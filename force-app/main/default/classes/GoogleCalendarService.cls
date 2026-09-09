public with sharing class GoogleCalendarService {
    public class GoogleCalendarException extends Exception {}

    private static final String CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3';

    public class GoogleEventResult {
        public String id;
        public String status;
        public String summary;
        public String description;
        public String hangoutLink;
        public String etag;
        public DateTime startDateTime;
        public DateTime endDateTime;
        public List<String> attendeeEmails;
        public String rawJson;
    }

    /**
     * @description Creates an event in the user's primary Google Calendar.
     * @param userEmail Google user email
     * @param summary Title of meeting
     * @param description Details of meeting
     * @param startDt Start DateTime
     * @param endDt End DateTime
     * @param attendeeEmails List of attendee email addresses
     * @param addGoogleMeet Boolean flag to create a Google Meet link
     */
    public static GoogleEventResult createEvent(
        String userEmail, 
        String summary, 
        String description, 
        DateTime startDt, 
        DateTime endDt, 
        List<String> attendeeEmails, 
        Boolean addGoogleMeet
    ) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = CALENDAR_API_BASE + '/calendars/primary/events?sendUpdates=none';
        if (addGoogleMeet == true) {
            endpoint += '&conferenceDataVersion=1';
        }

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('summary', summary);
        if (String.isNotBlank(description)) {
            payload.put('description', description);
        }

        // Format ISO 8601 DateTime strings (RFC3339)
        Map<String, Object> startMap = new Map<String, Object>{
            'dateTime' => startDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'timeZone' => 'UTC'
        };
        Map<String, Object> endMap = new Map<String, Object>{
            'dateTime' => endDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'timeZone' => 'UTC'
        };
        payload.put('start', startMap);
        payload.put('end', endMap);

        if (attendeeEmails != null && !attendeeEmails.isEmpty()) {
            List<Map<String, String>> attendees = new List<Map<String, String>>();
            for (String email : attendeeEmails) {
                if (String.isNotBlank(email)) {
                    attendees.add(new Map<String, String>{ 'email' => email.trim() });
                }
            }
            if (!attendees.isEmpty()) {
                payload.put('attendees', attendees);
            }
        }

        if (addGoogleMeet == true) {
            Map<String, Object> createReq = new Map<String, Object>{
                'requestId' => 'meet_' + String.valueOf(DateTime.now().getTime()) + '_' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'conferenceSolutionKey' => new Map<String, String>{ 'type' => 'hangoutsMeet' }
            };
            payload.put('conferenceData', new Map<String, Object>{ 'createRequest' => createReq });
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            return parseGoogleEvent(res.getBody());
        } else {
            throw new GoogleCalendarException('Error creating Google Calendar event: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Reschedules (shifts) an event in Google Calendar.
     */
    public static GoogleEventResult patchEventTimes(
        String userEmail, 
        String googleEventId, 
        DateTime startDt, 
        DateTime endDt
    ) {
        if (String.isBlank(googleEventId)) {
            throw new GoogleCalendarException('Google Event ID is required for rescheduling.');
        }

        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = CALENDAR_API_BASE + '/calendars/primary/events/' + EncodingUtil.urlEncode(googleEventId, 'UTF-8');

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('start', new Map<String, Object>{
            'dateTime' => startDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'timeZone' => 'UTC'
        });
        payload.put('end', new Map<String, Object>{
            'dateTime' => endDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'timeZone' => 'UTC'
        });

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            return parseGoogleEvent(res.getBody());
        } else {
            throw new GoogleCalendarException('Error updating Google Calendar event: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Cancels (deletes) an event from Google Calendar.
     */
    public static Boolean deleteEvent(String userEmail, String googleEventId) {
        if (String.isBlank(googleEventId)) {
            return true;
        }

        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = CALENDAR_API_BASE + '/calendars/primary/events/' + EncodingUtil.urlEncode(googleEventId, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('DELETE');
        req.setHeader('Authorization', 'Bearer ' + token);

        Http http = new Http();
        HttpResponse res = http.send(req);

        // 204 No Content or 410 Gone / 404 Not Found count as deleted
        if (res.getStatusCode() == 204 || res.getStatusCode() == 200 || res.getStatusCode() == 410 || res.getStatusCode() == 404) {
            return true;
        } else {
            throw new GoogleCalendarException('Error deleting Google Calendar event: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Fetches delta events or events list using optional syncToken.
     */
    public static Map<String, Object> getEventsDelta(String userEmail, String syncToken) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = CALENDAR_API_BASE + '/calendars/primary/events?singleEvents=true';
        if (String.isNotBlank(syncToken)) {
            endpoint += '&syncToken=' + EncodingUtil.urlEncode(syncToken, 'UTF-8');
        } else {
            // Default to past 7 days up to 6 months future
            DateTime minDt = DateTime.now().addDays(-7);
            endpoint += '&timeMin=' + EncodingUtil.urlEncode(minDt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''), 'UTF-8');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } else {
            throw new GoogleCalendarException('Error fetching Google events: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Registers a Push Notification webhook channel with Google Calendar.
     */
    public static Map<String, Object> registerWatchChannel(String userEmail, String channelId, String webhookUrl, String channelToken) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = CALENDAR_API_BASE + '/calendars/primary/events/watch';

        Map<String, Object> payload = new Map<String, Object>{
            'id' => channelId,
            'type' => 'web_hook',
            'address' => webhookUrl
        };
        if (String.isNotBlank(channelToken)) {
            payload.put('token', channelToken);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } else {
            throw new GoogleCalendarException('Error registering watch channel: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Stops a Push Notification webhook channel.
     */
    public static Boolean stopWatchChannel(String userEmail, String channelId, String resourceId) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = CALENDAR_API_BASE + '/channels/stop';

        Map<String, Object> payload = new Map<String, Object>{
            'id' => channelId,
            'resourceId' => resourceId
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));

        Http http = new Http();
        HttpResponse res = http.send(req);

        return (res.getStatusCode() >= 200 && res.getStatusCode() < 300);
    }

    /**
     * @description Helper to parse JSON Google event to GoogleEventResult wrapper.
     */
    public static GoogleEventResult parseGoogleEvent(String rawJson) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(rawJson);
        GoogleEventResult result = new GoogleEventResult();
        result.id = (String) data.get('id');
        result.status = (String) data.get('status');
        result.summary = (String) data.get('summary');
        result.description = (String) data.get('description');
        result.hangoutLink = (String) data.get('hangoutLink');
        result.etag = (String) data.get('etag');
        result.rawJson = rawJson;

        // Parse Start Time
        if (data.containsKey('start')) {
            Map<String, Object> startMap = (Map<String, Object>) data.get('start');
            if (startMap.containsKey('dateTime')) {
                result.startDateTime = parseIso8601((String) startMap.get('dateTime'));
            }
        }

        // Parse End Time
        if (data.containsKey('end')) {
            Map<String, Object> endMap = (Map<String, Object>) data.get('end');
            if (endMap.containsKey('dateTime')) {
                result.endDateTime = parseIso8601((String) endMap.get('dateTime'));
            }
        }

        // Parse Attendees
        result.attendeeEmails = new List<String>();
        if (data.containsKey('attendees')) {
            List<Object> attendeesList = (List<Object>) data.get('attendees');
            for (Object attObj : attendeesList) {
                Map<String, Object> attMap = (Map<String, Object>) attObj;
                if (attMap.containsKey('email')) {
                    result.attendeeEmails.add((String) attMap.get('email'));
                }
            }
        }

        return result;
    }

    private static DateTime parseIso8601(String isoString) {
        if (String.isBlank(isoString)) {
            return null;
        }
        try {
            // Replace 'Z' with '+00:00' if needed for DateTime.valueOf parsing
            String formatted = isoString.replace('T', ' ').replace('Z', '');
            if (formatted.contains('.')) {
                formatted = formatted.substringBefore('.');
            }
            if (formatted.contains('+')) {
                formatted = formatted.substringBefore('+');
            }
            return DateTime.valueOfGmt(formatted);
        } catch (Exception e) {
            return DateTime.now();
        }
    }
}
