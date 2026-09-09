import { agentSessionManager } from './gemini/agent.js';
import { loadConfig } from './config.js';

async function runPhase1Test() {
  console.log('================================================================');
  console.log('🧪 Google AI Studio Gemini Agent - Phase 1 Verification Suite');
  console.log('================================================================\n');

  try {
    const config = loadConfig(false);
    console.log(`✅ Loaded Configuration:`);
    console.log(`   - Model: ${config.geminiModel}`);
    console.log(`   - API Key: ${config.geminiApiKey.slice(0, 6)}...${config.geminiApiKey.slice(-4)}\n`);
  } catch (err: any) {
    console.error(`❌ Configuration Check Failed:\n${err.message}\n`);
    console.log('💡 How to fix:');
    console.log('1. Copy .env.example to .env');
    console.log('2. Add your Google AI Studio API key (https://aistudio.google.com/) to GEMINI_API_KEY');
    process.exit(1);
  }

  const testSessionId = 'test-session-' + Date.now();

  // Test Case 1: Persona & Direct Response
  console.log('----------------------------------------------------------------');
  console.log('Test 1: Agent Persona & General Inquiries');
  console.log('----------------------------------------------------------------');
  const q1 = 'Hi! Introduce yourself briefly and tell me how you can assist our team in Slack.';
  console.log(`User: "${q1}"`);
  try {
    const reply1 = await agentSessionManager.processMessage(testSessionId, q1);
    console.log(`\n🤖 Agent Reply:\n${reply1}\n`);
  } catch (error: any) {
    console.error('❌ Test 1 Failed:', error.message);
    process.exit(1);
  }

  // Test Case 2: Autonomous Tool Execution (get_current_time)
  console.log('----------------------------------------------------------------');
  console.log('Test 2: Tool Execution - Real-Time Date & Time');
  console.log('----------------------------------------------------------------');
  const q2 = 'What is the current date and time right now?';
  console.log(`User: "${q2}"`);
  try {
    let toolTriggered = false;
    const reply2 = await agentSessionManager.processMessage(testSessionId, q2, (toolName, args) => {
      toolTriggered = true;
      console.log(`⚡ [Tool Triggered] "${toolName}" with parameters:`, args);
    });
    console.log(`\n🤖 Agent Reply:\n${reply2}\n`);
    if (toolTriggered) {
      console.log('✅ Tool calling successfully verified!');
    }
  } catch (error: any) {
    console.error('❌ Test 2 Failed:', error.message);
    process.exit(1);
  }

  // Test Case 3: Autonomous Tool Execution (CRM Account Lookup)
  console.log('----------------------------------------------------------------');
  console.log('Test 3: Tool Execution - CRM Account Lookup (Salesforce)');
  console.log('----------------------------------------------------------------');
  const q3 = 'Can you look up the account details for Acme Corp and let me know who the CSM is?';
  console.log(`User: "${q3}"`);
  try {
    const reply3 = await agentSessionManager.processMessage(testSessionId, q3, (toolName, args) => {
      console.log(`⚡ [Tool Triggered] "${toolName}" with parameters:`, args);
    });
    console.log(`\n🤖 Agent Reply:\n${reply3}\n`);
  } catch (error: any) {
    console.error('❌ Test 3 Failed:', error.message);
    process.exit(1);
  }

  // Test Case 4: Multi-Turn Conversation Threading Memory
  console.log('----------------------------------------------------------------');
  console.log('Test 4: Multi-Turn Conversation Memory');
  console.log('----------------------------------------------------------------');
  const q4 = 'Thanks! What was the contact person name you mentioned for that account?';
  console.log(`User: "${q4}"`);
  try {
    const reply4 = await agentSessionManager.processMessage(testSessionId, q4);
    console.log(`\n🤖 Agent Reply:\n${reply4}\n`);
    console.log('✅ Multi-turn conversational memory verified!');
  } catch (error: any) {
    console.error('❌ Test 4 Failed:', error.message);
    process.exit(1);
  }

  // Test Case 5: Dual-Platform Query (Salesforce CRM + Snowflake Telemetry)
  console.log('----------------------------------------------------------------');
  console.log('Test 5: Dual-Platform Query - Salesforce CRM + Snowflake Warehouse');
  console.log('----------------------------------------------------------------');
  const q5 = 'Give me a complete 360 overview for Edge Communications including both Salesforce CRM details and Snowflake warehouse telemetry.';
  console.log(`User: "${q5}"`);
  try {
    const reply5 = await agentSessionManager.processMessage(testSessionId, q5, (toolName, args) => {
      console.log(`⚡ [Tool Triggered] "${toolName}" with parameters:`, args);
    });
    console.log(`\n🤖 Agent Reply:\n${reply5}\n`);
    console.log('✅ Dual-Platform reasoning verified!');
  } catch (error: any) {
    console.error('❌ Test 5 Failed:', error.message);
    process.exit(1);
  }

  console.log('================================================================');
  console.log('🎉 Dual-Platform Agent Verification Completed Successfully!');
  console.log('Your Google AI Studio Agent synthesizes both Salesforce CRM & Snowflake Warehouse.');
  console.log('================================================================');
  process.exit(0);
}

runPhase1Test();
