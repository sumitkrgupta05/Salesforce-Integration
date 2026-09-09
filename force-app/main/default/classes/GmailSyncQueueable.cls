public with sharing class GmailSyncQueueable implements Queueable, Database.AllowsCallouts {
    private String userEmail;
    private String historyId;

    public GmailSyncQueueable(String userEmail, String historyId) {
        this.userEmail = userEmail;
        this.historyId = historyId;
    }

    public void execute(QueueableContext context) {
        try {
            String effectiveUser = GoogleAuthService.resolveUserEmail(this.userEmail);
            Google_Calendar_Setting__mdt setting = GoogleAuthService.getSetting();

            String startHistId = String.isNotBlank(this.historyId) 
                ? this.historyId 
                : setting.Gmail_History_Id__c;

            if (String.isBlank(startHistId)) {
                startHistId = '1';
            }

            // 1. Fetch Delta History
            GmailService.GmailHistoryResult histResult = GmailService.listHistory(effectiveUser, startHistId);
            if (histResult == null || histResult.messageIdsAdded.isEmpty()) {
                System.debug('GmailSyncQueueable: No new messages added since historyId ' + startHistId);
                return;
            }

            // 2. Fetch Details for each added message
            List<GmailService.GmailMessageDTO> messages = new List<GmailService.GmailMessageDTO>();
            Set<String> emailsToMatch = new Set<String>();

            for (String msgId : histResult.messageIdsAdded) {
                try {
                    GmailService.GmailMessageDTO dto = GmailService.getMessage(effectiveUser, msgId);
                    if (dto != null) {
                        messages.add(dto);

                        String fromEmail = GmailService.extractEmail(dto.fromAddress).toLowerCase();
                        String toEmail = GmailService.extractEmail(dto.toAddress).toLowerCase();

                        if (String.isNotBlank(fromEmail)) emailsToMatch.add(fromEmail);
                        if (String.isNotBlank(toEmail)) emailsToMatch.add(toEmail);
                    }
                } catch (Exception ex) {
                    System.debug('Error fetching Gmail message ' + msgId + ': ' + ex.getMessage());
                }
            }

            if (messages.isEmpty()) {
                return;
            }

            // 3. Resolve Contacts and Accounts
            Map<String, Contact> emailToContactMap = new Map<String, Contact>();
            if (!emailsToMatch.isEmpty()) {
                for (Contact c : [
                    SELECT Id, Email, AccountId, Account.Name, Name 
                    FROM Contact 
                    WHERE Email IN :emailsToMatch 
                    AND AccountId != null
                    LIMIT 200
                ]) {
                    emailToContactMap.put(c.Email.toLowerCase(), c);
                }
            }

            // 4. Map to Event records & prepare Platform Events
            List<Event> eventsToUpsert = new List<Event>();
            List<Gmail_Sync_Notification__e> notificationsToPublish = new List<Gmail_Sync_Notification__e>();

            for (GmailService.GmailMessageDTO msg : messages) {
                String fromEmail = GmailService.extractEmail(msg.fromAddress).toLowerCase();
                String toEmail = GmailService.extractEmail(msg.toAddress).toLowerCase();

                Contact matchedContact = null;
                if (emailToContactMap.containsKey(fromEmail)) {
                    matchedContact = emailToContactMap.get(fromEmail);
                } else if (emailToContactMap.containsKey(toEmail)) {
                    matchedContact = emailToContactMap.get(toEmail);
                }

                // Only create/link Event if matched to a CRM Contact/Account
                if (matchedContact != null) {
                    DateTime eventStart = msg.dateVal != null ? msg.dateVal : DateTime.now();

                    Event ev = new Event();
                    ev.Subject = String.isNotBlank(msg.subject) ? msg.subject : '(No Subject)';
                    ev.WhatId = matchedContact.AccountId;
                    ev.WhoId = matchedContact.Id;
                    ev.StartDateTime = eventStart;
                    ev.EndDateTime = eventStart.addMinutes(30);
                    ev.Description = String.isNotBlank(msg.snippet) ? msg.snippet : msg.subject;

                    // Custom Gmail Fields
                    ev.Gmail_Message_Id__c = msg.id;
                    ev.Gmail_Thread_Id__c = msg.threadId;
                    ev.Gmail_Snippet__c = msg.snippet != null && msg.snippet.length() > 255 
                        ? msg.snippet.substring(0, 255) 
                        : msg.snippet;
                    ev.Gmail_From_Address__c = msg.fromAddress != null && msg.fromAddress.length() > 255 
                        ? msg.fromAddress.substring(0, 255) 
                        : msg.fromAddress;
                    ev.Gmail_To_Address__c = msg.toAddress != null && msg.toAddress.length() > 255 
                        ? msg.toAddress.substring(0, 255) 
                        : msg.toAddress;
                    ev.Gmail_CC_Address__c = msg.ccAddress != null && msg.ccAddress.length() > 255 
                        ? msg.ccAddress.substring(0, 255) 
                        : msg.ccAddress;
                    ev.Gmail_Direction__c = msg.direction;
                    ev.Gmail_Date__c = msg.dateVal;
                    ev.Gmail_Has_Attachments__c = msg.hasAttachments == true;

                    // Sync loop prevention & status
                    ev.Last_Sync_Source__c = 'GMAIL';
                    ev.Sync_Status__c = 'Synced';

                    eventsToUpsert.add(ev);

                    // Create Platform Event for reactive UI update
                    notificationsToPublish.add(new Gmail_Sync_Notification__e(
                        AccountId__c = matchedContact.AccountId,
                        ThreadId__c = msg.threadId,
                        MessageId__c = msg.id,
                        Action__c = msg.direction == 'INBOUND' ? 'RECEIVED' : 'SENT',
                        Timestamp__c = DateTime.now()
                    ));
                }
            }

            // 5. Database Upsert using External ID
            if (!eventsToUpsert.isEmpty()) {
                upsert eventsToUpsert Gmail_Message_Id__c;
                System.debug('GmailSyncQueueable: Upserted ' + eventsToUpsert.size() + ' Gmail event records.');
            }

            // 6. Publish Platform Events to trigger client-side LWC refresh
            if (!notificationsToPublish.isEmpty()) {
                EventBus.publish(notificationsToPublish);
                System.debug('GmailSyncQueueable: Published ' + notificationsToPublish.size() + ' platform events.');
            }

        } catch (Exception ex) {
            System.debug('Error in GmailSyncQueueable: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
        }
    }
}
