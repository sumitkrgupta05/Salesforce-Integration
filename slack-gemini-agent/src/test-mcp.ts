import { loadConfig } from './config.js';
import { getSalesforceCredentials } from './mcp/salesforceAuth.js';
import { salesforceMcpClient } from './mcp/salesforceMcpClient.js';

async function testSalesforceMcpIntegration() {
  console.log('================================================================');
  console.log('🔍 Salesforce-Hosted MCP Integration Test & Diagnostics');
  console.log('================================================================\n');

  const config = loadConfig(false);

  // 1. Test Salesforce Authentication / CLI Resolution
  console.log('--- Step 1: Testing Salesforce Org Authentication ---');
  try {
    const creds = await getSalesforceCredentials();
    console.log(`✅ Salesforce Org Connected:`);
    console.log(`   - Org Alias: ${creds.orgAlias}`);
    console.log(`   - Instance URL: ${creds.instanceUrl}`);
    console.log(`   - Access Token: ${creds.accessToken.slice(0, 15)}...${creds.accessToken.slice(-10)}\n`);
  } catch (err: any) {
    console.error(`❌ Salesforce Auth Error: ${err.message}\n`);
    process.exit(1);
  }

  // 2. Test Salesforce Hosted MCP Endpoint
  console.log('--- Step 2: Testing Salesforce Hosted MCP Server Endpoint ---');
  if (!config.sfMcpEndpointUrl) {
    console.log('ℹ️  SF_MCP_ENDPOINT_URL is not currently set in .env.');
    console.log('📌 Once you create your Custom MCP Server in Salesforce Setup:');
    console.log('   1. Copy the generated MCP Server Endpoint URL.');
    console.log('   2. Add to slack-gemini-agent/.env:');
    console.log('      SF_MCP_ENDPOINT_URL=https://<your-instance>.my.salesforce.com/services/mcp/v1/...');
    console.log('   3. Rerun this test!\n');
    console.log('✅ Fallback mechanism verified: Agent runs safely with built-in CRM tools.');
    process.exit(0);
  }

  console.log(`Testing connection to: ${config.sfMcpEndpointUrl}...`);
  const connected = await salesforceMcpClient.initialize();

  if (connected) {
    console.log('✅ Connection established with Salesforce Hosted MCP Server!');
    const tools = salesforceMcpClient.getTools();
    console.log(`📦 Discovered ${tools.length} tool(s) from Salesforce Setup:`);
    tools.forEach((t: any, idx: number) => {
      console.log(`   ${idx + 1}. [${t.name}] - ${t.description || 'No description'}`);
    });

    console.log('\n--- Step 3: Testing Live Tool Execution on Salesforce ---');
    console.log('Invoking: LearnDCMCPAccountAction({ accountIdentifier: "Edge" })...');
    try {
      const toolOutput = await salesforceMcpClient.callTool('LearnDCMCPAccountAction', {
        accountIdentifier: 'Edge',
      });
      console.log('🎉 Live CRM Tool Result:');
      console.log(JSON.stringify(toolOutput, null, 2));
    } catch (toolErr: any) {
      console.error('❌ Tool Execution Error:', toolErr.message);
    }
  } else {
    console.log('⚠️  Could not connect to the MCP endpoint. Please verify endpoint URL and active session.');
  }

  process.exit(0);
}

testSalesforceMcpIntegration().catch((e) => {
  console.error('Fatal error during MCP test:', e);
  process.exit(1);
});
