/**
 * @description Trigger handler for Account to manage automated real-time synchronization to Snowflake.
 *              Includes field-level diffing to prevent circular sync loops.
 */
public with sharing class AccountSnowflakeTriggerHandler {

    @TestVisible private static Set<Id> processedIds = new Set<Id>();

    public static void handleAfterInsert(List<Account> newAccounts) {
        if (SnowflakeSyncService.isSyncing) return;

        Set<Id> idsToSync = new Set<Id>();
        for (Account acc : newAccounts) {
            if (!processedIds.contains(acc.Id)) {
                idsToSync.add(acc.Id);
                processedIds.add(acc.Id);
            }
        }

        if (!idsToSync.isEmpty()) {
            SnowflakeSyncService.syncAccountsAsync(idsToSync);
        }
    }

    public static void handleAfterUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        if (SnowflakeSyncService.isSyncing) return;

        Set<Id> idsToSync = new Set<Id>();
        for (Account acc : newAccounts) {
            Account oldAcc = oldMap != null ? oldMap.get(acc.Id) : null;
            if (oldAcc == null) continue;

            // Loop Prevention / Field Diffing:
            // Only trigger sync if mapped CRM fields changed
            Boolean hasCrmChange = (
                acc.Name != oldAcc.Name ||
                acc.Industry != oldAcc.Industry ||
                acc.Type != oldAcc.Type ||
                acc.AnnualRevenue != oldAcc.AnnualRevenue ||
                acc.SLA__c != oldAcc.SLA__c ||
                acc.CustomerPriority__c != oldAcc.CustomerPriority__c ||
                acc.CSM_Email__c != oldAcc.CSM_Email__c
            );

            if (hasCrmChange && !processedIds.contains(acc.Id)) {
                idsToSync.add(acc.Id);
                processedIds.add(acc.Id);
            }
        }

        if (!idsToSync.isEmpty()) {
            SnowflakeSyncService.syncAccountsAsync(idsToSync);
        }
    }
}
