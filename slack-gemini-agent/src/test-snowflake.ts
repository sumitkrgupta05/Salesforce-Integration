import { snowflakeClient } from './snowflake/client.js';
import { snowflakeService } from './snowflake/service.js';

async function main() {
  console.log('❄️ ==========================================');
  console.log('❄️ Testing Live Connection to Snowflake...');
  console.log('❄️ ==========================================');

  try {
    // 1. Test basic connection
    const connInfo = await snowflakeClient.testConnection();
    console.log('✅ Connected to Snowflake successfully!');
    console.log(`   • Current User:      ${connInfo.currentUser}`);
    console.log(`   • Current Account:   ${connInfo.currentAccount}`);
    console.log(`   • Snowflake Version: ${connInfo.version}`);
    console.log(`   • Active Warehouse:  ${connInfo.currentWarehouse}`);

    // 2. Initialize Database, Schema, and Table (Phase 2 DDL)
    console.log('\n🚀 Initializing LEARNDC_DB database & ACCOUNT_ANALYTICS table (Phase 2)...');
    await snowflakeService.ensureSchemaExists();
    console.log('✅ Database LEARNDC_DB, Schema ANALYTICS, and Table ACCOUNT_ANALYTICS are ready!');

    // 3. Seed sample data
    console.log('\n🌱 Seeding test analytics for known accounts...');
    await snowflakeService.seedDefaultAnalytics();

    // 4. Query sample account analytics
    console.log('\n🔍 Querying analytics for "Edge Communications"...');
    const edgeData = await snowflakeService.getAccountAnalytics('Edge Communications');
    console.log('📊 Edge Communications Analytics Result:');
    console.log(JSON.stringify(edgeData, null, 2));

    // 5. Test Outbound Merge
    console.log('\n🔄 Testing Outbound Sync (Salesforce -> Snowflake merge)...');
    const mergeRes = await snowflakeService.mergeAccountOutbound({
      sfAccountId: '001fj00001NDiLnAAL',
      accountName: 'Edge Communications',
      industry: 'Electronics',
      accountType: 'Customer - Direct',
      annualRevenue: 139000000,
      slaTier: 'Platinum',
      customerPriority: 'High',
      csmEmail: 'skgsummo5@gmail.com',
    });
    console.log('✅ Outbound Merge Succeeded:', JSON.stringify(mergeRes, null, 2));

    // Verify after merge
    const edgeAfterMerge = await snowflakeService.getAccountAnalytics('001fj00001NDiLnAAL');
    console.log('\n📊 Edge Communications After Merge:');
    console.log(`   • Account Name:   ${edgeAfterMerge.accountName}`);
    console.log(`   • Industry:       ${edgeAfterMerge.industry}`);
    console.log(`   • CSM Email:      ${edgeAfterMerge.csmEmail}`);
    console.log(`   • Health Score:   ${edgeAfterMerge.healthScore}/100`);
    console.log(`   • Monthly Hours:  ${edgeAfterMerge.usageHours} hrs`);
    console.log(`   • Churn Risk:     ${edgeAfterMerge.churnRisk}`);
    console.log(`   • SF Last Sync:   ${edgeAfterMerge.sfLastModified}`);

    console.log('\n🎉 ALL SNOWFLAKE TESTS PASSED SUCCESSFULLY! Phase 2 is COMPLETE!');
    process.exit(0);
  } catch (err: any) {
    console.error('❌ Snowflake test error:', err.message || err);
    process.exit(1);
  }
}

main();
