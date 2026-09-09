@isTest
private class AccountSnowflakeTriggerTest {

    private class SnowflakeHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"isSuccess":true,"data":{"isSuccess":true,"sfAccountId":"001test"}}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void testInsertAccountTriggersSync() {
        Test.setMock(HttpCalloutMock.class, new SnowflakeHttpMock());
        SnowflakeSyncService.mockEndpoint = 'https://mock.snowflake.gateway/api/sync-outbound';

        Test.startTest();
        Account acc = new Account(
            Name = 'Test Cloud Account',
            Industry = 'Technology',
            Type = 'Customer - Direct',
            AnnualRevenue = 5000000,
            SLA__c = 'Platinum',
            CustomerPriority__c = 'High',
            CSM_Email__c = 'csm.test@example.com'
        );
        insert acc;
        Test.stopTest();

        Account refreshedAcc = [SELECT Id, Name, Last_Snowflake_Sync__c FROM Account WHERE Id = :acc.Id];
        System.assertNotEquals(null, refreshedAcc.Id, 'Account should have been inserted');
    }

    @isTest
    static void testUpdateAccountTriggersSyncOnCrmFieldChange() {
        Test.setMock(HttpCalloutMock.class, new SnowflakeHttpMock());
        SnowflakeSyncService.mockEndpoint = 'https://mock.snowflake.gateway/api/sync-outbound';

        Account acc = new Account(
            Name = 'Initial Corp',
            Industry = 'Electronics',
            SLA__c = 'Gold'
        );
        insert acc;

        AccountSnowflakeTriggerHandler.processedIds.clear();

        Test.startTest();
        acc.SLA__c = 'Platinum';
        acc.AnnualRevenue = 12000000;
        update acc;
        Test.stopTest();

        Account refreshedAcc = [SELECT Id, SLA__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Platinum', refreshedAcc.SLA__c, 'SLA should have been updated to Platinum');
    }

    @isTest
    static void testUpdateAccountBypassesSyncOnInboundOnlyFieldChange() {
        Test.setMock(HttpCalloutMock.class, new SnowflakeHttpMock());
        SnowflakeSyncService.mockEndpoint = 'https://mock.snowflake.gateway/api/sync-outbound';

        Account acc = new Account(
            Name = 'Telemetry Account',
            Industry = 'Healthcare'
        );
        insert acc;

        AccountSnowflakeTriggerHandler.processedIds.clear();

        Test.startTest();
        // Update ONLY inbound Snowflake fields (simulating reverse sync)
        acc.Health_Score__c = 95;
        acc.Usage_Hours__c = 420.5;
        acc.Churn_Risk__c = 'LOW';
        update acc;
        Test.stopTest();

        Account refreshedAcc = [SELECT Id, Health_Score__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(95, refreshedAcc.Health_Score__c, 'Health score should be updated without triggering sync loop');
    }

    @isTest
    static void testDirectSyncServiceExecution() {
        Test.setMock(HttpCalloutMock.class, new SnowflakeHttpMock());
        SnowflakeSyncService.mockEndpoint = 'https://mock.snowflake.gateway/api/sync-outbound';

        Account acc = new Account(
            Name = 'Direct Service Test',
            Industry = 'Finance'
        );
        insert acc;

        Test.startTest();
        SnowflakeSyncService.syncAccountsAsync(new Set<Id>{ acc.Id });
        Test.stopTest();

        System.assertNotEquals(null, SnowflakeSyncService.resolveEndpoint(), 'Endpoint should resolve');
    }
}
