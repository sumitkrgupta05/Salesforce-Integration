import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { SSEClientTransport } from '@modelcontextprotocol/sdk/client/sse.js';
import { EventSource } from 'eventsource';
import { loadConfig } from '../config.js';
import { getSalesforceCredentials, SalesforceCredentials } from './salesforceAuth.js';

// Polyfill global EventSource for Node.js runtime if not present
if (typeof (global as any).EventSource === 'undefined') {
  (global as any).EventSource = EventSource;
}

export interface McpToolDefinition {
  name: string;
  description: string;
  inputSchema: {
    type: string;
    properties: Record<string, any>;
    required?: string[];
  };
}

/**
 * Salesforce Hosted MCP Client with Automatic Direct-Execution Bridge.
 * 
 * Mode 1 (SSE Gateway): Connects over SSE to api.salesforce.com/platform/mcp/v1/... (requires ECA).
 * Mode 2 (Direct Apex Bridge): Executes the deployed Invocable Actions directly against learn_dc REST API,
 *                             guaranteeing 100% functionality with active CLI credentials.
 */
export class SalesforceHostedMcpClient {
  private client: Client | null = null;
  private transport: SSEClientTransport | null = null;
  private connected = false;
  private mode: 'sse' | 'direct' | 'none' = 'none';
  private creds: SalesforceCredentials | null = null;
  private cachedTools: McpToolDefinition[] = [];

  /**
   * Initializes connection to Salesforce MCP Server.
   */
  public async initialize(): Promise<boolean> {
    const config = loadConfig(false);

    try {
      this.creds = await getSalesforceCredentials();
    } catch (err: any) {
      console.warn(`[SalesforceMCP] Could not resolve Salesforce credentials: ${err.message}`);
      return false;
    }

    // 1. Try connecting via SSE if SF_MCP_ENDPOINT_URL is configured
    if (config.sfMcpEndpointUrl) {
      try {
        console.log(`[SalesforceMCP] Attempting SSE connection to: ${config.sfMcpEndpointUrl}...`);

        this.client = new Client(
          {
            name: 'slack-gemini-agent-client',
            version: '1.0.0',
          },
          {
            capabilities: {},
          }
        );

        this.transport = new SSEClientTransport(new URL(config.sfMcpEndpointUrl), {
          eventSourceInit: {
            headers: {
              Authorization: `Bearer ${this.creds.accessToken}`,
            },
          } as any,
          requestInit: {
            headers: {
              Authorization: `Bearer ${this.creds.accessToken}`,
              'Content-Type': 'application/json',
            },
          },
        });

        await this.client.connect(this.transport);
        this.connected = true;
        this.mode = 'sse';
        console.log('✅ [SalesforceMCP] Connected via SSE to Salesforce Hosted MCP Server!');

        const toolsResult = await this.client.listTools();
        this.cachedTools = (toolsResult.tools as McpToolDefinition[]) || [];
        console.log(`[SalesforceMCP] Discovered ${this.cachedTools.length} tool(s) via SSE:`, 
          this.cachedTools.map(t => t.name)
        );
        return true;
      } catch (sseError: any) {
        console.warn(`[SalesforceMCP] SSE Gateway returned: ${sseError.message}`);
        console.log('[SalesforceMCP] Engaging Direct Invocable Action Bridge to learn_dc...');
      }
    }

    // 2. Fallback to Direct Invocable Actions Bridge on learn_dc
    return this.initializeDirectBridge();
  }

  /**
   * Registers the deployed Invocable Actions as live MCP tools on learn_dc.
   */
  private initializeDirectBridge(): boolean {
    if (!this.creds) return false;

    this.cachedTools = [
      {
        name: 'LearnDCMCPAccountAction',
        description: 'Retrieves live Salesforce Account details, assigned CSM email (Account.CSM_Email__c), industry, and primary contacts from learn_dc.',
        inputSchema: {
          type: 'object',
          properties: {
            accountIdentifier: {
              type: 'string',
              description: 'The name or Salesforce record ID of the Account to look up.',
            },
          },
          required: ['accountIdentifier'],
        },
      },
      {
        name: 'LearnDCMCPThreadAction',
        description: 'Retrieves the AI-generated executive email summary, discussion highlights, and action items for a customer from Gmail_Thread_Summary__c in Salesforce.',
        inputSchema: {
          type: 'object',
          properties: {
            accountIdentifier: {
              type: 'string',
              description: 'The name or Salesforce record ID of the Account.',
            },
            threadId: {
              type: 'string',
              description: 'Optional specific Gmail Thread ID.',
            },
          },
        },
      },
      {
        name: 'LearnDCMCPMeetingAction',
        description: 'Schedules a customer meeting with automated Google Meet video link and inserts the Salesforce Event record in learn_dc.',
        inputSchema: {
          type: 'object',
          properties: {
            accountIdentifier: {
              type: 'string',
              description: 'Account Name or ID for meeting context.',
            },
            subject: {
              type: 'string',
              description: 'Subject/title of the meeting.',
            },
            startDateTime: {
              type: 'string',
              description: 'Meeting start date and time in ISO-8601 format.',
            },
            durationMinutes: {
              type: 'number',
              description: 'Duration of the meeting in minutes (default 30).',
            },
            attendeeEmail: {
              type: 'string',
              description: 'Attendee email address.',
            },
            description: {
              type: 'string',
              description: 'Meeting agenda or description.',
            },
          },
          required: ['accountIdentifier', 'subject', 'startDateTime'],
        },
      },
    ];

    this.connected = true;
    this.mode = 'direct';
    console.log(`✅ [SalesforceMCP] Direct Invocable Actions Bridge active for "${this.creds.orgAlias}" (${this.creds.instanceUrl})!`);
    console.log(`[SalesforceMCP] Registered ${this.cachedTools.length} live Salesforce tool(s):`, 
      this.cachedTools.map(t => t.name)
    );
    return true;
  }

  public isReady(): boolean {
    return this.connected && (this.mode === 'sse' || this.mode === 'direct');
  }

  public getTools(): McpToolDefinition[] {
    return this.cachedTools;
  }

  /**
   * Calls a tool either via SSE client or direct Salesforce Invocable Action REST endpoint.
   */
  public async callTool(name: string, args: Record<string, any>): Promise<any> {
    if (!this.connected) {
      throw new Error(`Salesforce MCP Client is not connected. Cannot invoke tool "${name}".`);
    }

    if (this.mode === 'sse' && this.client) {
      console.log(`[SalesforceMCP] Invoking tool "${name}" via SSE Gateway:`, JSON.stringify(args));
      return await this.client.callTool({ name, arguments: args });
    }

    // Direct Invocable Action Execution on learn_dc
    if (this.mode === 'direct' && this.creds) {
      console.log(`[SalesforceMCP] Invoking Invocable Action "${name}" directly on ${this.creds.instanceUrl}:`, JSON.stringify(args));
      const actionUrl = `${this.creds.instanceUrl}/services/data/v67.0/actions/custom/apex/${name}`;

      let response = await fetch(actionUrl, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.creds.accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          inputs: [args],
        }),
      });

      // Self-healing: if session expired (HTTP 401 / INVALID_SESSION_ID), automatically refresh credentials and retry once
      if (response.status === 401) {
        console.warn(`[SalesforceMCP] Action "${name}" encountered HTTP 401 (Session expired/invalid). Refreshing credentials...`);
        try {
          this.creds = await getSalesforceCredentials(true);
          const retryUrl = `${this.creds.instanceUrl}/services/data/v67.0/actions/custom/apex/${name}`;
          console.log(`[SalesforceMCP] Retrying Invocable Action "${name}" with fresh credentials...`);
          response = await fetch(retryUrl, {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${this.creds.accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              inputs: [args],
            }),
          });
        } catch (refreshErr: any) {
          console.error(`[SalesforceMCP] Failed to auto-refresh credentials on 401:`, refreshErr.message);
        }
      }

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Salesforce action "${name}" failed with HTTP ${response.status}: ${errorText}`);
      }

      const resultData = await response.json();
      if (Array.isArray(resultData) && resultData.length > 0) {
        const actionResult = resultData[0];
        if (actionResult.isSuccess) {
          return actionResult.outputValues;
        } else {
          throw new Error(`Salesforce action reported errors: ${JSON.stringify(actionResult.errors)}`);
        }
      }
      return resultData;
    }

    throw new Error('Unsupported execution mode in Salesforce MCP Client.');
  }

  public async disconnect(): Promise<void> {
    if (this.transport) {
      await this.transport.close();
    }
    this.connected = false;
    this.mode = 'none';
  }
}

export const salesforceMcpClient = new SalesforceHostedMcpClient();
