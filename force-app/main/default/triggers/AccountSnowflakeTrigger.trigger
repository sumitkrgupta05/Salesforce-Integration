trigger AccountSnowflakeTrigger on Account (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AccountSnowflakeTriggerHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AccountSnowflakeTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
