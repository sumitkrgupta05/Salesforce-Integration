@IsTest
private class GoogleCalendarTest {

    public class GoogleHttpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public GoogleHttpMock() {
            this.statusCode = 200;
            this.responseBody = null;
        }

        public GoogleHttpMock(Integer code, String body) {
            this.statusCode = code;
            this.responseBody = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (this.responseBody != null) {
                res.setStatusCode(this.statusCode);
                res.setBody(this.responseBody);
                return res;
            }

            String endpoint = req.getEndpoint();
            String method = req.getMethod();

            if (endpoint.contains('/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_test_token_xyz","expires_in":3600,"token_type":"Bearer"}');
            } else if (endpoint.contains('/watch')) {
                res.setStatusCode(200);
                res.setBody('{"kind":"api#channel","id":"chan_001","resourceId":"res_001","expiration":"1700000000000"}');
            } else if (endpoint.contains('/channels/stop')) {
                res.setStatusCode(200);
                res.setBody('{}');
            } else if (endpoint.contains('/calendars/primary/events') && method == 'POST') {
                res.setStatusCode(201);
                res.setBody('{' +
                    '"id":"mock_google_evt_101",' +
                    '"status":"confirmed",' +
                    '"summary":"Test Client Meeting",' +
                    '"description":"Discuss project details",' +
                    '"hangoutLink":"https://meet.google.com/abc-defg-hij",' +
                    '"etag":"\\"etag_val_001\\"",' +
                    '"start":{"dateTime":"2026-09-01T10:00:00Z"},' +
                    '"end":{"dateTime":"2026-09-01T10:30:00Z"},' +
                    '"attendees":[{"email":"contact@skg5.com"}]' +
                '}');
            } else if (endpoint.contains('/calendars/primary/events') && method == 'PATCH') {
                res.setStatusCode(200);
                res.setBody('{' +
                    '"id":"mock_google_evt_101",' +
                    '"status":"confirmed",' +
                    '"summary":"Test Client Meeting Rescheduled",' +
                    '"etag":"\\"etag_val_002\\"",' +
                    '"start":{"dateTime":"2026-09-01T14:00:00Z"},' +
                    '"end":{"dateTime":"2026-09-01T14:30:00Z"}' +
                '}');
            } else if (endpoint.contains('/calendars/primary/events') && method == 'DELETE') {
                res.setStatusCode(204);
                res.setBody('');
            } else if (endpoint.contains('/calendars/primary/events') && method == 'GET') {
                res.setStatusCode(200);
                res.setBody('{' +
                    '"nextSyncToken":"sync_tok_999",' +
                    '"items":[' +
                        '{' +
                            '"id":"mock_google_evt_101",' +
                            '"status":"confirmed",' +
                            '"summary":"Inbound Synced Event",' +
                            '"description":"Detailed notes",' +
                            '"hangoutLink":"https://meet.google.com/xyz",' +
                            '"start":{"dateTime":"2026-09-02T10:00:00Z"},' +
                            '"end":{"dateTime":"2026-09-02T10:30:00Z"},' +
                            '"attendees":[{"email":"contact@skg5.com"}]' +
                        '},' +
                        '{' +
                            '"id":"mock_google_evt_cancelled",' +
                            '"status":"cancelled"' +
                        '}' +
                    ']' +
                '}');
            } else {
                res.setStatusCode(200);
                res.setBody('{}');
            }

            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Acme Test Corp');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            Email = 'contact@skg5.com',
            Title = 'VP Sales',
            AccountId = acc.Id
        );
        insert con;

        Event ev = new Event(
            Subject = 'Existing Meeting',
            StartDateTime = DateTime.now().addDays(1),
            EndDateTime = DateTime.now().addDays(1).addMinutes(30),
            WhatId = acc.Id,
            WhoId = con.Id,
            Google_Event_Id__c = 'mock_google_evt_existing',
            Google_ETag__c = 'etag_old_001',
            Google_Meet_Link__c = 'https://meet.google.com/test-meet',
            Last_Sync_Source__c = 'SALESFORCE',
            Sync_Status__c = 'Synced'
        );
        insert ev;
    }

    @IsTest
    static void testGoogleAuthService() {
        Test.setMock(HttpCalloutMock.class, new GoogleHttpMock());

        Test.startTest();
        String token = GoogleAuthService.getAccessToken('sumit@skg5.com');
        System.assertNotEquals(null, token, 'Access token should not be null');

        String cachedToken = GoogleAuthService.getAccessToken('sumit@skg5.com');
        System.assertEquals(token, cachedToken, 'Should retrieve from memory cache');

        String defaultToken = GoogleAuthService.getAccessToken(null);
        System.assertNotEquals(null, defaultToken);

        // Test error response
        Test.setMock(HttpCalloutMock.class, new GoogleHttpMock(400, '{"error":"invalid_grant","error_description":"Invalid JWT"}'));
        try {
            GoogleAuthService.getAccessToken('error_user@skg5.com');
        } catch (GoogleAuthService.GoogleAuthException ex) {
            System.assert(ex.getMessage().contains('Failed to obtain Google access token'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGoogleCalendarServiceOperations() {
        Test.setMock(HttpCalloutMock.class, new GoogleHttpMock());

        Test.startTest();
        // 1. Create with Meet
        GoogleCalendarService.GoogleEventResult createResult = GoogleCalendarService.createEvent(
            'sumit@skg5.com',
            'Test Client Meeting',
            'Description text',
            DateTime.now().addHours(2),
            DateTime.now().addHours(3),
            new List<String>{'contact@skg5.com'},
            true
        );
        System.assertEquals('mock_google_evt_101', createResult.id);
        System.assertEquals('https://meet.google.com/abc-defg-hij', createResult.hangoutLink);

        // 2. Patch
        GoogleCalendarService.GoogleEventResult patchResult = GoogleCalendarService.patchEventTimes(
            'sumit@skg5.com',
            'mock_google_evt_101',
            DateTime.now().addDays(1),
            DateTime.now().addDays(1).addMinutes(30)
        );
        System.assertNotEquals(null, patchResult.etag);

        // 3. Delete
        Boolean deleteSuccess = GoogleCalendarService.deleteEvent('sumit@skg5.com', 'mock_google_evt_101');
        System.assertEquals(true, deleteSuccess);

        // 4. Delta
        Map<String, Object> delta = GoogleCalendarService.getEventsDelta('sumit@skg5.com', 'sync_tok_999');
        System.assert(delta.containsKey('items'));

        // 5. Watch
        Map<String, Object> watchRes = GoogleCalendarService.registerWatchChannel('sumit@skg5.com', 'chan_001', 'https://example.com/webhook', 'tok');
        System.assertEquals('chan_001', (String) watchRes.get('id'));

        // 6. Stop
        Boolean stopSuccess = GoogleCalendarService.stopWatchChannel('sumit@skg5.com', 'chan_001', 'res_001');
        System.assertEquals(true, stopSuccess);

        // 7. Error callout test
        Test.setMock(HttpCalloutMock.class, new GoogleHttpMock(500, '{"error":{"message":"Internal Error"}}'));
        try {
            GoogleCalendarService.deleteEvent('sumit@skg5.com', 'mock_evt_fail');
        } catch (GoogleCalendarService.GoogleCalendarException ex) {
            System.assert(ex.getMessage().contains('Error deleting Google Calendar event'));
        }

        Test.stopTest();
    }

    @IsTest
    static void testAccountCalendarControllerQueries() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // Integration status
        AccountCalendarController.IntegrationStatusDTO status = AccountCalendarController.getIntegrationStatus();
        System.assertNotEquals(null, status);
        System.assertEquals(true, status.isConfigured);

        // Contacts
        List<AccountCalendarController.ContactDTO> contacts = AccountCalendarController.getAccountContacts(acc.Id);
        System.assertEquals(1, contacts.size());

        // Meetings
        List<AccountCalendarController.EventDTO> meetings = AccountCalendarController.getAccountMeetings(acc.Id);
        System.assertEquals(1, meetings.size());
        System.assertEquals('Existing Meeting', meetings[0].subject);
        Test.stopTest();
    }

    @IsTest
    static void testAccountCalendarControllerCreate() {
        Test.setMock(HttpCalloutMock.class, new GoogleHttpMock());

        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id, Email FROM Contact LIMIT 1];

        Test.startTest();
        DateTime startDt = DateTime.now().addDays(2);
        DateTime endDt = startDt.addMinutes(45);
        AccountCalendarController.EventDTO createdEv = AccountCalendarController.createMeeting(
            acc.Id,
            'Acme Q3 Review',
            'Quarterly strategic roadmap',
            startDt,
            endDt,
            new List<String>{con.Email},
            true,
            con.Id
        );
        System.assertEquals('mock_google_evt_101', createdEv.googleEventId);
        System.assertEquals('https://meet.google.com/abc-defg-hij', createdEv.googleMeetLink);

        // Validation test
        try {
            AccountCalendarController.createMeeting(acc.Id, '', '', null, null, null, false, null);
        } catch (Exception ex) {
            System.assert(ex.getMessage().contains('Subject is required'));
        }

        Test.stopTest();
    }

    @IsTest
    static void testAccountCalendarControllerRescheduleAndCancel() {
        Test.setMock(HttpCalloutMock.class, new GoogleHttpMock());

        Event ev = [SELECT Id FROM Event WHERE Google_Event_Id__c = 'mock_google_evt_existing' LIMIT 1];

        Test.startTest();
        // Reschedule
        DateTime newStart = DateTime.now().addDays(3);
        DateTime newEnd = newStart.addMinutes(30);
        AccountCalendarController.EventDTO rescheduled = AccountCalendarController.rescheduleMeeting(ev.Id, newStart, newEnd);
        System.assertEquals(newStart, rescheduled.startDateTime);

        // Cancel
        Boolean cancelled = AccountCalendarController.cancelMeeting(ev.Id);
        System.assertEquals(true, cancelled);

        Test.stopTest();
    }

    @IsTest
    static void testGoogleWebhookAndQueueable() {
        Test.setMock(HttpCalloutMock.class, new GoogleHttpMock());

        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id, Email FROM Contact LIMIT 1];

        Event evCancelled = new Event(
            Subject = 'Cancelled Meeting',
            StartDateTime = DateTime.now().addDays(1),
            EndDateTime = DateTime.now().addDays(1).addMinutes(30),
            WhatId = acc.Id,
            WhoId = con.Id,
            Google_Event_Id__c = 'mock_google_evt_cancelled',
            Last_Sync_Source__c = 'SALESFORCE'
        );
        insert evCancelled;

        Test.startTest();
        // 1. Webhook Handshake ('sync' state)
        RestRequest reqSync = new RestRequest();
        reqSync.requestURI = '/services/apexrest/google/calendar/webhook';
        reqSync.httpMethod = 'POST';
        reqSync.headers.put('X-Goog-Resource-State', 'sync');
        reqSync.headers.put('X-Goog-Channel-ID', 'chan_sync_test');
        RestContext.request = reqSync;
        RestContext.response = new RestResponse();

        GoogleCalendarWebhookRestResource.handleNotification();
        System.assertEquals(200, RestContext.response.statusCode);

        // 2. Webhook Inbound Change ('exists' state)
        RestRequest reqExists = new RestRequest();
        reqExists.requestURI = '/services/apexrest/google/calendar/webhook';
        reqExists.httpMethod = 'POST';
        reqExists.headers.put('X-Goog-Resource-State', 'exists');
        reqExists.headers.put('X-Goog-Channel-ID', 'chan_exists_test');
        reqExists.headers.put('X-Goog-Channel-Token', 'sumit@skg5.com');
        RestContext.request = reqExists;
        RestContext.response = new RestResponse();

        GoogleCalendarWebhookRestResource.handleNotification();
        System.assertEquals(200, RestContext.response.statusCode);

        // 3. Queueable direct execution
        GoogleCalendarQueueable qJob = new GoogleCalendarQueueable('sumit@skg5.com', null);
        System.enqueueJob(qJob);

        Test.stopTest();

        // Verify cancelled event was deleted
        List<Event> cancelledEvents = [SELECT Id FROM Event WHERE Google_Event_Id__c = 'mock_google_evt_cancelled'];
        System.assertEquals(0, cancelledEvents.size(), 'Cancelled event should be deleted by delta sync');
    }
}
