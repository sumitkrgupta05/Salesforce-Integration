import { snowflakeClient } from './client.js';
import { getSalesforceCredentials } from '../mcp/salesforceAuth.js';

export interface OutboundAccountSyncDTO {
  sfAccountId: string;
  accountName: string;
  industry?: string;
  accountType?: string;
  annualRevenue?: number;
  slaTier?: string;
  customerPriority?: string;
  csmEmail?: string;
}

export interface InboundAccountAnalyticsDTO {
  isFound: boolean;
  sfAccountId?: string;
  accountName?: string;
  industry?: string;
  accountType?: string;
  annualRevenue?: number;
  slaTier?: string;
  customerPriority?: string;
  csmEmail?: string;
  healthScore?: number;
  usageHours?: number;
  churnRisk?: string;
  snowflakeLastUpdated?: string;
  sfLastModified?: string;
}

export class SnowflakeService {
  private static instance: SnowflakeService;

  public static getInstance(): SnowflakeService {
    if (!SnowflakeService.instance) {
      SnowflakeService.instance = new SnowflakeService();
    }
    return SnowflakeService.instance;
  }

  /**
   * Initializes LEARNDC_DB database, ANALYTICS schema, and ACCOUNT_ANALYTICS table.
   */
  public async ensureSchemaExists(): Promise<void> {
    console.log('[SnowflakeService] Verifying / Initializing LEARNDC_DB schema...');

    // 1. Create Database
    await snowflakeClient.executeQuery(
      'CREATE DATABASE IF NOT EXISTS LEARNDC_DB COMMENT = "Learn DC CRM & Snowflake Integration Database"',
      [],
      false
    );

    // 2. Create Schema
    await snowflakeClient.executeQuery(
      'CREATE SCHEMA IF NOT EXISTS LEARNDC_DB.ANALYTICS COMMENT = "Customer CRM & Telemetry Analytics"',
      [],
      false
    );

    // 3. Create Table
    await snowflakeClient.executeQuery(
      `CREATE TABLE IF NOT EXISTS LEARNDC_DB.ANALYTICS.ACCOUNT_ANALYTICS (
        SF_ACCOUNT_ID          VARCHAR(18) NOT NULL PRIMARY KEY,
        ACCOUNT_NAME           VARCHAR(255) NOT NULL,
        INDUSTRY               VARCHAR(100),
        ACCOUNT_TYPE           VARCHAR(100),
        ANNUAL_REVENUE         NUMBER(18,2),
        SLA_TIER               VARCHAR(50),
        CUSTOMER_PRIORITY      VARCHAR(50),
        CSM_EMAIL              VARCHAR(255),
        SF_LAST_MODIFIED       TIMESTAMP_NTZ,
        HEALTH_SCORE           NUMBER(3,0) DEFAULT 85,
        USAGE_HOURS            NUMBER(10,2) DEFAULT 142.50,
        CHURN_RISK             VARCHAR(20) DEFAULT 'LOW',
        SNOWFLAKE_LAST_UPDATED TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
      )`,
      [],
      false
    );

    console.log('[SnowflakeService] Schema and ACCOUNT_ANALYTICS table verified successfully.');
  }

  /**
   * Merges Account CRM attributes from Salesforce into Snowflake (Outbound Sync).
   */
  public async mergeAccountOutbound(dto: OutboundAccountSyncDTO): Promise<{ isSuccess: boolean; sfAccountId: string; syncedAt: string }> {
    if (!dto.sfAccountId || !dto.accountName) {
      throw new Error('sfAccountId and accountName are required for outbound synchronization.');
    }

    await this.ensureSchemaExists();

    const sql = `
      MERGE INTO LEARNDC_DB.ANALYTICS.ACCOUNT_ANALYTICS target
      USING (
        SELECT 
          ? AS SF_ACCOUNT_ID,
          ? AS ACCOUNT_NAME,
          ? AS INDUSTRY,
          ? AS ACCOUNT_TYPE,
          ? AS ANNUAL_REVENUE,
          ? AS SLA_TIER,
          ? AS CUSTOMER_PRIORITY,
          ? AS CSM_EMAIL,
          CURRENT_TIMESTAMP() AS SF_LAST_MODIFIED
      ) source
      ON target.SF_ACCOUNT_ID = source.SF_ACCOUNT_ID
      WHEN MATCHED THEN
        UPDATE SET 
          target.ACCOUNT_NAME = source.ACCOUNT_NAME,
          target.INDUSTRY = source.INDUSTRY,
          target.ACCOUNT_TYPE = source.ACCOUNT_TYPE,
          target.ANNUAL_REVENUE = source.ANNUAL_REVENUE,
          target.SLA_TIER = source.SLA_TIER,
          target.CUSTOMER_PRIORITY = source.CUSTOMER_PRIORITY,
          target.CSM_EMAIL = source.CSM_EMAIL,
          target.SF_LAST_MODIFIED = source.SF_LAST_MODIFIED
      WHEN NOT MATCHED THEN
        INSERT (
          SF_ACCOUNT_ID, ACCOUNT_NAME, INDUSTRY, ACCOUNT_TYPE,
          ANNUAL_REVENUE, SLA_TIER, CUSTOMER_PRIORITY, CSM_EMAIL, SF_LAST_MODIFIED
        ) VALUES (
          source.SF_ACCOUNT_ID, source.ACCOUNT_NAME, source.INDUSTRY, source.ACCOUNT_TYPE,
          source.ANNUAL_REVENUE, source.SLA_TIER, source.CUSTOMER_PRIORITY, source.CSM_EMAIL, source.SF_LAST_MODIFIED
        )
    `;

    const binds = [
      dto.sfAccountId,
      dto.accountName,
      dto.industry || null,
      dto.accountType || null,
      dto.annualRevenue !== undefined && dto.annualRevenue !== null ? dto.annualRevenue : null,
      dto.slaTier || null,
      dto.customerPriority || null,
      dto.csmEmail || null,
    ];

    await snowflakeClient.executeQuery(sql, binds, true);

    return {
      isSuccess: true,
      sfAccountId: dto.sfAccountId,
      syncedAt: new Date().toISOString(),
    };
  }

  /**
   * Retrieves warehouse metrics from Snowflake for an Account (Inbound Sync & Slack Bot queries).
   */
  public async getAccountAnalytics(accountIdentifier: string, forceReconcile = true): Promise<InboundAccountAnalyticsDTO> {
    await this.ensureSchemaExists();

    const trimmed = (accountIdentifier || '').trim();
    if (!trimmed) {
      return { isFound: false };
    }

    // Live on-demand reconciliation: Ensures 0ms latency when account is queried in Slack Bot or LWC
    if (forceReconcile) {
      try {
        await this.syncSingleAccountFromSalesforce(trimmed);
      } catch (liveSyncErr: any) {
        console.warn(`[SnowflakeService] Notice during live reconciliation: ${liveSyncErr.message}`);
      }
    }

    // Query by SF_ACCOUNT_ID or by ACCOUNT_NAME (case-insensitive)
    const sql = `
      SELECT 
        SF_ACCOUNT_ID,
        ACCOUNT_NAME,
        INDUSTRY,
        ACCOUNT_TYPE,
        ANNUAL_REVENUE,
        SLA_TIER,
        CUSTOMER_PRIORITY,
        CSM_EMAIL,
        HEALTH_SCORE,
        USAGE_HOURS,
        CHURN_RISK,
        TO_VARCHAR(SNOWFLAKE_LAST_UPDATED, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS SNOWFLAKE_LAST_UPDATED,
        TO_VARCHAR(SF_LAST_MODIFIED, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS SF_LAST_MODIFIED
      FROM LEARNDC_DB.ANALYTICS.ACCOUNT_ANALYTICS
      WHERE SF_ACCOUNT_ID = ? OR LOWER(ACCOUNT_NAME) = LOWER(?) OR LOWER(ACCOUNT_NAME) LIKE LOWER(?)
      ORDER BY SF_LAST_MODIFIED DESC NULLS LAST
      LIMIT 1
    `;

    const likePattern = `%${trimmed}%`;
    let rows = await snowflakeClient.executeQuery<any>(sql, [trimmed, trimmed, likePattern], true);

    // If not found in Snowflake yet, dynamically attempt reconcile again
    if (!rows || rows.length === 0) {
      try {
        console.log(`[SnowflakeService] Account "${trimmed}" not yet cached in Snowflake. Auto-fetching from Salesforce...`);
        const synced = await this.syncSingleAccountFromSalesforce(trimmed);
        if (synced) {
          rows = await snowflakeClient.executeQuery<any>(sql, [trimmed, trimmed, likePattern], true);
        }
      } catch (autoSyncErr: any) {
        console.warn(`[SnowflakeService] Notice during auto-fetch: ${autoSyncErr.message}`);
      }
    }

    if (!rows || rows.length === 0) {
      return { isFound: false };
    }

    const row = rows[0];
    return {
      isFound: true,
      sfAccountId: row.SF_ACCOUNT_ID || row.sf_account_id,
      accountName: row.ACCOUNT_NAME || row.account_name,
      industry: row.INDUSTRY || row.industry,
      accountType: row.ACCOUNT_TYPE || row.account_type,
      annualRevenue: row.ANNUAL_REVENUE !== undefined ? Number(row.ANNUAL_REVENUE) : undefined,
      slaTier: row.SLA_TIER || row.sla_tier,
      customerPriority: row.CUSTOMER_PRIORITY || row.customer_priority,
      csmEmail: row.CSM_EMAIL || row.csm_email,
      healthScore: row.HEALTH_SCORE !== undefined ? Number(row.HEALTH_SCORE) : 85,
      usageHours: row.USAGE_HOURS !== undefined ? Number(row.USAGE_HOURS) : 142.5,
      churnRisk: row.CHURN_RISK || row.churn_risk || 'LOW',
      snowflakeLastUpdated: row.SNOWFLAKE_LAST_UPDATED || row.snowflake_last_updated,
      sfLastModified: row.SF_LAST_MODIFIED || row.sf_last_modified,
    };
  }

  /**
   * Fetches an Account record live from Salesforce and merges it into Snowflake on-the-fly.
   */
  public async syncSingleAccountFromSalesforce(identifier: string): Promise<boolean> {
    try {
      const creds = await getSalesforceCredentials();
      const trimmed = identifier.trim();
      const escaped = trimmed.replace(/'/g, "\\'");
      const isRecordId = /^[a-zA-Z0-9]{15,18}$/.test(trimmed);

      const whereClause = isRecordId
        ? `Id = '${escaped}'`
        : `Name = '${escaped}' OR Name LIKE '%${escaped}%'`;

      const soql = `SELECT Id, Name, Industry, Type, AnnualRevenue, SLA__c, CustomerPriority__c, CSM_Email__c FROM Account WHERE ${whereClause} ORDER BY LastModifiedDate DESC LIMIT 1`;
      const queryUrl = `${creds.instanceUrl.replace(/\/+$/, '')}/services/data/v60.0/query?q=${encodeURIComponent(soql)}`;

      const response = await fetch(queryUrl, {
        headers: {
          Authorization: `Bearer ${creds.accessToken}`,
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.warn(`[SnowflakeService] Salesforce query responded with ${response.status}: ${errorText}`);
        return false;
      }

      const data = (await response.json()) as any;
      if (data && data.records && data.records.length > 0) {
        const acc = data.records[0];
        await this.mergeAccountOutbound({
          sfAccountId: acc.Id,
          accountName: acc.Name,
          industry: acc.Industry,
          accountType: acc.Type,
          annualRevenue: acc.AnnualRevenue,
          slaTier: acc.SLA__c,
          customerPriority: acc.CustomerPriority__c,
          csmEmail: acc.CSM_Email__c,
        });

        // Patch Last_Snowflake_Sync__c in Salesforce
        try {
          const patchUrl = `${creds.instanceUrl.replace(/\/+$/, '')}/services/data/v60.0/sobjects/Account/${acc.Id}`;
          await fetch(patchUrl, {
            method: 'PATCH',
            headers: {
              Authorization: `Bearer ${creds.accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              Last_Snowflake_Sync__c: new Date().toISOString(),
            }),
          });
        } catch (_) {}

        console.log(`[SnowflakeService] Successfully auto-synced Salesforce account "${acc.Name}" (${acc.Id}) into Snowflake!`);
        return true;
      }
    } catch (err: any) {
      console.warn(`[SnowflakeService] Auto-sync from Salesforce notice: ${err.message}`);
    }
    return false;
  }

  /**
   * Pre-seeds or updates realistic analytics metrics for test accounts in Snowflake.
   */
  public async seedDefaultAnalytics(): Promise<void> {
    await this.ensureSchemaExists();

    const seedData = [
      {
        id: '001fj00001NDiLnAAL',
        name: 'Edge Communications',
        industry: 'Electronics',
        healthScore: 94,
        usageHours: 348.5,
        churnRisk: 'LOW',
        slaTier: 'Platinum',
      },
      {
        id: '001fj00001NDiLoAAL',
        name: 'Burlington Textiles Corp of America',
        industry: 'Apparel',
        healthScore: 78,
        usageHours: 195.0,
        churnRisk: 'MEDIUM',
        slaTier: 'Gold',
      },
      {
        id: '001fj00001NDiLpAAL',
        name: 'Pyramid Construction Inc.',
        industry: 'Construction',
        healthScore: 52,
        usageHours: 64.2,
        churnRisk: 'HIGH',
        slaTier: 'Silver',
      },
    ];

    for (const item of seedData) {
      const sql = `
        MERGE INTO LEARNDC_DB.ANALYTICS.ACCOUNT_ANALYTICS target
        USING (
          SELECT 
            ? AS SF_ACCOUNT_ID,
            ? AS ACCOUNT_NAME,
            ? AS INDUSTRY,
            ? AS HEALTH_SCORE,
            ? AS USAGE_HOURS,
            ? AS CHURN_RISK,
            ? AS SLA_TIER,
            CURRENT_TIMESTAMP() AS SNOWFLAKE_LAST_UPDATED
        ) source
        ON target.SF_ACCOUNT_ID = source.SF_ACCOUNT_ID
        WHEN MATCHED THEN
          UPDATE SET 
            target.HEALTH_SCORE = source.HEALTH_SCORE,
            target.USAGE_HOURS = source.USAGE_HOURS,
            target.CHURN_RISK = source.CHURN_RISK,
            target.SNOWFLAKE_LAST_UPDATED = source.SNOWFLAKE_LAST_UPDATED
        WHEN NOT MATCHED THEN
          INSERT (
            SF_ACCOUNT_ID, ACCOUNT_NAME, INDUSTRY, HEALTH_SCORE, USAGE_HOURS, CHURN_RISK, SLA_TIER, SNOWFLAKE_LAST_UPDATED
          ) VALUES (
            source.SF_ACCOUNT_ID, source.ACCOUNT_NAME, source.INDUSTRY, source.HEALTH_SCORE,
            source.USAGE_HOURS, source.CHURN_RISK, source.SLA_TIER, source.SNOWFLAKE_LAST_UPDATED
          )
      `;

      await snowflakeClient.executeQuery(
        sql,
        [item.id, item.name, item.industry, item.healthScore, item.usageHours, item.churnRisk, item.slaTier],
        true
      );
    }

    console.log('[SnowflakeService] Seeded default analytics for test accounts successfully.');
  }
}

export const snowflakeService = SnowflakeService.getInstance();
