import { execSync } from 'child_process';
import { loadConfig } from '../config.js';

export interface SalesforceCredentials {
  accessToken: string;
  instanceUrl: string;
  orgAlias: string;
}

let cachedCredentials: SalesforceCredentials | null = null;

/**
 * Refreshes an access token using OAuth 2.0 refresh_token grant against Salesforce token endpoint.
 */
async function refreshViaOAuth2(
  refreshToken: string,
  clientId: string,
  loginUrl: string,
  defaultInstanceUrl?: string,
  orgAlias = 'learn_dc'
): Promise<SalesforceCredentials | null> {
  try {
    const tokenEndpoint = `${loginUrl.replace(/\/+$/, '')}/services/oauth2/token`;
    console.log(`[SalesforceAuth] Refreshing Salesforce token via OAuth2 (${tokenEndpoint})...`);

    const params = new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: clientId,
      refresh_token: refreshToken,
    });

    const response = await fetch(tokenEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params.toString(),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.warn(`[SalesforceAuth] OAuth2 refresh returned HTTP ${response.status}: ${errText}`);
      return null;
    }

    const data = (await response.json()) as any;
    if (data && data.access_token) {
      const instanceUrl = data.instance_url || defaultInstanceUrl;
      console.log(`[SalesforceAuth] Successfully refreshed Salesforce token via OAuth2 (${instanceUrl}).`);
      return {
        accessToken: data.access_token,
        instanceUrl,
        orgAlias,
      };
    }
  } catch (err: any) {
    console.warn(`[SalesforceAuth] OAuth2 refresh failed: ${err.message}`);
  }
  return null;
}

/**
 * Retrieves valid Salesforce credentials for connecting to the Salesforce Hosted MCP Server.
 * Supports environment variables, direct OAuth2 refresh_token grant, or dynamic extraction from CLI session.
 */
export async function getSalesforceCredentials(forceRefresh = false): Promise<SalesforceCredentials> {
  if (!forceRefresh && cachedCredentials) {
    return cachedCredentials;
  }

  const config = loadConfig(false);
  const orgAlias = config.sfOrgAlias || 'learn_dc';
  const clientId = config.sfClientId || 'PlatformCLI';
  const loginUrl = config.sfLoginUrl || 'https://login.salesforce.com';

  // 1. Prioritize active Salesforce CLI session (guaranteed fresh, never stale)
  try {
    const tokenOutput = execSync(`sf org auth show-access-token -o ${orgAlias} --json`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore'],
    });
    const tokenData = JSON.parse(tokenOutput);
    const accessToken = tokenData?.result?.accessToken;

    let instanceUrl = config.sfInstanceUrl;
    try {
      const orgDisplayOutput = execSync(`sf org display --json -o ${orgAlias}`, {
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'ignore'],
      });
      const orgData = JSON.parse(orgDisplayOutput);
      instanceUrl = orgData?.result?.instanceUrl || instanceUrl;
    } catch (_) {}

    if (accessToken && instanceUrl) {
      cachedCredentials = {
        accessToken,
        instanceUrl,
        orgAlias,
      };
      return cachedCredentials;
    }
  } catch (cliErr: any) {
    // Fall back to environment tokens if CLI is not present
  }

  // 2. Fall back to static access token from .env
  if (config.sfAccessToken && config.sfInstanceUrl) {
    cachedCredentials = {
      accessToken: config.sfAccessToken,
      instanceUrl: config.sfInstanceUrl,
      orgAlias,
    };
    return cachedCredentials;
  }

  // 3. Try OAuth2 refresh token if available
  if (config.sfRefreshToken) {
    const refreshed = await refreshViaOAuth2(
      config.sfRefreshToken,
      clientId,
      loginUrl,
      config.sfInstanceUrl,
      orgAlias
    );
    if (refreshed) {
      cachedCredentials = refreshed;
      return cachedCredentials;
    }
  }

  // 4. Fall back to active Salesforce CLI session (learn_dc) if available
  try {
    console.log(`[SalesforceAuth] Fetching active CLI session for org alias: "${orgAlias}"...`);

    // Get instance URL and org details
    const orgDisplayOutput = execSync(`sf org display --json -o ${orgAlias}`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore'],
    });
    const orgData = JSON.parse(orgDisplayOutput);
    const instanceUrl = orgData?.result?.instanceUrl;

    // Get access token
    const tokenOutput = execSync(`sf org auth show-access-token -o ${orgAlias} --json`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore'],
    });
    const tokenData = JSON.parse(tokenOutput);
    const accessToken = tokenData?.result?.accessToken;

    if (!instanceUrl || !accessToken) {
      throw new Error(`Incomplete credentials returned for Salesforce org "${orgAlias}".`);
    }

    console.log(`[SalesforceAuth] Successfully resolved CLI credentials for "${orgAlias}" (${instanceUrl}).`);
    cachedCredentials = {
      accessToken,
      instanceUrl,
      orgAlias,
    };
    return cachedCredentials;
  } catch (cliErr: any) {
    // If CLI resolution failed but we have a static token, use it even if forceRefresh was true
    if (config.sfAccessToken && config.sfInstanceUrl) {
      console.warn(`[SalesforceAuth] CLI retrieval unavailable (${cliErr.message}), falling back to SF_ACCESS_TOKEN.`);
      cachedCredentials = {
        accessToken: config.sfAccessToken,
        instanceUrl: config.sfInstanceUrl,
        orgAlias,
      };
      return cachedCredentials;
    }

    throw new Error(
      `Could not retrieve Salesforce credentials for "${orgAlias}". Please verify 'sf org list' or set SF_REFRESH_TOKEN / SF_ACCESS_TOKEN and SF_INSTANCE_URL in .env. Details: ${cliErr.message}`
    );
  }
}
