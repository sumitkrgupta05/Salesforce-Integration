import http from 'http';
import { App } from '@slack/bolt';
import { loadConfig } from './config.js';
import { registerSlackHandlers } from './slack/handlers.js';
import { registerSlashCommands } from './slack/commands.js';
import { salesforceMcpClient } from './mcp/salesforceMcpClient.js';
import { handleLwcChatRequest } from './api/gateway.js';
import { snowflakeService } from './snowflake/service.js';
import { snowflakeClient } from './snowflake/client.js';
import { snowflakeSyncDaemon } from './snowflake/syncDaemon.js';
import { snowflakeMcpClient } from './mcp/snowflakeMcpClient.js';
import { handleAuthLogin, handleAuthCallback, handleAuthConfirm } from './api/auth.js';

async function startSlackBot() {
  console.log('================================================================');
  console.log('🚀 Starting Google AI Studio Gemini Agent for Slack (Bolt)');
  console.log('================================================================\n');

  let config;
  try {
    config = loadConfig(true);
  } catch (err: any) {
    console.error(`❌ Slack Configuration Error:\n${err.message}\n`);
    console.log('💡 How to configure:');
    console.log('1. Open slack-gemini-agent/.env');
    console.log('2. Set SLACK_BOT_TOKEN (starts with xoxb-)');
    console.log('3. Set SLACK_APP_TOKEN (starts with xapp- with connections:write scope)');
    console.log('4. Set SLACK_SIGNING_SECRET');
    process.exit(1);
  }

  const app = new App({
    token: config.slackBotToken,
    appToken: config.slackAppToken,
    signingSecret: config.slackSigningSecret,
    socketMode: true,
  });

  // Initialize Hosted MCP Clients (Salesforce & Snowflake)
  await salesforceMcpClient.initialize();
  await snowflakeMcpClient.initialize();

  // Register Event Handlers & Slash Commands
  registerSlackHandlers(app);
  registerSlashCommands(app);

  // Start Socket Mode connection
  await app.start();

  // Start Real-Time Salesforce <-> Snowflake Sync Daemon
  snowflakeSyncDaemon.start();
  // Start HTTP Gateway & Health Check Server
  const port = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
  const healthServer = http.createServer(async (req, res) => {
    // CORS headers for web callouts
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return;
    }

    // OAuth 2.0 Login / Authorization Redirect
    if (req.method === 'GET' && req.url && req.url.startsWith('/auth/login')) {
      await handleAuthLogin(req, res);
      return;
    }

    // Interactive Slack Consent Confirmation (Allow button)
    if (req.url && req.url.startsWith('/auth/slack/confirm')) {
      await handleAuthConfirm(req, res);
      return;
    }

    // OAuth 2.0 Slack Callback
    if (req.method === 'GET' && req.url && req.url.startsWith('/auth/slack/callback')) {
      await handleAuthCallback(req, res);
      return;
    }

    // Headless Agent Gateway for Salesforce LWC
    if (req.method === 'POST' && req.url === '/api/chat') {
      let body = '';
      req.on('data', (chunk) => { body += chunk; });
      req.on('end', async () => {
        try {
          const payload = JSON.parse(body || '{}');
          const result = await handleLwcChatRequest(app, payload);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(result));
        } catch (parseErr: any) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ isSuccess: false, messageText: 'Invalid JSON request payload: ' + parseErr.message }));
        }
      });
      return;
    }

    // Snowflake Outbound Sync (Salesforce -> Snowflake)
    if (req.method === 'POST' && req.url === '/api/snowflake/sync-outbound') {
      let body = '';
      req.on('data', (chunk) => { body += chunk; });
      req.on('end', async () => {
        try {
          const payload = JSON.parse(body || '{}');
          const result = await snowflakeService.mergeAccountOutbound(payload);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ isSuccess: true, data: result }));
        } catch (err: any) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ isSuccess: false, errorMessage: err.message }));
        }
      });
      return;
    }

    // Snowflake Inbound Sync & Query (Snowflake -> Salesforce)
    if (req.method === 'POST' && req.url === '/api/snowflake/sync-inbound') {
      let body = '';
      req.on('data', (chunk) => { body += chunk; });
      req.on('end', async () => {
        try {
          const payload = JSON.parse(body || '{}');
          const identifier = payload.accountId || payload.accountName || payload.accountIdentifier;
          const analytics = await snowflakeService.getAccountAnalytics(identifier);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ isSuccess: true, analytics }));
        } catch (err: any) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ isSuccess: false, errorMessage: err.message }));
        }
      });
      return;
    }

    // Snowflake Health Check
    if (req.method === 'GET' && req.url === '/api/snowflake/health') {
      try {
        const testRes = await snowflakeClient.testConnection();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ isSuccess: true, status: 'connected', ...testRes }));
      } catch (err: any) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ isSuccess: false, status: 'disconnected', errorMessage: err.message }));
      }
      return;
    }

    if (req.url === '/health' || req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'healthy',
        service: 'slack-gemini-agent',
        gateway: 'active',
        endpoint: '/api/chat',
        model: config.geminiModel,
        uptimeSeconds: Math.floor(process.uptime()),
        timestamp: new Date().toISOString(),
      }));
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    }
  });

  healthServer.listen(port, '0.0.0.0', () => {
    console.log(`🏥 Headless Slack Bot Gateway & Health Server listening on 0.0.0.0:${port} (/api/chat)`);
  });

  console.log('⚡️ Slack Gemini Agent is connected and running in Socket Mode!');
  console.log(`🤖 Using LLM Model: ${config.geminiModel}`);
  console.log('💬 Listening for:');
  console.log('   - Mentions in channels: @Gemini');
  console.log('   - Direct Messages (DMs)\n');
  console.log('Press Ctrl+C to stop the bot.');
}

startSlackBot().catch((error) => {
  console.error('Fatal error starting Slack bot:', error);
  process.exit(1);
});
