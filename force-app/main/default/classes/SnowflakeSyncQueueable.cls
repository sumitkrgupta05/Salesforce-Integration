/**
 * @description Asynchronous Queueable worker to dispatch Account changes to Snowflake without blocking the UI.
 */
public with sharing class SnowflakeSyncQueueable implements Queueable, Database.AllowsCallouts {

    private Set<Id> accountIds;

    public SnowflakeSyncQueueable(Set<Id> accountIds) {
        this.accountIds = accountIds;
    }

    public void execute(QueueableContext context) {
        SnowflakeSyncService.executeSync(this.accountIds);
    }
}
