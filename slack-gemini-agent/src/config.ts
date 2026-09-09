import dotenv from 'dotenv';
import path from 'path';

// Load environment variables from .env
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

export interface AgentConfig {
  geminiApiKey: string;
  geminiModel: string;
  slackBotToken?: string;
  slackAppToken?: string;
  slackSigningSecret?: string;
  enableSalesforceTools: boolean;
  sfMcpEndpointUrl?: string;
  sfAccessToken?: string;
  sfRefreshToken?: string;
  sfClientId?: string;
  sfLoginUrl?: string;
  sfInstanceUrl?: string;
  sfOrgAlias?: string;
  snowflakeAccount?: string;
  snowflakeUsername?: string;
  snowflakePassword?: string;
  snowflakeWarehouse?: string;
  snowflakeDatabase?: string;
  snowflakeSchema?: string;
}

export function loadConfig(requireSlack = false): AgentConfig {
  const geminiApiKey = process.env.GEMINI_API_KEY;
  if (!geminiApiKey || geminiApiKey === 'your_gemini_api_key_here') {
    throw new Error(
      'Missing or placeholder GEMINI_API_KEY in .env file. Please set a valid API key from Google AI Studio (https://aistudio.google.com/).'
    );
  }

  const geminiModel = process.env.GEMINI_MODEL || 'gemini-3.6-flash';

  if (requireSlack) {
    if (!process.env.SLACK_BOT_TOKEN || process.env.SLACK_BOT_TOKEN === 'xoxb-your-bot-token' || !process.env.SLACK_BOT_TOKEN.startsWith('xoxb-')) {
      throw new Error('Missing or placeholder SLACK_BOT_TOKEN. Please set your Bot User OAuth Token from api.slack.com (starts with xoxb-).');
    }
    if (!process.env.SLACK_APP_TOKEN || process.env.SLACK_APP_TOKEN === 'xapp-your-app-token' || !process.env.SLACK_APP_TOKEN.startsWith('xapp-')) {
      throw new Error('Missing or placeholder SLACK_APP_TOKEN. Please set your App-Level Token from api.slack.com with connections:write scope (starts with xapp-).');
    }
    if (!process.env.SLACK_SIGNING_SECRET || process.env.SLACK_SIGNING_SECRET === 'your_slack_signing_secret') {
      throw new Error('Missing or placeholder SLACK_SIGNING_SECRET. Please set your Signing Secret from api.slack.com.');
    }
  }

  return {
    geminiApiKey,
    geminiModel,
    slackBotToken: process.env.SLACK_BOT_TOKEN,
    slackAppToken: process.env.SLACK_APP_TOKEN,
    slackSigningSecret: process.env.SLACK_SIGNING_SECRET,
    enableSalesforceTools: process.env.ENABLE_SALESFORCE_TOOLS === 'true',
    sfMcpEndpointUrl: process.env.SF_MCP_ENDPOINT_URL,
    sfAccessToken: process.env.SF_ACCESS_TOKEN,
    sfRefreshToken: process.env.SF_REFRESH_TOKEN,
    sfClientId: process.env.SF_CLIENT_ID || 'PlatformCLI',
    sfLoginUrl: process.env.SF_LOGIN_URL || 'https://login.salesforce.com',
    sfInstanceUrl: process.env.SF_INSTANCE_URL,
    sfOrgAlias: process.env.SF_ORG_ALIAS || 'learn_dc',
    snowflakeAccount: process.env.SNOWFLAKE_ACCOUNT,
    snowflakeUsername: process.env.SNOWFLAKE_USERNAME,
    snowflakePassword: process.env.SNOWFLAKE_PASSWORD,
    snowflakeWarehouse: process.env.SNOWFLAKE_WAREHOUSE || 'COMPUTE_WH',
    snowflakeDatabase: process.env.SNOWFLAKE_DATABASE || 'LEARNDC_DB',
    snowflakeSchema: process.env.SNOWFLAKE_SCHEMA || 'ANALYTICS',
  };
}
