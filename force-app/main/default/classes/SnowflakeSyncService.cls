/**
 * @description Service class managing asynchronous synchronization of Account records
 *              from Salesforce to Snowflake Cloud Data Warehouse via the integration gateway.
 */
public with sharing class SnowflakeSyncService {

    public static Boolean isSyncing = false;
    @TestVisible private static String mockEndpoint = null;

    /**
     * @description Enqueues asynchronous synchronization for a set of Account IDs.
     */
    public static void syncAccountsAsync(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }

        if (System.isQueueable() || System.isFuture()) {
            executeSync(accountIds);
        } else {
            System.enqueueJob(new SnowflakeSyncQueueable(accountIds));
        }
    }

    /**
     * @description Outbound synchronization execution method called by Queueable.
     *              Queries the mapped Account fields and sends payload to the Snowflake gateway.
     */
    public static void executeSync(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) return;

        List<Account> accounts = [
            SELECT Id, Name, Industry, Type, AnnualRevenue, SLA__c, CustomerPriority__c, CSM_Email__c
            FROM Account
            WHERE Id IN :accountIds
        ];

        if (accounts.isEmpty()) return;

        String endpoint = resolveEndpoint();
        List<Account> accountsToUpdate = new List<Account>();

        for (Account acc : accounts) {
            Map<String, Object> payload = new Map<String, Object>{
                'sfAccountId' => String.valueOf(acc.Id),
                'accountName' => acc.Name,
                'industry' => acc.Industry,
                'accountType' => acc.Type,
                'annualRevenue' => acc.AnnualRevenue,
                'slaTier' => acc.SLA__c,
                'customerPriority' => acc.CustomerPriority__c,
                'csmEmail' => acc.CSM_Email__c
            };

            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpoint);
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setTimeout(20000);
                req.setBody(JSON.serialize(payload));

                Http http = new Http();
                HttpResponse res = http.send(req);

                if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    accountsToUpdate.add(new Account(
                        Id = acc.Id,
                        Last_Snowflake_Sync__c = DateTime.now()
                    ));
                } else {
                    System.debug(LoggingLevel.WARN, 'Snowflake sync returned status ' + res.getStatusCode() + ': ' + res.getBody());
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Snowflake sync callout notice: ' + ex.getMessage());
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            isSyncing = true; // Prevent trigger recursion when updating Last_Snowflake_Sync__c
            try {
                update accountsToUpdate;
            } finally {
                isSyncing = false;
            }
        }
    }

    /**
     * @description Resolves the Snowflake outbound sync gateway URL.
     */
    public static String resolveEndpoint() {
        if (Test.isRunningTest() && mockEndpoint != null) {
            return mockEndpoint;
        }
        return 'http://localhost:8080/api/snowflake/sync-outbound';
    }
}
