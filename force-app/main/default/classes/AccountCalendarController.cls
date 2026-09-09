public without sharing class AccountCalendarController {
    public class ControllerException extends Exception {}

    public class EventDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public DateTime startDateTime { get; set; }
        @AuraEnabled public DateTime endDateTime { get; set; }
        @AuraEnabled public String googleEventId { get; set; }
        @AuraEnabled public String googleMeetLink { get; set; }
        @AuraEnabled public String syncStatus { get; set; }
        @AuraEnabled public String contactName { get; set; }
        @AuraEnabled public String contactEmail { get; set; }
        @AuraEnabled public Id whoId { get; set; }
        @AuraEnabled public Id whatId { get; set; }
        @AuraEnabled public Boolean isPast { get; set; }
        @AuraEnabled public Integer durationMinutes { get; set; }
    }

    public class ContactDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String title { get; set; }
    }

    public class IntegrationStatusDTO {
        @AuraEnabled public Boolean isConfigured { get; set; }
        @AuraEnabled public String serviceAccountEmail { get; set; }
        @AuraEnabled public String userEmail { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
    }

    /**
     * @description Returns integration configuration status
     */
    @AuraEnabled(cacheable=true)
    public static IntegrationStatusDTO getIntegrationStatus() {
        IntegrationStatusDTO dto = new IntegrationStatusDTO();
        try {
            Google_Calendar_Setting__mdt setting = GoogleAuthService.getSetting();
            dto.isConfigured = String.isNotBlank(setting.Service_Account_Email__c);
            dto.serviceAccountEmail = setting.Service_Account_Email__c;
            dto.userEmail = UserInfo.getUserEmail();
        } catch (Exception ex) {
            dto.isConfigured = false;
            dto.errorMessage = ex.getMessage();
        }
        return dto;
    }

    /**
     * @description Fetches all contacts associated with the Account
     */
    @AuraEnabled(cacheable=true)
    public static List<ContactDTO> getAccountContacts(Id accountId) {
        List<ContactDTO> results = new List<ContactDTO>();
        if (accountId == null) {
            return results;
        }

        for (Contact c : [
            SELECT Id, Name, Email, Title
            FROM Contact
            WHERE AccountId = :accountId AND Email != null
            ORDER BY Name ASC
        ]) {
            ContactDTO dto = new ContactDTO();
            dto.id = c.Id;
            dto.name = c.Name;
            dto.email = c.Email;
            dto.title = c.Title;
            results.add(dto);
        }
        return results;
    }

    /**
     * @description Fetches all calendar meetings associated with this Account
     */
    @AuraEnabled(cacheable=false)
    public static List<EventDTO> getAccountMeetings(Id accountId) {
        List<EventDTO> results = new List<EventDTO>();
        if (accountId == null) {
            return results;
        }

        Set<Id> contactIds = new Map<Id, Contact>([
            SELECT Id FROM Contact WHERE AccountId = :accountId
        ]).keySet();

        List<Event> events = [
            SELECT Id, Subject, Description, StartDateTime, EndDateTime, DurationInMinutes,
                   WhatId, WhoId, Who.Name,
                   Google_Event_Id__c, Google_Meet_Link__c, Sync_Status__c
            FROM Event
            WHERE (WhatId = :accountId OR WhoId IN :contactIds)
              AND Gmail_Thread_Id__c = null
              AND Gmail_Direction__c = null
            ORDER BY StartDateTime ASC
        ];

        DateTime nowTime = DateTime.now();

        for (Event ev : events) {
            EventDTO dto = new EventDTO();
            dto.id = ev.Id;
            dto.subject = ev.Subject;
            dto.description = ev.Description;
            dto.startDateTime = ev.StartDateTime;
            dto.endDateTime = ev.EndDateTime;
            dto.durationMinutes = ev.DurationInMinutes;
            dto.googleEventId = ev.Google_Event_Id__c;
            dto.googleMeetLink = ev.Google_Meet_Link__c;
            dto.syncStatus = String.isNotBlank(ev.Sync_Status__c) ? ev.Sync_Status__c : 'Synced';
            dto.contactName = ev.WhoId != null ? ev.Who.Name : null;
            dto.whoId = ev.WhoId;
            dto.whatId = ev.WhatId;
            dto.isPast = ev.EndDateTime != null && ev.EndDateTime < nowTime;
            results.add(dto);
        }

        return results;
    }

    /**
     * @description Creates a new meeting in Google Calendar and Salesforce
     */
    @AuraEnabled
    public static EventDTO createMeeting(
        Id accountId, 
        String subject, 
        String description, 
        DateTime startDateTime, 
        DateTime endDateTime, 
        List<String> attendeeEmails, 
        Boolean addGoogleMeet, 
        Id contactId
    ) {
        if (String.isBlank(subject)) {
            throw new ControllerException('Subject is required.');
        }
        if (startDateTime == null || endDateTime == null) {
            throw new ControllerException('Start and End Date/Time are required.');
        }
        if (endDateTime <= startDateTime) {
            throw new ControllerException('End time must be after start time.');
        }

        String userEmail = GoogleAuthService.resolveUserEmail(null);

        // 1. Create Event on Google Calendar
        GoogleCalendarService.GoogleEventResult gResult = GoogleCalendarService.createEvent(
            userEmail, 
            subject, 
            description, 
            startDateTime, 
            endDateTime, 
            attendeeEmails, 
            addGoogleMeet
        );

        // 2. Insert into Salesforce Event object
        Event newEvent = new Event();
        newEvent.Subject = subject;
        newEvent.Description = description;
        newEvent.StartDateTime = startDateTime;
        newEvent.EndDateTime = endDateTime;
        newEvent.WhatId = accountId;
        newEvent.WhoId = contactId;
        newEvent.Google_Event_Id__c = gResult.id;
        newEvent.Google_Meet_Link__c = gResult.hangoutLink;
        newEvent.Google_ETag__c = gResult.etag;
        newEvent.Last_Sync_Source__c = 'SALESFORCE';
        newEvent.Sync_Status__c = 'Synced';

        insert newEvent;

        // 3. Dispatch branded meeting invitation email with subject 'Invitation from CSM-Teqfoucs'
        sendMeetingInvitation(newEvent, attendeeEmails, contactId, gResult.hangoutLink);

        // Return EventDTO
        EventDTO dto = new EventDTO();
        dto.id = newEvent.Id;
        dto.subject = newEvent.Subject;
        dto.description = newEvent.Description;
        dto.startDateTime = newEvent.StartDateTime;
        dto.endDateTime = newEvent.EndDateTime;
        dto.googleEventId = newEvent.Google_Event_Id__c;
        dto.googleMeetLink = newEvent.Google_Meet_Link__c;
        dto.syncStatus = 'Synced';
        dto.whoId = newEvent.WhoId;
        dto.whatId = newEvent.WhatId;
        dto.isPast = false;

        return dto;
    }

    /**
     * @description Reschedules (shifts) an existing meeting
     */
    @AuraEnabled
    public static EventDTO rescheduleMeeting(Id eventId, DateTime newStartDateTime, DateTime newEndDateTime) {
        if (eventId == null) {
            throw new ControllerException('Event ID is required.');
        }
        if (newStartDateTime == null || newEndDateTime == null) {
            throw new ControllerException('Start and End Date/Time are required.');
        }
        if (newEndDateTime <= newStartDateTime) {
            throw new ControllerException('End time must be after start time.');
        }

        Event ev = [
            SELECT Id, Subject, Description, StartDateTime, EndDateTime, WhatId, WhoId,
                   Google_Event_Id__c, Google_Meet_Link__c, Google_ETag__c
            FROM Event
            WHERE Id = :eventId
            LIMIT 1
        ];

        String userEmail = GoogleAuthService.resolveUserEmail(null);

        // If synced with Google, patch on Google Calendar
        if (String.isNotBlank(ev.Google_Event_Id__c)) {
            GoogleCalendarService.GoogleEventResult gResult = GoogleCalendarService.patchEventTimes(
                userEmail, 
                ev.Google_Event_Id__c, 
                newStartDateTime, 
                newEndDateTime
            );
            ev.Google_ETag__c = gResult.etag;
        }

        ev.StartDateTime = newStartDateTime;
        ev.EndDateTime = newEndDateTime;
        ev.Last_Sync_Source__c = 'SALESFORCE';
        ev.Sync_Status__c = 'Synced';
        update ev;

        EventDTO dto = new EventDTO();
        dto.id = ev.Id;
        dto.subject = ev.Subject;
        dto.description = ev.Description;
        dto.startDateTime = ev.StartDateTime;
        dto.endDateTime = ev.EndDateTime;
        dto.googleEventId = ev.Google_Event_Id__c;
        dto.googleMeetLink = ev.Google_Meet_Link__c;
        dto.syncStatus = 'Synced';
        dto.whoId = ev.WhoId;
        dto.whatId = ev.WhatId;
        dto.isPast = ev.EndDateTime < DateTime.now();

        return dto;
    }

    /**
     * @description Cancels (deletes) a meeting
     */
    @AuraEnabled
    public static Boolean cancelMeeting(Id eventId) {
        if (eventId == null) {
            return true;
        }

        Event ev = [
            SELECT Id, Google_Event_Id__c
            FROM Event
            WHERE Id = :eventId
            LIMIT 1
        ];

        String userEmail = GoogleAuthService.resolveUserEmail(null);

        if (String.isNotBlank(ev.Google_Event_Id__c)) {
            try {
                GoogleCalendarService.deleteEvent(userEmail, ev.Google_Event_Id__c);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Google Calendar deletion notice: ' + ex.getMessage());
            }
        }

        delete ev;
        return true;
    }

    /**
     * @description Sends meeting invitation email with subject 'Invitation from CSM-Teqfoucs'
     */
    private static void sendMeetingInvitation(
        Event ev, 
        List<String> attendeeEmails, 
        Id contactId, 
        String googleMeetLink
    ) {
        Set<String> recipientEmails = new Set<String>();
        if (attendeeEmails != null) {
            for (String em : attendeeEmails) {
                if (String.isNotBlank(em)) {
                    recipientEmails.add(em.trim().toLowerCase());
                }
            }
        }
        if (contactId != null) {
            for (Contact c : [SELECT Email FROM Contact WHERE Id = :contactId AND Email != null]) {
                recipientEmails.add(c.Email.trim().toLowerCase());
            }
        }

        if (recipientEmails.isEmpty()) {
            return;
        }

        // Custom subject as requested: 'Invitation from CSM-Teqfoucs'
        String inviteSubject = 'Invitation from CSM-Teqfoucs';
        String formattedDate = ev.StartDateTime != null ? ev.StartDateTime.format('EEEE, MMMM d, yyyy h:mm a') : '';
        String formattedEndDate = ev.EndDateTime != null ? ev.EndDateTime.format('h:mm a (z)') : '';

        String htmlBody = '<div style="font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e2e8f0; border-radius: 8px; background-color: #ffffff;">'
            + '<div style="border-bottom: 2px solid #0176d3; padding-bottom: 12px; margin-bottom: 16px;">'
            + '<h2 style="color: #0176d3; margin: 0 0 6px 0; font-size: 20px;">Meeting Invitation</h2>'
            + '<p style="color: #64748b; margin: 0; font-size: 13px;">You have been invited to a meeting by CSM-Teqfocus</p>'
            + '</div>'
            + '<table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">'
            + '<tr><td style="padding: 8px 0; color: #64748b; width: 120px; font-weight: 600;">Meeting:</td><td style="padding: 8px 0; color: #1e293b; font-weight: 700;">' + (String.isNotBlank(ev.Subject) ? ev.Subject.escapeHtml4() : 'Meeting') + '</td></tr>'
            + '<tr><td style="padding: 8px 0; color: #64748b; font-weight: 600;">When:</td><td style="padding: 8px 0; color: #1e293b;">' + formattedDate + ' - ' + formattedEndDate + '</td></tr>';

        if (String.isNotBlank(googleMeetLink)) {
            htmlBody += '<tr><td style="padding: 8px 0; color: #64748b; font-weight: 600;">Video Call:</td><td style="padding: 8px 0;"><a href="' + googleMeetLink + '" style="background-color: #0176d3; color: #ffffff; padding: 6px 14px; text-decoration: none; border-radius: 4px; display: inline-block; font-weight: 600; font-size: 13px;">Join Google Meet</a></td></tr>';
        }

        if (String.isNotBlank(ev.Description)) {
            htmlBody += '<tr><td style="padding: 8px 0; color: #64748b; font-weight: 600; vertical-align: top;">Description:</td><td style="padding: 8px 0; color: #334155;">' + ev.Description.escapeHtml4().replaceAll('\n', '<br/>') + '</td></tr>';
        }

        htmlBody += '</table>'
            + '<div style="border-top: 1px solid #e2e8f0; padding-top: 12px; font-size: 12px; color: #94a3b8;">'
            + 'Sent by Customer Success Team &bull; Teqfocus Solutions'
            + '</div></div>';

        // Match Users dynamically to bypass Developer Edition daily limits
        Map<String, Id> userMap = new Map<String, Id>();
        for (User u : [SELECT Id, Email FROM User WHERE Email IN :recipientEmails AND IsActive = true]) {
            userMap.put(u.Email.toLowerCase().trim(), u.Id);
        }

        List<Messaging.SingleEmailMessage> msgs = new List<Messaging.SingleEmailMessage>();
        for (String em : recipientEmails) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            if (userMap.containsKey(em)) {
                mail.setTargetObjectId(userMap.get(em));
            } else {
                mail.setToAddresses(new List<String>{ em });
            }
            mail.setSubject(inviteSubject);
            mail.setHtmlBody(htmlBody);
            mail.setSenderDisplayName('CSM-Teqfocus');
            mail.setSaveAsActivity(false);
            msgs.add(mail);
        }

        try {
            Messaging.sendEmail(msgs, false);
        } catch (Exception ex) {
            System.debug('Meeting invitation notice: ' + ex.getMessage());
        }
    }
}
