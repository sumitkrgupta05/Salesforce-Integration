global with sharing class LearnDCMCPMeetingAction {

    global class MeetingRequest {
        @InvocableVariable(label='Account Name or ID' description='Account Name or ID for the meeting context.' required=true)
        global String accountIdentifier;

        @InvocableVariable(label='Meeting Subject' description='Subject of the meeting.' required=true)
        global String subject;

        @InvocableVariable(label='Start Date and Time' description='Start time of the meeting (ISO-8601 or Datetime).' required=true)
        global DateTime startDateTime;

        @InvocableVariable(label='Duration in Minutes' description='Duration of the meeting in minutes (default 30).')
        global Integer durationMinutes;

        @InvocableVariable(label='Attendee Email' description='Primary attendee email address.')
        global String attendeeEmail;

        @InvocableVariable(label='Meeting Description' description='Agenda or description of the meeting.')
        global String description;
    }

    global class MeetingResult {
        @InvocableVariable(label='Is Success' description='True if the meeting was created and synced.')
        global Boolean isSuccess;

        @InvocableVariable(label='Event Record ID' description='Salesforce Event ID.')
        global String eventId;

        @InvocableVariable(label='Google Meet Link' description='Google Meet video conference link.')
        global String googleMeetLink;

        @InvocableVariable(label='Google Event ID' description='Google Calendar Event ID.')
        global String googleEventId;

        @InvocableVariable(label='Status Message' description='Result message or error details.')
        global String message;
    }

    @InvocableMethod(
        label='Schedule Calendar Meeting'
        description='Schedules a customer meeting with a Google Meet link in Google Calendar and records the Salesforce Event.'
    )
    global static List<MeetingResult> scheduleMeeting(List<MeetingRequest> requests) {
        List<MeetingResult> results = new List<MeetingResult>();

        for (MeetingRequest req : requests) {
            MeetingResult res = new MeetingResult();
            res.isSuccess = false;

            try {
                if (String.isBlank(req.accountIdentifier) || String.isBlank(req.subject) || req.startDateTime == null) {
                    res.message = 'Account, Subject, and Start Date/Time are required.';
                    results.add(res);
                    continue;
                }

                // Resolve Account and Contact
                String searchPattern = '%' + req.accountIdentifier.trim() + '%';
                List<Account> accList = [
                    SELECT Id, Name, (SELECT Id, Email FROM Contacts LIMIT 1)
                    FROM Account
                    WHERE Name LIKE :searchPattern OR Id = :req.accountIdentifier.trim()
                    LIMIT 1
                ];

                if (accList.isEmpty()) {
                    res.message = 'Account not found for: ' + req.accountIdentifier;
                    results.add(res);
                    continue;
                }

                Account targetAcc = accList[0];
                Id contactId = (targetAcc.Contacts != null && !targetAcc.Contacts.isEmpty()) ? targetAcc.Contacts[0].Id : null;

                Integer duration = (req.durationMinutes != null && req.durationMinutes > 0) ? req.durationMinutes : 30;
                DateTime endDateTime = req.startDateTime.addMinutes(duration);

                List<String> attendees = new List<String>();
                if (String.isNotBlank(req.attendeeEmail)) {
                    attendees.add(req.attendeeEmail.trim());
                } else if (targetAcc.Contacts != null && !targetAcc.Contacts.isEmpty() && String.isNotBlank(targetAcc.Contacts[0].Email)) {
                    attendees.add(targetAcc.Contacts[0].Email);
                }

                // Invoke existing Calendar integration engine
                AccountCalendarController.EventDTO eventDto = AccountCalendarController.createMeeting(
                    targetAcc.Id,
                    req.subject,
                    req.description,
                    req.startDateTime,
                    endDateTime,
                    attendees,
                    true,
                    contactId
                );

                res.isSuccess = true;
                res.eventId = eventDto.id;
                res.googleMeetLink = eventDto.googleMeetLink;
                res.googleEventId = eventDto.googleEventId;
                res.message = 'Meeting scheduled successfully with Google Meet link: ' + eventDto.googleMeetLink;
            } catch (Exception ex) {
                res.isSuccess = false;
                res.message = 'Error creating meeting: ' + ex.getMessage();
            }

            results.add(res);
        }

        return results;
    }
}
