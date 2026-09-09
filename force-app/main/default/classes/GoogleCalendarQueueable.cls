public with sharing class GoogleCalendarQueueable implements Queueable, Database.AllowsCallouts {
    private String userEmail;
    private String syncToken;

    public GoogleCalendarQueueable(String userEmail, String syncToken) {
        this.userEmail = userEmail;
        this.syncToken = syncToken;
    }

    public void execute(QueueableContext context) {
        try {
            Map<String, Object> deltaResult = GoogleCalendarService.getEventsDelta(this.userEmail, this.syncToken);
            if (deltaResult == null || !deltaResult.containsKey('items')) {
                return;
            }

            List<Object> items = (List<Object>) deltaResult.get('items');
            if (items.isEmpty()) {
                return;
            }

            Set<String> googleEventIds = new Set<String>();
            Set<String> attendeeEmails = new Set<String>();

            for (Object obj : items) {
                Map<String, Object> item = (Map<String, Object>) obj;
                String gId = (String) item.get('id');
                if (String.isNotBlank(gId)) {
                    googleEventIds.add(gId);
                }
                if (item.containsKey('attendees')) {
                    for (Object attObj : (List<Object>) item.get('attendees')) {
                        Map<String, Object> attMap = (Map<String, Object>) attObj;
                        if (attMap.containsKey('email')) {
                            attendeeEmails.add(((String) attMap.get('email')).toLowerCase().trim());
                        }
                    }
                }
            }

            // Query existing Salesforce Events
            Map<String, Event> existingEventsByGoogleId = new Map<String, Event>();
            for (Event evt : [
                SELECT Id, Subject, StartDateTime, EndDateTime, Description, WhatId, WhoId,
                       Google_Event_Id__c, Google_Meet_Link__c, Google_ETag__c, Last_Sync_Source__c, Sync_Status__c
                FROM Event
                WHERE Google_Event_Id__c IN :googleEventIds
            ]) {
                existingEventsByGoogleId.put(evt.Google_Event_Id__c, evt);
            }

            // Query matching Contacts by email to resolve AccountId and ContactId
            Map<String, Contact> contactsByEmail = new Map<String, Contact>();
            if (!attendeeEmails.isEmpty()) {
                for (Contact c : [
                    SELECT Id, Email, AccountId
                    FROM Contact
                    WHERE Email IN :attendeeEmails AND AccountId != null
                    ORDER BY CreatedDate ASC
                ]) {
                    if (String.isNotBlank(c.Email)) {
                        contactsByEmail.put(c.Email.toLowerCase().trim(), c);
                    }
                }
            }

            List<Event> eventsToUpsert = new List<Event>();
            List<Event> eventsToDelete = new List<Event>();
            List<Calendar_Sync_Notification__e> notifications = new List<Calendar_Sync_Notification__e>();

            for (Object obj : items) {
                Map<String, Object> item = (Map<String, Object>) obj;
                String gId = (String) item.get('id');
                String status = (String) item.get('status');

                if (status == 'cancelled') {
                    if (existingEventsByGoogleId.containsKey(gId)) {
                        Event existing = existingEventsByGoogleId.get(gId);
                        eventsToDelete.add(existing);
                        notifications.add(new Calendar_Sync_Notification__e(
                            AccountId__c = existing.WhatId,
                            EventId__c = existing.Id,
                            Action__c = 'DELETED',
                            Timestamp__c = DateTime.now()
                        ));
                    }
                } else {
                    GoogleCalendarService.GoogleEventResult parsed = GoogleCalendarService.parseGoogleEvent(JSON.serialize(item));
                    Event sfEvent = existingEventsByGoogleId.containsKey(gId) 
                        ? existingEventsByGoogleId.get(gId) 
                        : new Event(Google_Event_Id__c = gId);

                    sfEvent.Subject = String.isNotBlank(parsed.summary) ? parsed.summary : 'Google Calendar Meeting';
                    sfEvent.Description = parsed.description;
                    sfEvent.StartDateTime = parsed.startDateTime != null ? parsed.startDateTime : DateTime.now();
                    sfEvent.EndDateTime = parsed.endDateTime != null ? parsed.endDateTime : sfEvent.StartDateTime.addMinutes(30);
                    sfEvent.Google_Meet_Link__c = parsed.hangoutLink;
                    sfEvent.Google_ETag__c = parsed.etag;
                    sfEvent.Last_Sync_Source__c = 'GOOGLE'; // Mark source to avoid trigger loops
                    sfEvent.Sync_Status__c = 'Synced';

                    // Link Contact & Account if available and not already set
                    if (sfEvent.WhatId == null && parsed.attendeeEmails != null) {
                        for (String attEmail : parsed.attendeeEmails) {
                            String lower = attEmail.toLowerCase().trim();
                            if (contactsByEmail.containsKey(lower)) {
                                Contact matchContact = contactsByEmail.get(lower);
                                sfEvent.WhoId = matchContact.Id;
                                sfEvent.WhatId = matchContact.AccountId;
                                break;
                            }
                        }
                    }

                    eventsToUpsert.add(sfEvent);
                }
            }

            if (!eventsToDelete.isEmpty()) {
                delete eventsToDelete;
            }

            if (!eventsToUpsert.isEmpty()) {
                upsert eventsToUpsert Google_Event_Id__c;
                for (Event ev : eventsToUpsert) {
                    notifications.add(new Calendar_Sync_Notification__e(
                        AccountId__c = ev.WhatId,
                        EventId__c = ev.Id,
                        Action__c = 'UPDATED',
                        Timestamp__c = DateTime.now()
                    ));
                }
            }

            if (!notifications.isEmpty()) {
                EventBus.publish(notifications);
            }

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'GoogleCalendarQueueable Error: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
        }
    }
}
