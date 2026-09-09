@isTest
public class GmailServiceTest {

    public class GmailHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint();
            String method = req.getMethod();

            // OAuth Token Exchange
            if (endpoint.contains('oauth2.googleapis.com/token') || endpoint.contains('/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"ya29.mock_token_gmail_test","expires_in":3600,"token_type":"Bearer"}');
                return res;
            }

            // Watch Mailbox
            if (endpoint.endsWith('/watch')) {
                res.setStatusCode(200);
                res.setBody('{"historyId":"12345","expiration":"1756800000000"}');
                return res;
            }

            // Gemini AI API
            if (endpoint.contains('generativelanguage.googleapis.com')) {
                res.setStatusCode(200);
                res.setBody('{"candidates":[{"content":{"parts":[{"text":"{\\"executiveSummary\\":\\"Discussion regarding business proposal.\\",\\"keyPoints\\":[\\"Proposal submitted\\",\\"Follow-up meeting requested\\"],\\"actionItems\\":[\\"Review agreement and reply\\"]}"}]}}]}');
                return res;
            }

            // Stop Watch
            if (endpoint.endsWith('/stop')) {
                res.setStatusCode(204);
                res.setBody('');
                return res;
            }

            // History List
            if (endpoint.contains('/history')) {
                res.setStatusCode(200);
                res.setBody('{'
                    + '"historyId":"12349",'
                    + '"history":['
                    + '  {"messagesAdded":[{"message":{"id":"msg_mock_1","threadId":"th_mock_1"}}]}'
                    + ']'
                    + '}');
                return res;
            }

            // Send Message
            if (endpoint.endsWith('/messages/send')) {
                res.setStatusCode(200);
                res.setBody('{"id":"msg_sent_999","threadId":"th_sent_999","labelIds":["SENT"]}');
                return res;
            }

            // Search / List Threads
            if (endpoint.contains('/threads?') || endpoint.endsWith('/threads')) {
                res.setStatusCode(200);
                res.setBody('{"threads":[{"id":"th_mock_1","snippet":"Hello test snippet","historyId":"12349"}]}');
                return res;
            }

            // Get Thread
            if (endpoint.contains('/threads/')) {
                res.setStatusCode(200);
                res.setBody('{'
                    + '"id":"th_mock_1",'
                    + '"historyId":"12349",'
                    + '"messages":['
                    + '  {'
                    + '    "id":"msg_mock_1",'
                    + '    "threadId":"th_mock_1",'
                    + '    "snippet":"Hello test snippet",'
                    + '    "internalDate":"1725180000000",'
                    + '    "payload":{'
                    + '      "headers":['
                    + '        {"name":"From","value":"John Doe <client@example.com>"},'
                    + '        {"name":"To","value":"sumit@skg5.com"},'
                    + '        {"name":"Subject","value":"Proposal Inquiry"},'
                    + '        {"name":"Date","value":"Tue, 1 Sep 2026 12:00:00 +0000"}'
                    + '      ],'
                    + '      "parts":['
                    + '        {'
                    + '          "mimeType":"text/html",'
                    + '          "body":{"data":"PHA+SGVsbG8gZnJvbSBHbWFpbCE8L3A+"}'
                    + '        }'
                    + '      ]'
                    + '    }'
                    + '  }'
                    + ']'
                    + '}');
                return res;
            }

            // Get Message
            if (endpoint.contains('/messages/')) {
                res.setStatusCode(200);
                res.setBody('{'
                    + '"id":"msg_mock_1",'
                    + '"threadId":"th_mock_1",'
                    + '"snippet":"Hello test snippet",'
                    + '"internalDate":"1725180000000",'
                    + '"payload":{'
                    + '  "headers":['
                    + '    {"name":"From","value":"John Doe <client@example.com>"},'
                    + '    {"name":"To","value":"sumit@skg5.com"},'
                    + '    {"name":"Subject","value":"Proposal Inquiry"}'
                    + '  ],'
                    + '  "parts":['
                    + '    {'
                    + '      "mimeType":"text/html",'
                    + '      "body":{"data":"PHA+SGVsbG8gZnJvbSBHbWFpbCE8L3A+"}'
                    + '    }'
                    + '  ]'
                    + '}'
                    + '}');
                return res;
            }

            // Default fallback
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @testSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Gmail Account', CSM_Email__c = 'csm@company.com');
        insert acc;

        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'client@example.com',
            AccountId = acc.Id
        );
        insert con;

        // Insert an initial synced Event
        Event ev = new Event(
            Subject = 'Email: Proposal Inquiry',
            WhatId = acc.Id,
            WhoId = con.Id,
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addMinutes(30),
            Gmail_Message_Id__c = 'msg_mock_existing',
            Gmail_Thread_Id__c = 'th_mock_1',
            Gmail_Snippet__c = 'Existing snippet',
            Gmail_From_Address__c = 'client@example.com',
            Gmail_To_Address__c = 'sumit@skg5.com',
            Gmail_Direction__c = 'INBOUND',
            Last_Sync_Source__c = 'GMAIL',
            Sync_Status__c = 'Synced'
        );
        insert ev;
    }

    @isTest
    static void testWatchAndStopWatch() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());

        Test.startTest();
        GmailService.GmailWatchResult watchRes = GmailService.watchMailbox('sumit@skg5.com', 'projects/test/topics/gmail-notifications');
        System.assertNotEquals(null, watchRes, 'Watch result should not be null');
        System.assertEquals('12345', watchRes.historyId, 'History ID should match mock');

        Boolean stopRes = GmailService.stopWatchMailbox('sumit@skg5.com');
        System.assertEquals(true, stopRes, 'Stop watch should succeed');
        Test.stopTest();
    }

    @isTest
    static void testListHistoryAndGetMessage() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());

        Test.startTest();
        GmailService.GmailHistoryResult hist = GmailService.listHistory('sumit@skg5.com', '12340');
        System.assertNotEquals(null, hist, 'History result should not be null');
        System.assertEquals('12349', hist.latestHistoryId, 'History ID should match mock');
        System.assertEquals(1, hist.messageIdsAdded.size(), 'Should have 1 added message');

        GmailService.GmailMessageDTO msg = GmailService.getMessage('sumit@skg5.com', 'msg_mock_1');
        System.assertNotEquals(null, msg, 'Message should not be null');
        System.assertEquals('Proposal Inquiry', msg.subject, 'Subject should match mock');
        System.assertEquals('INBOUND', msg.direction, 'Direction should be INBOUND');

        GmailService.GmailThreadDTO thread = GmailService.getThread('sumit@skg5.com', 'th_mock_1');
        System.assertNotEquals(null, thread, 'Thread should not be null');
        System.assertEquals(1, thread.messages.size(), 'Thread should contain 1 message');
        Test.stopTest();
    }

    @isTest
    static void testSendMessage() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());

        Test.startTest();
        GmailService.GmailMessageDTO sent = GmailService.sendMessage(
            'sumit@skg5.com', 
            'client@example.com', 
            'manager@example.com', 
            'Re: Proposal Inquiry', 
            '<p>Thank you for reaching out!</p>', 
            'th_mock_1', 
            '<orig_msg@mail.gmail.com>'
        );
        Test.stopTest();

        System.assertNotEquals(null, sent, 'Sent message should not be null');
        System.assertEquals('msg_sent_999', sent.id, 'Sent message ID should match mock');
        System.assertEquals('OUTBOUND', sent.direction, 'Sent message direction should be OUTBOUND');
    }

    @isTest
    static void testWebhookAndQueueable() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/gmail/webhook';
        req.httpMethod = 'POST';

        // Simulated Pub/Sub push JSON
        String pubsubDataJson = '{"emailAddress":"sumit@skg5.com","historyId":"12340"}';
        String base64Data = EncodingUtil.base64Encode(Blob.valueOf(pubsubDataJson));
        req.requestBody = Blob.valueOf('{"message":{"data":"' + base64Data + '","messageId":"sub_msg_1"}}');

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        GmailWebhookRestResource.handleGet();
        System.assertEquals(200, res.statusCode);

        GmailWebhookRestResource.handlePost();
        System.assertEquals(200, res.statusCode);

        // Directly execute the Queueable worker
        GmailSyncQueueable job = new GmailSyncQueueable('sumit@skg5.com', '12340');
        System.enqueueJob(job);
        Test.stopTest();

        // Verify Event was upserted
        List<Event> events = [SELECT Id, Subject, Gmail_Message_Id__c FROM Event WHERE Gmail_Message_Id__c = 'msg_mock_1'];
        System.assertEquals(1, events.size(), 'Event should be created from Gmail delta sync');
    }

    @isTest
    static void testAccountGmailControllerQueries() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Map<String, Object> ctx = AccountGmailController.getAccountContext(acc.Id);
        System.assertNotEquals(null, ctx.get('account'), 'Account context should return account');
        System.assertNotEquals(null, ctx.get('contacts'), 'Account context should return contacts');
        System.assertEquals('csm@company.com', ctx.get('csmEmail'), 'CSM email should match Account field');

        List<AccountGmailController.ThreadSummaryDTO> threads = AccountGmailController.getAccountEmailThreads(acc.Id, '');
        System.assertNotEquals(0, threads.size(), 'Threads list should not be empty');
        Test.stopTest();
    }

    @isTest
    static void testAccountGmailControllerThreadDetails() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Map<String, Object> threadDetails = AccountGmailController.getThreadDetails('th_mock_1', acc.Id);
        System.assertNotEquals(null, threadDetails.get('thread'), 'Thread details should not be null');
        Test.stopTest();
    }

    @isTest
    static void testAccountGmailControllerSendEmail() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id, Email FROM Contact LIMIT 1];

        Test.startTest();
        Map<String, Object> sendResult = AccountGmailController.sendEmail(
            acc.Id, 
            con.Id, 
            con.Email, 
            '', 
            'Testing Outbound Compose', 
            '<p>Test body content</p>', 
            null, 
            null
        );
        System.assertEquals(true, sendResult.get('success'), 'Send email should succeed');
        Test.stopTest();
    }

    @isTest
    static void testSearchThreads() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());
        Test.startTest();
        List<String> thIds = GmailService.searchThreads('sumit@skg5.com', 'from:client@example.com', 5);
        Test.stopTest();
        System.assertNotEquals(null, thIds);
        System.assertEquals(1, thIds.size());
        System.assertEquals('th_mock_1', thIds[0]);
    }

    @isTest
    static void testThreadAiSummaryGeneration() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        GmailAIService.ThreadSummaryResult res1 = AccountGmailController.getOrGenerateThreadSummary('th_mock_1', acc.Id, false);
        Test.stopTest();

        System.assertNotEquals(null, res1);
        System.assertNotEquals(null, res1.executiveSummary);
        System.assertEquals(false, res1.isCached, 'First call should be fresh generation');

        List<Gmail_Thread_Summary__c> saved = [SELECT Id, Thread_Id__c, Message_Count__c FROM Gmail_Thread_Summary__c WHERE Thread_Id__c = 'th_mock_1'];
        System.assertEquals(1, saved.size(), 'Summary record should be saved in DB');
    }

    @isTest
    static void testThreadAiSummaryCacheHit() {
        Test.setMock(HttpCalloutMock.class, new GmailHttpMock());
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Pre-insert cached summary matching mock thread count (1) and latest message id (msg_mock_1)
        Gmail_Thread_Summary__c gts = new Gmail_Thread_Summary__c(
            Thread_Id__c = 'th_mock_1',
            Account__c = acc.Id,
            Executive_Summary__c = 'Cached discussion summary.',
            Key_Points__c = 'Point 1\nPoint 2',
            Action_Items__c = 'Action 1',
            Message_Count__c = 1,
            Latest_Message_Id__c = 'msg_mock_existing',
            Last_Generated_At__c = DateTime.now(),
            Model_Used__c = 'Test Engine'
        );
        insert gts;

        Test.startTest();
        GmailAIService.ThreadSummaryResult res = AccountGmailController.getOrGenerateThreadSummary('th_mock_1', acc.Id, false);
        Test.stopTest();

        System.assertNotEquals(null, res);
        System.assertEquals(true, res.isCached, 'Should return cached summary without regeneration');
        System.assertEquals('Cached discussion summary.', res.executiveSummary);
    }

    @isTest
    static void testFallbackAiSummary() {
        GmailService.GmailMessageDTO m1 = new GmailService.GmailMessageDTO();
        m1.id = 'm1';
        m1.direction = 'OUTBOUND';
        m1.fromAddress = 'rep@company.com';
        m1.toAddress = 'client@example.com';
        m1.subject = 'Project Proposal';
        m1.snippet = 'Please find attached the proposal for review.';
        m1.dateVal = DateTime.now().addDays(-2);

        GmailService.GmailMessageDTO m2 = new GmailService.GmailMessageDTO();
        m2.id = 'm2';
        m2.direction = 'INBOUND';
        m2.fromAddress = 'client@example.com';
        m2.toAddress = 'rep@company.com';
        m2.subject = 'Re: Project Proposal';
        m2.snippet = 'Looks great, when can we start?';
        m2.dateVal = DateTime.now();

        List<GmailService.GmailMessageDTO> msgs = new List<GmailService.GmailMessageDTO>{ m1, m2 };

        Test.startTest();
        GmailAIService.ThreadSummaryResult res = GmailAIService.generateFallbackSummary(msgs);
        Test.stopTest();

        System.assertNotEquals(null, res);
        System.assert(res.executiveSummary.contains('Project Proposal'));
        System.assertNotEquals(0, res.keyPoints.size());
        System.assertNotEquals(0, res.actionItems.size());
    }

    @isTest
    static void testBuildThreadFromEvents() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        GmailService.GmailThreadDTO dto = AccountGmailController.buildThreadFromEvents('th_mock_1', acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto);
        System.assertEquals('th_mock_1', dto.id);
        System.assertNotEquals(0, dto.messages.size());
    }

    @isTest
    static void testInboundEmailHandler() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id, Email FROM Contact LIMIT 1];

        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = con.Email;
        email.toAddresses = new List<String>{ 'csm@company.com' };
        email.subject = 'Re: Proposal Inquiry [th_mock_1]';
        email.plainTextBody = 'Hello, this is a reply to the proposal.';

        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        env.fromAddress = con.Email;
        env.toAddress = 'inbound@salesforce.com';

        Test.startTest();
        AccountGmailInboundHandler handler = new AccountGmailInboundHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, env);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Inbound email handling should succeed');
        List<Event> inboundEvents = [SELECT Id, Subject, Gmail_Direction__c FROM Event WHERE Gmail_Direction__c = 'INBOUND'];
        System.assertNotEquals(0, inboundEvents.size(), 'INBOUND event should be created');
    }

    @isTest
    static void testSimulateInboundReply() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        Map<String, Object> res = AccountGmailController.simulateInboundReply(
            acc.Id, 
            con.Id, 
            'th_mock_1', 
            'Client reply message content'
        );
        Test.stopTest();

        System.assertEquals(true, res.get('success'), 'Simulation should succeed');
        System.assertNotEquals(null, res.get('eventId'), 'Event ID should be returned');
    }

    @isTest
    static void testStripQuotedReply() {
        String input = 'Hi Sumit, this is my live reply from Gmail!\n\nOn Wed, 2 Sept 2026, 17:16, Sumit Gupta <email@...> wrote:\n> Previous message...';
        String cleaned = AccountGmailInboundHandler.stripQuotedReply(input);
        System.assertEquals('Hi Sumit, this is my live reply from Gmail!', cleaned.trim());
    }

    @isTest
    static void testCsmPersonalEmailReply() {
        Account acc = [SELECT Id, CSM_Email__c FROM Account LIMIT 1];
        Contact con = [SELECT Id, Email FROM Contact LIMIT 1];

        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = acc.CSM_Email__c; // CSM personal email
        email.toAddresses = new List<String>{ 'inbound@salesforce.com' };
        email.subject = 'Re: Proposal Inquiry [th_mock_1]';
        email.plainTextBody = 'Sounds great, let us connect tomorrow.';

        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        env.fromAddress = acc.CSM_Email__c;
        env.toAddress = 'inbound@salesforce.com';

        Test.startTest();
        AccountGmailInboundHandler handler = new AccountGmailInboundHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, env);
        Test.stopTest();

        System.assertEquals(true, result.success, 'CSM personal reply handling should succeed');
        List<Event> outboundEvents = [SELECT Id, Subject, Gmail_Direction__c FROM Event WHERE Gmail_Direction__c = 'OUTBOUND' AND Subject LIKE '%Proposal Inquiry%'];
        System.assertNotEquals(0, outboundEvents.size(), 'OUTBOUND event should be created for CSM personal reply');
    }
}
