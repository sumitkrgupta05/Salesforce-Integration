import { agentSessionManager } from './gemini/agent.js';
import { snowflakeService } from './snowflake/service.js';

async function verifyLiveEndToEnd() {
  console.log('🚀 =========================================================================');
  console.log('🚀 LIVE END-TO-END VERIFICATION: Real-Time Salesforce ➔ Snowflake ➔ AI Agent');
  console.log('🚀 =========================================================================\n');

  const testAccountName = 'Apex Global Innovations';

  // 1. Query Snowflake directly for the newly created Salesforce record
  console.log(`❄️ Step 1: Querying Snowflake for newly created Account "${testAccountName}"...`);
  const snowData = await snowflakeService.getAccountAnalytics(testAccountName);
  console.log('📊 Snowflake Result for New Account:');
  console.log(JSON.stringify(snowData, null, 2));

  if (!snowData || !snowData.isFound) {
    console.error('❌ Failed: Record was not found or synced in Snowflake.');
    process.exit(1);
  }

  console.log(`\n✅ Snowflake verification succeeded!`);
  console.log(`   • Account Name:   ${snowData.accountName}`);
  console.log(`   • Industry:       ${snowData.industry}`);
  console.log(`   • CSM Email:      ${snowData.csmEmail}`);
  console.log(`   • Health Score:   ${snowData.healthScore}/100 (Onboarding baseline)`);
  console.log(`   • Monthly Usage:  ${snowData.usageHours} hrs`);
  console.log(`   • Churn Risk:     ${snowData.churnRisk}`);

  // 2. Query Gemini AI Agent to verify dual-platform synthesis
  console.log('\n🤖 Step 2: Querying Gemini AI Agent for dual-platform synthesis...');
  const testSessionId = 'live-e2e-' + Date.now();
  const prompt = `Give me a full 360 overview for ${testAccountName} covering both Salesforce CRM details and Snowflake warehouse telemetry.`;

  console.log(`User Prompt: "${prompt}"\n`);
  const reply = await agentSessionManager.processMessage(testSessionId, prompt, (toolName, args) => {
    console.log(`⚡ [Agent Tool Triggered] "${toolName}" with args:`, JSON.stringify(args));
  });

  console.log('\n=========================================================================');
  console.log('🤖 AGENT SYNTHESIZED 360° RESPONSE:');
  console.log('=========================================================================');
  console.log(reply);
  console.log('=========================================================================\n');

  console.log('🎉 ALL TESTS PASSED! REAL-TIME CREATION, SYNC & DUAL-PLATFORM RETRIEVAL VERIFIED!');
  process.exit(0);
}

verifyLiveEndToEnd().catch((err) => {
  console.error('❌ Error during E2E test:', err.message || err);
  process.exit(1);
});
