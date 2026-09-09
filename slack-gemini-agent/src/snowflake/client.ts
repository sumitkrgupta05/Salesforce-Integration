import snowflake from 'snowflake-sdk';
import { loadConfig } from '../config.js';

// Suppress noisy internal SDK debug logs
snowflake.configure({ logLevel: 'WARN' });

export interface SnowflakeQueryResult<T = any> {
  rows: T[];
  statementId?: string;
}

export class SnowflakeClient {
  private static instance: SnowflakeClient;
  private isConfigured = false;

  private constructor() {
    const config = loadConfig();
    this.isConfigured = Boolean(
      config.snowflakeAccount &&
      config.snowflakeUsername &&
      config.snowflakePassword
    );
  }

  public static getInstance(): SnowflakeClient {
    if (!SnowflakeClient.instance) {
      SnowflakeClient.instance = new SnowflakeClient();
    }
    return SnowflakeClient.instance;
  }

  public hasValidConfiguration(): boolean {
    return this.isConfigured;
  }

  /**
   * Creates a Snowflake connection instance.
   * @param includeDbSchema Whether to bind directly to the configured database/schema
   */
  private createConnection(includeDbSchema = true): snowflake.Connection {
    const config = loadConfig();
    if (!this.isConfigured) {
      throw new Error('Snowflake credentials (account, username, password) are not configured in .env');
    }

    const connectionOptions: snowflake.ConnectionOptions = {
      account: config.snowflakeAccount!,
      username: config.snowflakeUsername!,
      password: config.snowflakePassword!,
      warehouse: config.snowflakeWarehouse || 'COMPUTE_WH',
    };

    if (includeDbSchema) {
      if (config.snowflakeDatabase) {
        connectionOptions.database = config.snowflakeDatabase;
      }
      if (config.snowflakeSchema) {
        connectionOptions.schema = config.snowflakeSchema;
      }
    }

    return snowflake.createConnection(connectionOptions);
  }

  /**
   * Executes a single SQL query against Snowflake and returns the result rows as a Promise.
   */
  public async executeQuery<T = any>(sqlText: string, binds: any[] = [], includeDbSchema = true): Promise<T[]> {
    const connection = this.createConnection(includeDbSchema);

    return new Promise<T[]>((resolve, reject) => {
      connection.connect((err, conn) => {
        if (err) {
          console.error('[SnowflakeClient] Connection failed:', err.message);
          return reject(err);
        }

        conn.execute({
          sqlText,
          binds,
          complete: (execErr, _stmt, rows) => {
            // Always destroy / close the connection after execution
            conn.destroy((destroyErr) => {
              if (destroyErr) {
                console.warn('[SnowflakeClient] Error closing connection:', destroyErr.message);
              }
            });

            if (execErr) {
              console.error('[SnowflakeClient] Query execution error:', execErr.message, '\nSQL:', sqlText);
              return reject(execErr);
            }

            resolve((rows || []) as T[]);
          },
        });
      });
    });
  }

  /**
   * Tests the connection with a lightweight query (SELECT CURRENT_USER(), CURRENT_ACCOUNT(), CURRENT_VERSION()).
   */
  public async testConnection(): Promise<{ currentUser: string; currentAccount: string; version: string; currentWarehouse: string }> {
    const rows = await this.executeQuery<any>(
      'SELECT CURRENT_USER() AS "user", CURRENT_ACCOUNT() AS "account", CURRENT_VERSION() AS "version", CURRENT_WAREHOUSE() AS "warehouse"',
      [],
      false // don't bind to db/schema yet in case they don't exist
    );

    if (!rows || rows.length === 0) {
      throw new Error('Snowflake returned empty response from test connection query.');
    }

    return {
      currentUser: rows[0].user || rows[0].USER,
      currentAccount: rows[0].account || rows[0].ACCOUNT,
      version: rows[0].version || rows[0].VERSION,
      currentWarehouse: rows[0].warehouse || rows[0].WAREHOUSE,
    };
  }
}

export const snowflakeClient = SnowflakeClient.getInstance();
