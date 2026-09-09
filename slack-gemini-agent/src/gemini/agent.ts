import { getGeminiClient } from './client.js';
import { loadConfig } from '../config.js';
import { AGENT_SYSTEM_INSTRUCTION, AGENT_GENERATION_CONFIG } from './prompt.js';
import { TOOL_DECLARATIONS, executeTool } from './tools.js';
import { salesforceMcpClient } from '../mcp/salesforceMcpClient.js';
import { snowflakeMcpClient } from '../mcp/snowflakeMcpClient.js';

interface SessionEntry {
  chat: any;
  lastActive: number;
}

/**
 * Manages conversational chat sessions for multi-turn dialogues across Slack threads.
 */
export class GeminiAgentSessionManager {
  private sessions = new Map<string, SessionEntry>();
  private readonly sessionTtlMs = 2 * 60 * 60 * 1000; // 2 hours TTL

  constructor() {
    // Run periodic cleanup every 15 minutes to prevent memory leaks
    setInterval(() => this.cleanupExpiredSessions(), 15 * 60 * 1000);
  }

  /**
   * Retrieves an existing chat session or creates a new one configured with the agent's
   * system prompt and declared tools.
   */
  public getOrCreateChat(sessionId: string): any {
    const existing = this.sessions.get(sessionId);
    if (existing) {
      existing.lastActive = Date.now();
      return existing.chat;
    }

    const config = loadConfig(false);
    const ai = getGeminiClient();

    console.log(`[GeminiAgent] Initializing new chat session for ID: "${sessionId}" using model: ${config.geminiModel}`);

    // Dynamically assemble tools from Salesforce Hosted MCP and Snowflake MCP
    const mcpTools: any[] = [];

    if (salesforceMcpClient.isReady()) {
      salesforceMcpClient.getTools().forEach((t: any) => {
        mcpTools.push({
          name: t.name,
          description: t.description || 'Salesforce Hosted MCP Tool',
          parameters: t.inputSchema || { type: 'OBJECT', properties: {} },
        });
      });
    }

    if (snowflakeMcpClient.isReady()) {
      snowflakeMcpClient.getTools().forEach((t: any) => {
        mcpTools.push({
          name: t.name,
          description: t.description || 'Snowflake Secure Analytics MCP Tool',
          parameters: t.inputSchema || { type: 'OBJECT', properties: {} },
        });
      });
    }

    // Suppress legacy mock CRM and warehouse tools, retaining core utilities
    const coreTools = TOOL_DECLARATIONS.filter((t) => t.name === 'get_current_time');
    const activeTools = [...coreTools, ...mcpTools];
    console.log(`[GeminiAgent] Injected ${mcpTools.length} dynamic tool(s) (Salesforce MCP + Snowflake Secure MCP).`);

    const chat = ai.chats.create({
      model: config.geminiModel,
      config: {
        systemInstruction: AGENT_SYSTEM_INSTRUCTION,
        temperature: AGENT_GENERATION_CONFIG.temperature,
        topP: AGENT_GENERATION_CONFIG.topP,
        topK: AGENT_GENERATION_CONFIG.topK,
        tools: [
          {
            functionDeclarations: activeTools as any,
          },
        ],
      },
    });

    this.sessions.set(sessionId, {
      chat,
      lastActive: Date.now(),
    });

    return chat;
  }

  /**
   * Sends a user message to the Gemini Agent and handles any Function Calling loops
   * autonomously until a final synthesized response is produced.
   */
  public async processMessage(
    sessionId: string,
    message: string,
    onToolExecution?: (toolName: string, args: Record<string, any>) => void
  ): Promise<string> {
    const chat = this.getOrCreateChat(sessionId);

    console.log(`[GeminiAgent] Sending user message to session "${sessionId}": "${message}"`);
    
    // Helper function for adaptive retrying on transient 503/429 spikes
    const sendWithRetry = async (payload: any, retries = 4, initialDelayMs = 2500): Promise<any> => {
      let delayMs = initialDelayMs;
      for (let attempt = 1; attempt <= retries; attempt++) {
        try {
          return await chat.sendMessage(payload);
        } catch (err: any) {
          const isTransient = err?.message?.includes('503') || err?.message?.includes('429') || err?.status === 503 || err?.status === 429;
          if (isTransient && attempt < retries) {
            let waitMs = delayMs;
            const match = err?.message?.match(/retry in ([0-9.]+)s/i) || err?.message?.match(/retryDelay"?:\s*"([0-9.]+)s/i);
            if (match && match[1]) {
              const parsedSec = parseFloat(match[1]);
              if (!isNaN(parsedSec) && parsedSec > 0) {
                waitMs = Math.ceil(parsedSec * 1000) + 500;
              }
            }
            console.log(`[GeminiAgent] Transient rate limit / spike (attempt ${attempt}/${retries}). Waiting ${waitMs}ms before retrying...`);
            await new Promise((r) => setTimeout(r, waitMs));
            delayMs *= 2;
            continue;
          }
          throw err;
        }
      }
    };

    let response = await sendWithRetry({ message });

    // Track last executed MCP result for fail-safe zero-loss delivery
    let lastMcpResult: { toolName: string; result: any } | null = null;

    // Handle Function Calling Loop
    const maxToolIterations = 5;
    let iteration = 0;

    while (response.functionCalls && response.functionCalls.length > 0 && iteration < maxToolIterations) {
      iteration++;
      console.log(`[GeminiAgent] Tool invocation detected (turn ${iteration}):`, response.functionCalls);

      const responseParts: any[] = [];

      for (const call of response.functionCalls) {
        if (onToolExecution) {
          onToolExecution(call.name, call.args || {});
        }

        try {
          let toolResult: any;
          const isSfMcpTool = salesforceMcpClient.isReady() && salesforceMcpClient.getTools().some((t: any) => t.name === call.name);
          const isSnowMcpTool = snowflakeMcpClient.isReady() && snowflakeMcpClient.hasTool(call.name);

          if (isSnowMcpTool) {
            console.log(`[GeminiAgent] Routing tool call "${call.name}" to Snowflake MCP Client (LEARNDC_MCP_DB.SECURE_ANALYTICS)...`);
            toolResult = await snowflakeMcpClient.callTool(call.name, call.args || {});
            lastMcpResult = { toolName: call.name, result: toolResult };
          } else if (isSfMcpTool) {
            console.log(`[GeminiAgent] Routing tool call "${call.name}" to LearnDC Agent MCP Server...`);
            toolResult = await salesforceMcpClient.callTool(call.name, call.args || {});
            lastMcpResult = { toolName: call.name, result: toolResult };
          } else {
            toolResult = await executeTool(call.name, call.args || {});
          }

          responseParts.push({
            functionResponse: {
              name: call.name,
              id: call.id,
              response: { result: toolResult },
            },
          });
        } catch (toolError: any) {
          console.error(`[GeminiAgent] Error executing tool "${call.name}":`, toolError);
          responseParts.push({
            functionResponse: {
              name: call.name,
              id: call.id,
              response: { error: toolError?.message || 'Tool execution failed' },
            },
          });
        }
      }

      // Feed function responses back into Gemini chat with zero-loss fallback
      try {
        response = await sendWithRetry({ message: responseParts });
      } catch (feedError: any) {
        // If Gemini throttles during synthesis, but we already fetched the real data from MCP, rescue it!
        if (lastMcpResult && lastMcpResult.result) {
          console.warn(`[GeminiAgent] Rate limit encountered during LLM synthesis. Rescuing with direct LearnDC MCP card formatting.`);
          return formatDirectMcpOutput(lastMcpResult.toolName, lastMcpResult.result);
        }
        throw feedError;
      }
    }

    const outputText = response.text || 'I processed your request, but no textual output was generated.';
    return outputText;
  }

  /**
   * Cleans up sessions that have been idle longer than the TTL.
   */
  private cleanupExpiredSessions(): void {
    const now = Date.now();
    for (const [id, entry] of this.sessions.entries()) {
      if (now - entry.lastActive > this.sessionTtlMs) {
        console.log(`[GeminiAgent] Evicting expired session: "${id}"`);
        this.sessions.delete(id);
      }
    }
  }

  /**
   * Reset / clear a specific session (useful for resetting conversations).
   */
  public clearSession(sessionId: string): void {
    this.sessions.delete(sessionId);
  }
}

// Global Agent Session Manager Singleton
export const agentSessionManager = new GeminiAgentSessionManager();

/**
 * Formats raw Salesforce MCP output directly into a rich Slack-ready message
 * in the event that Gemini encounters a transient rate limit during final synthesis.
 */
function formatDirectMcpOutput(toolName: string, data: any): string {
  if (toolName === 'snowflake_get_account_telemetry') {
    if (!data.isFound) {
      return `ℹ️ *Account Health & Utilization*\nNo telemetry records found for this account.`;
    }
    return `*Account Health & Platform Utilization*\n\n` +
      `• *Account*: *${data.accountName || 'N/A'}*\n` +
      `• *Health Rating*: *${data.healthScore || 85} / 100* (${data.healthStatus || 'FAIR'})\n` +
      `• *Platform Usage*: *${data.usageHours || 0}* Compute Hours\n` +
      `• *Risk Level*: *${data.churnRisk || 'LOW'}*\n` +
      `• *Support Entitlement*: *${data.slaTier || 'Standard'}*`;
  }

  if (toolName === 'LearnDCMCPAccountAction') {
    if (!data.isFound) {
      return `❌ *Account Not Found*\nNo matching account was found. Please verify the account name or keyword.`;
    }
    return `*Account Overview*\n\n` +
      `• *Account Name*: *${data.accountName || 'N/A'}*\n` +
      `• *Account ID*: \`${data.accountId || 'N/A'}\`\n` +
      `• *Industry*: ${data.industry || 'Not Specified'}\n` +
      `• *Assigned Account Manager*: ${data.csmEmail ? `\`${data.csmEmail}\`` : '_None Assigned_'}\n` +
      `• *Primary Contact*: ${data.primaryContactName || 'None'} ${data.primaryContactEmail ? `(\`${data.primaryContactEmail}\`)` : ''}\n` +
      (data.contactSummary ? `• *Key Contacts*: ${data.contactSummary}\n` : '');
  }

  if (toolName === 'LearnDCMCPThreadAction') {
    if (!data.isFound) {
      return `ℹ️ *Recent Customer Intelligence*\nNo recent customer communications found for this account.`;
    }
    return `*Recent Customer Intelligence*\n\n` +
      `• *Account*: *${data.accountName || 'N/A'}*\n` +
      `• *Thread ID*: \`${data.threadId || 'N/A'}\` (Messages analyzed: ${data.messageCount || 0})\n\n` +
      `*Executive Summary:*\n${data.executiveSummary || 'N/A'}\n\n` +
      (data.keyPoints ? `*Key Points:*\n${data.keyPoints}\n\n` : '') +
      (data.actionItems ? `*Action Items:*\n${data.actionItems}` : '');
  }

  if (toolName === 'LearnDCMCPMeetingAction') {
    if (!data.isSuccess) {
      return `❌ *Meeting Scheduling Failed*\n${data.message || 'Unknown error'}`;
    }
    return `✅ *Meeting Scheduled Successfully*\n\n` +
      `• *Event Record*: \`${data.eventId || 'Created'}\`\n` +
      `• *Google Meet Video Link*: ${data.googleMeetLink ? `<${data.googleMeetLink}|Join Google Meet>` : '_None_'}\n` +
      `• *Status*: ${data.message || 'Synced'}`;
  }

  return `*Salesforce Data (LearnDC Agent MCP Server)*\n\n\`\`\`json\n${JSON.stringify(data, null, 2)}\n\`\`\``;
}
