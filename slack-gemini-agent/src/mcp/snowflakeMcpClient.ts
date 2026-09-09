import snowflake from 'snowflake-sdk';
import { loadConfig } from '../config.js';
import { McpToolDefinition } from './salesforceMcpClient.js';

// Suppress internal SDK logging
snowflake.configure({ logLevel: 'WARN' });

export interface SecureAccountTelemetryDTO {
  isFound: boolean;
  sfAccountId?: string;
  accountName?: string;
  slaTier?: string;
  healthScore?: number;
  healthStatus?: string;
  usageHours?: number;
  churnRisk?: string;
  telemetryLastUpdated?: string;
  message?: string;
}

/**
 * Snowflake MCP Client
 * 
 * Provides standardized Model Context Protocol (MCP) access to Snowflake Cloud Data Warehouse.
 * Connects strictly with the least-privileged read-only role (MCP_AGENT_READER_ROLE) to
 * the dedicated database (LEARNDC_MCP_DB) and secure view (V_ACCOUNT_INSIGHTS).
 * 
 * Exposes strictly 8 sanitized telemetry fields, with zero financial or internal CRM exposure.
 */
export class SnowflakeMcpClient {
  private static instance: SnowflakeMcpClient;
  private isInitialized = false;

  private constructor() {}

  public static getInstance(): SnowflakeMcpClient {
    if (!SnowflakeMcpClient.instance) {
      SnowflakeMcpClient.instance = new SnowflakeMcpClient();
    }
    return SnowflakeMcpClient.instance;
  }

  public async initialize(): Promise<boolean> {
    const config = loadConfig(false);
    if (!config.snowflakeAccount || !config.snowflakeUsername || !config.snowflakePassword) {
      console.warn('[SnowflakeMCP] Credentials not configured in .env');
      return false;
    }
    this.isInitialized = true;
    console.log('[SnowflakeMCP] Initialized Snowflake MCP Client bound to LEARNDC_MCP_DB.SECURE_ANALYTICS (Role: MCP_AGENT_READER_ROLE).');
    return true;
  }

  public isReady(): boolean {
    return this.isInitialized;
  }

  /**
   * Creates a read-only Snowflake connection bound to the MCP database, schema, and role.
   */
  private createReadOnlyConnection(): snowflake.Connection {
    const config = loadConfig(false);
    return snowflake.createConnection({
      account: config.snowflakeAccount!,
      username: config.snowflakeUsername!,
      password: config.snowflakePassword!,
      warehouse: 'COMPUTE_WH',
      database: 'LEARNDC_MCP_DB',
      schema: 'SECURE_ANALYTICS',
      role: 'MCP_AGENT_READER_ROLE',
    });
  }

  /**
   * Executes a read-only query against the Secure View.
   */
  private async executeQuery<T = any>(sqlText: string, binds: any[] = []): Promise<T[]> {
    const conn = this.createReadOnlyConnection();
    return new Promise<T[]>((resolve, reject) => {
      conn.connect((err) => {
        if (err) {
          console.error('[SnowflakeMCP] Connection error:', err.message);
          return reject(err);
        }
        conn.execute({
          sqlText,
          binds,
          complete: (execErr, _stmt, rows) => {
            conn.destroy(() => {});
            if (execErr) {
              console.error('[SnowflakeMCP] Query execution error:', execErr.message);
              return reject(execErr);
            }
            resolve((rows || []) as T[]);
          },
        });
      });
    });
  }

  /**
   * Returns tool declarations conforming to the Model Context Protocol (MCP) specification.
   */
  public getTools(): McpToolDefinition[] {
    return [
      {
        name: 'snowflake_get_account_telemetry',
        description: 'Retrieves sanitized customer health, status (EXCELLENT/FAIR/AT RISK), usage hours, SLA tier, and churn risk from the Snowflake secure analytics view.',
        inputSchema: {
          type: 'OBJECT',
          properties: {
            accountIdentifier: {
              type: 'STRING',
              description: 'The Account Name or Salesforce 18-character Account ID (e.g. "Apex Global Innovations" or "001fj00001qAtYCAA0").',
            },
          },
          required: ['accountIdentifier'],
        },
      },
      {
        name: 'snowflake_list_at_risk_accounts',
        description: 'Lists accounts displaying elevated churn risk (HIGH) or low health scores (<60) from the Snowflake secure analytics view.',
        inputSchema: {
          type: 'OBJECT',
          properties: {
            maxResults: {
              type: 'INTEGER',
              description: 'Maximum number of records to return (default: 5).',
            },
          },
        },
      },
    ];
  }

  public hasTool(name: string): boolean {
    return this.getTools().some((t) => t.name === name);
  }

  /**
   * Executes the specified MCP Tool and returns the result.
   */
  public async callTool(toolName: string, args: Record<string, any>): Promise<any> {
    console.log(`[SnowflakeMCP] Executing tool "${toolName}" with args:`, JSON.stringify(args));

    switch (toolName) {
      case 'snowflake_get_account_telemetry': {
        const identifier = (args.accountIdentifier || '').trim();
        if (!identifier) {
          return { isFound: false, message: 'Account identifier is required.' };
        }

        const sql = `
          SELECT 
            SF_ACCOUNT_ID,
            ACCOUNT_NAME,
            SLA_TIER,
            HEALTH_SCORE,
            HEALTH_STATUS,
            USAGE_HOURS,
            CHURN_RISK,
            SNOWFLAKE_LAST_UPDATED
          FROM LEARNDC_MCP_DB.SECURE_ANALYTICS.V_ACCOUNT_INSIGHTS
          WHERE SF_ACCOUNT_ID = ? OR LOWER(ACCOUNT_NAME) = LOWER(?) OR LOWER(ACCOUNT_NAME) LIKE LOWER(?)
          ORDER BY SNOWFLAKE_LAST_UPDATED DESC NULLS LAST
          LIMIT 1
        `;

        const likePattern = `%${identifier}%`;
        const rows = await this.executeQuery<any>(sql, [identifier, identifier, likePattern]);

        if (!rows || rows.length === 0) {
          return {
            isFound: false,
            message: `No telemetry insights found for account "${identifier}".`,
          };
        }

        const r = rows[0];
        const res: SecureAccountTelemetryDTO = {
          isFound: true,
          sfAccountId: r.SF_ACCOUNT_ID || r.sf_account_id,
          accountName: r.ACCOUNT_NAME || r.account_name,
          slaTier: r.SLA_TIER || r.sla_tier,
          healthScore: r.HEALTH_SCORE !== undefined ? Number(r.HEALTH_SCORE) : 85,
          healthStatus: r.HEALTH_STATUS || r.health_status || 'FAIR',
          usageHours: r.USAGE_HOURS !== undefined ? Number(r.USAGE_HOURS) : 0,
          churnRisk: r.CHURN_RISK || r.churn_risk || 'LOW',
          telemetryLastUpdated: r.SNOWFLAKE_LAST_UPDATED || r.snowflake_last_updated,
        };
        return res;
      }

      case 'snowflake_list_at_risk_accounts': {
        const limit = args.maxResults ? Number(args.maxResults) : 5;
        const sql = `
          SELECT 
            SF_ACCOUNT_ID,
            ACCOUNT_NAME,
            SLA_TIER,
            HEALTH_SCORE,
            HEALTH_STATUS,
            USAGE_HOURS,
            CHURN_RISK,
            SNOWFLAKE_LAST_UPDATED
          FROM LEARNDC_MCP_DB.SECURE_ANALYTICS.V_ACCOUNT_INSIGHTS
          WHERE CHURN_RISK = 'HIGH' OR HEALTH_SCORE < 60
          ORDER BY HEALTH_SCORE ASC
          LIMIT ?
        `;

        const rows = await this.executeQuery<any>(sql, [limit]);
        return {
          count: rows.length,
          accounts: rows.map((r: any) => ({
            sfAccountId: r.SF_ACCOUNT_ID || r.sf_account_id,
            accountName: r.ACCOUNT_NAME || r.account_name,
            slaTier: r.SLA_TIER || r.sla_tier,
            healthScore: Number(r.HEALTH_SCORE),
            healthStatus: r.HEALTH_STATUS || r.health_status,
            usageHours: Number(r.USAGE_HOURS),
            churnRisk: r.CHURN_RISK || r.churn_risk,
          })),
        };
      }

      default:
        throw new Error(`Unknown Snowflake MCP tool: "${toolName}"`);
    }
  }
}

export const snowflakeMcpClient = SnowflakeMcpClient.getInstance();
