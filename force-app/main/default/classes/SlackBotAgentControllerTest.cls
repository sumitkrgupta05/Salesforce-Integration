@IsTest
private class SlackBotAgentControllerTest {

    private class GatewayMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"ok":true,"ts":"1725360000.123","isSuccess":true,"messageText":"Here is the Slack Bot Agent response!","slackThreadUrl":"https://slack.com/app_redirect?channel=D0BUQS5V68Z&message_ts=1725360000.123"}');
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        Account testAcc = new Account(
            Name = 'Edge Communications Gateway',
            Industry = 'Technology',
            CSM_Email__c = 'skgsummo5@gmail.com'
        );
        insert testAcc;

        Contact testContact = new Contact(
            FirstName = 'Rose',
            LastName = 'Gonzalez',
            Email = 'rose@edge.com',
            Title = 'SVP, Procurement',
            AccountId = testAcc.Id
        );
        insert testContact;

        Gmail_Thread_Summary__c summary = new Gmail_Thread_Summary__c(
            Account__c = testAcc.Id,
            Thread_Id__c = 'slack-thread-123',
            Executive_Summary__c = 'Quarterly customer sync.',
            Key_Points__c = '• System adoption on track',
            Action_Items__c = '• Schedule follow up meeting',
            Message_Count__c = 2,
            Last_Generated_At__c = DateTime.now()
        );
        insert summary;
    }

    @IsTest
    static void testGetAccountContext() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Test.startTest();
        SlackBotAgentController.AccountContextDTO ctx = SlackBotAgentController.getAccountContext(acc.Id);
        SlackBotAgentController.AccountContextDTO emptyCtx = SlackBotAgentController.getAccountContext(null);
        Test.stopTest();

        Assert.areEqual(acc.Id, ctx.accountId, 'Account ID should match');
        Assert.areEqual('Edge Communications Gateway', ctx.accountName, 'Name should match');
        Assert.isTrue(ctx.initialGreeting.contains('Edge Communications Gateway'), 'Greeting should mention account');
        Assert.isNotNull(emptyCtx.initialGreeting, 'Empty context greeting should not be null');
    }

    @IsTest
    static void testSendMessageGatewayActive() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        SlackBotAgentController.mockGatewayUrl = 'https://mock-gateway.ngrok-free.app/api/chat';
        Test.setMock(HttpCalloutMock.class, new GatewayMock());

        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-1', 
            'Summarize customer email thread', 
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Gateway response should succeed');
        Assert.isTrue(res.messageText.contains('Slack Bot Agent'), 'Should contain gateway response');
        Assert.isNotNull(res.slackThreadUrl, 'Should return slack thread url');
    }

    @IsTest
    static void testSendMessageNativeFallbackAccountDetails() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        SlackBotAgentController.mockGatewayUrl = null; // Forces native fallback

        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-1', 
            'Who is the CSM on this account?', 
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Should succeed via native fallback');
        Assert.isNotNull(res.messageText, 'Should return message text');
    }

    @IsTest
    static void testSendMessageNativeFallbackThreadSummary() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        SlackBotAgentController.mockGatewayUrl = null; // Forces native fallback

        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-1', 
            'Summarize the recent email thread', 
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Should succeed via native fallback');
    }

    @IsTest
    static void testSlashCommandHelp() {
        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-slash-help',
            '/help',
            null
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Help command should succeed');
        Assert.isTrue(res.messageText.contains('/account-brief'), 'Should mention account-brief');
        Assert.isTrue(res.messageText.contains('/summarize-thread'), 'Should mention summarize-thread');
    }

    @IsTest
    static void testSlashCommandAccountBriefDefault() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-slash-brief',
            '/account-brief',
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Account brief command should succeed');
        Assert.areEqual('accountCard', res.messageType, 'Should return accountCard');
        Assert.isTrue(res.messageText.contains('Edge Communications Gateway'), 'Should mention account');
        Assert.isNotNull(res.cardData.get('healthScore'), 'Should include snowflake health score');
        Assert.isNotNull(res.cardData.get('usageHours'), 'Should include snowflake usage hours');
        Assert.isNotNull(res.cardData.get('churnRisk'), 'Should include snowflake churn risk');
    }

    @IsTest
    static void testSlashCommandAccountBriefNamed() {
        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-slash-brief-named',
            '/account-brief Edge Communications Gateway',
            null
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Named account brief should succeed');
        Assert.areEqual('accountCard', res.messageType, 'Should return accountCard');
        Assert.isNotNull(res.cardData.get('healthScore'), 'Should include snowflake health score');
    }

    @IsTest
    static void testSlashCommandSnowflake() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-slash-snowflake',
            '/snowflake',
            acc.Id
        );
        SlackBotAgentController.ChatResponseDTO resNamed = SlackBotAgentController.sendMessage(
            'session-slash-snowflake-named',
            '/snowflake Edge Communications Gateway',
            null
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Snowflake command should succeed');
        Assert.areEqual('snowflakeCard', res.messageType, 'Should return snowflakeCard');
        Assert.isNotNull(res.cardData.get('healthScore'), 'Health score must not be null');
        Assert.isNotNull(res.cardData.get('usageHours'), 'Usage hours must not be null');
        Assert.isNotNull(res.cardData.get('churnRisk'), 'Churn risk must not be null');

        Assert.isTrue(resNamed.isSuccess, 'Named snowflake command should succeed');
        Assert.areEqual('snowflakeCard', resNamed.messageType, 'Should return snowflakeCard');
    }

    @IsTest
    static void testSlashCommandSummarizeThread() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-slash-thread',
            '/summarize-thread slack-thread-123',
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Summarize thread command should succeed');
        Assert.areEqual('threadSummaryCard', res.messageType, 'Should return threadSummaryCard');
    }

    @IsTest
    static void testSlashCommandUnrecognized() {
        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-slash-invalid',
            '/invalid-command-xyz',
            null
        );
        Test.stopTest();

        Assert.isFalse(res.isSuccess, 'Unrecognized command should fail gracefully');
        Assert.isTrue(res.messageText.contains('not recognized'), 'Should inform user command is not recognized');
    }

    @IsTest
    static void testBuildFullMessageTextCards() {
        // 1. Account Card
        SlackBotAgentController.ChatResponseDTO accRes = new SlackBotAgentController.ChatResponseDTO();
        accRes.messageType = 'accountCard';
        accRes.messageText = 'Account Details:';
        accRes.cardData.put('accountName', 'Test Corp');
        accRes.cardData.put('csmEmail', 'csm@test.com');
        accRes.cardData.put('primaryContactName', 'John Doe');
        accRes.cardData.put('primaryContactEmail', 'john@test.com');
        accRes.cardData.put('industry', 'Finance');
        accRes.cardData.put('executiveSummary', 'Summary preview');
        accRes.cardData.put('actionItems', 'Follow up');
        String accText = SlackBotAgentController.buildFullMessageText(accRes);
        Assert.isTrue(accText.contains('Test Corp'), 'Should format account name');
        Assert.isTrue(accText.contains('csm@test.com'), 'Should format CSM email');
        Assert.isTrue(accText.contains('Summary preview'), 'Should format brief thread preview');

        // 2. Thread Summary Card
        SlackBotAgentController.ChatResponseDTO threadRes = new SlackBotAgentController.ChatResponseDTO();
        threadRes.messageType = 'threadSummaryCard';
        threadRes.messageText = 'Thread Summary:';
        threadRes.cardData.put('threadId', 'thread-abc-123');
        threadRes.cardData.put('executiveSummary', 'Discussion about timeline');
        threadRes.cardData.put('keyPoints', '• Key point 1');
        threadRes.cardData.put('actionItems', '• Follow up');
        threadRes.cardData.put('messageCount', 3);
        String threadText = SlackBotAgentController.buildFullMessageText(threadRes);
        Assert.isTrue(threadText.contains('thread-abc-123'), 'Should format thread id');
        Assert.isTrue(threadText.contains('Discussion about timeline'), 'Should format summary');

        // 3. Meeting Card
        SlackBotAgentController.ChatResponseDTO meetingRes = new SlackBotAgentController.ChatResponseDTO();
        meetingRes.messageType = 'meetingCard';
        meetingRes.messageText = 'Meeting Booked:';
        meetingRes.cardData.put('subject', 'Q3 Sync');
        meetingRes.cardData.put('startDateTimeFormatted', 'Tomorrow 3 PM');
        meetingRes.cardData.put('attendeeEmail', 'attendee@test.com');
        meetingRes.cardData.put('googleMeetLink', 'https://meet.google.com/xyz');
        String meetText = SlackBotAgentController.buildFullMessageText(meetingRes);
        Assert.isTrue(meetText.contains('Q3 Sync'), 'Should format subject');
        Assert.isTrue(meetText.contains('https://meet.google.com/xyz'), 'Should format meet link');
    }

    @IsTest
    static void testSyncChatToSlackAndSalesforceAsync() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new GatewayMock());

        Test.startTest();
        SlackBotAgentController.syncChatToSlackAndSalesforceAsync(
            acc.Id,
            acc.Name,
            'Test User',
            '/account-brief',
            'Here is the executive brief'
        );
        Test.stopTest();

        List<Task> tasks = [SELECT Id, Subject, WhatId FROM Task WHERE WhatId = :acc.Id];
        Assert.isTrue(tasks.isEmpty(), 'Chat sync should not create tasks on the account');
    }

    @IsTest
    static void testEmptyMessage() {
        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-1', 
            '', 
            null
        );
        Test.stopTest();

        Assert.isFalse(res.isSuccess, 'Empty message should not succeed');
    }

    @IsTest
    static void testSendMessageWithExistingThreadTsGatewayActive() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        SlackBotAgentController.mockGatewayUrl = 'https://mock-gateway.ngrok-free.app/api/chat';
        Test.setMock(HttpCalloutMock.class, new GatewayMock());

        Test.startTest();
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-1', 
            'Second message continuing thread', 
            acc.Id,
            '1725360000.123'
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Gateway response should succeed');
        Assert.areEqual('1725360000.123', res.slackThreadTs, 'Should retain existing thread timestamp');
        Assert.isTrue(res.slackThreadUrl.contains('1725360000.123'), 'URL should link to existing thread');
    }

    @IsTest
    static void testSyncChatToSlackAndSalesforceSynchronous() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new GatewayMock());

        Test.startTest();
        // 1. Initial message without existing thread
        String initialThreadTs = SlackBotAgentController.syncChatToSlackAndSalesforce(
            acc.Id,
            acc.Name,
            'Test User',
            'Initial Inquiry',
            'Initial Response',
            null
        );

        // 2. Follow-up message under the same thread
        String followUpThreadTs = SlackBotAgentController.syncChatToSlackAndSalesforce(
            acc.Id,
            acc.Name,
            'Test User',
            'Follow-up message',
            'Follow-up response',
            initialThreadTs
        );
        Test.stopTest();

        Assert.areEqual('1725360000.123', initialThreadTs, 'Initial message should return ts from Slack mock');
        Assert.areEqual(initialThreadTs, followUpThreadTs, 'Follow-up message should preserve the same thread ts');

        List<Task> tasks = [SELECT Id, Subject, Description FROM Task WHERE WhatId = :acc.Id];
        Assert.areEqual(0, tasks.size(), 'Chat messages should not create tasks on the account');
    }

    @IsTest
    static void testGetChatThreads() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Task t = new Task(
            WhatId = acc.Id,
            OwnerId = UserInfo.getUserId(),
            Subject = 'Slack Bot Agent: What is our pipeline?',
            Description = '👤 User Inquiry:\nWhat is our pipeline?\n\n🤖 Slack Bot Agent Response:\nYour pipeline is strong at $1.2M.\n\n💬 Slack Conversation:\nhttps://slack.com/archives/D0BUQS5V68Z/p1725399999888?thread_ts=1725399999.888&cid=D0BUQS5V68Z',
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today()
        );
        insert t;

        Test.startTest();
        List<SlackBotAgentController.ThreadSummaryDTO> threads = SlackBotAgentController.getChatThreads(acc.Id);
        List<SlackBotAgentController.ThreadSummaryDTO> userThreads = SlackBotAgentController.getChatThreads(null);
        Test.stopTest();

        Assert.isFalse(threads.isEmpty(), 'Threads should be retrieved for Account');
        Assert.areEqual('1725399999.888', threads[0].threadTs, 'ThreadTs should be parsed');
        Assert.isTrue(threads[0].title.contains('What is our pipeline'), 'Title should reflect inquiry');
        Assert.isTrue(threads[0].slackUrl.contains('/archives/D0BUQS5V68Z/p1725399999888'), 'Should generate direct Slack archive link');
        Assert.isNotNull(userThreads, 'User threads query should not error');
    }

    @IsTest
    static void testGetThreadMessagesFallback() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Task t = new Task(
            WhatId = acc.Id,
            OwnerId = UserInfo.getUserId(),
            Subject = 'Slack Bot Agent: Account Brief',
            Description = '👤 User Inquiry:\n/account-brief Edge\n\n🤖 Slack Bot Agent Response:\nHere is the dossier for Edge.\n\n💬 Slack Conversation:\nhttps://slack.com/archives/D0BUQS5V68Z/p1725399999888?thread_ts=1725399999.888&cid=D0BUQS5V68Z',
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today()
        );
        insert t;

        Test.startTest();
        List<SlackBotAgentController.ThreadMessageDTO> msgs = SlackBotAgentController.getThreadMessages('1725399999.888', acc.Id);
        List<SlackBotAgentController.ThreadMessageDTO> emptyMsgs = SlackBotAgentController.getThreadMessages('', acc.Id);
        Test.stopTest();

        Assert.isTrue(msgs.size() >= 2, 'Should return both user and bot messages');
        Assert.isTrue(msgs[0].isUser, 'First turn should be user');
        Assert.areEqual('/account-brief Edge', msgs[0].text, 'User inquiry should match');
        Assert.isFalse(msgs[1].isUser, 'Second turn should be bot');
        Assert.isTrue(msgs[1].slackThreadUrl.contains('/archives/D0BUQS5V68Z/p1725399999888'), 'Bot message should include direct archive link');
        Assert.isTrue(emptyMsgs.isEmpty(), 'Empty threadTs should return empty list');
    }

    @IsTest
    static void testUserCentricThreadIsolation() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        // 1. Insert task for current running user (User A)
        Task tCurrent = new Task(
            WhatId = acc.Id,
            OwnerId = UserInfo.getUserId(),
            Subject = 'Slack Bot Agent: User A inquiry',
            Description = '👤 User Inquiry:\nUser A Question\n\n🤖 Slack Bot Agent Response:\nUser A Answer\n\n💬 Slack Conversation:\nhttps://slack.com/archives/D0BUQS5V68Z/p1725111111000?thread_ts=1725111111.000&cid=D0BUQS5V68Z',
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today()
        );
        insert tCurrent;

        // 2. Create secondary test user (User B)
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User userB = new User(
            Alias = 'usrB',
            Email = 'userB@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestingUserB',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'userb_learndc_' + Crypto.getRandomInteger() + '@testorg.com'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert userB;
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Slack_Bot_Agent_User' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = userB.Id, PermissionSetId = ps.Id);
        }

        System.runAs(userB) {
            // User B on the same account should see 0 threads because User A's threads are isolated
            List<SlackBotAgentController.ThreadSummaryDTO> userBThreads = SlackBotAgentController.getChatThreads(acc.Id);
            Assert.areEqual(0, userBThreads.size(), 'User B should not see User A threads on the same account');

            // User B's thread messages fallback should also be isolated
            List<SlackBotAgentController.ThreadMessageDTO> userBMsgs = SlackBotAgentController.getThreadMessages('1725111111.000', acc.Id);
            Assert.areEqual(0, userBMsgs.size(), 'User B should not see User A thread messages');
        }

        // 3. User A should see their own thread
        List<SlackBotAgentController.ThreadSummaryDTO> userAThreads = SlackBotAgentController.getChatThreads(acc.Id);
        Assert.isTrue(userAThreads.size() >= 1, 'User A should see their own thread');
    }

    @IsTest
    static void testBuildSlackThreadUrl() {
        String validTs = '1788513404.400199';
        String url = SlackBotAgentController.buildSlackThreadUrl(validTs);
        Assert.areEqual(
            'https://slack.com/archives/D0BUQS5V68Z/p1788513404400199?thread_ts=1788513404.400199&cid=D0BUQS5V68Z',
            url,
            'Should format direct thread archive permalink'
        );

        String nullUrl = SlackBotAgentController.buildSlackThreadUrl(null);
        Assert.areEqual('https://slack.com/app_redirect?channel=D0BUQS5V68Z', nullUrl, 'Null ts should fallback to channel redirect');

        String taskFallbackUrl = SlackBotAgentController.buildSlackThreadUrl('00Tfj0000012345AAA');
        Assert.areEqual('https://slack.com/app_redirect?channel=D0BUQS5V68Z', taskFallbackUrl, 'Task ID should fallback to channel redirect');
    }

    @IsTest
    static void testParsingHelpers() {
        String sampleDescNew = '👤 User Inquiry:\nHello Bot\n\n🤖 Slack Bot Agent Response:\nHello Human!\n\n💬 Slack Conversation:\nhttps://slack.com/archives/D0BUQS5V68Z/p1725111111222?thread_ts=1725111111.222&cid=D0BUQS5V68Z';
        String sampleDescOld = '👤 User Inquiry:\nHello Bot Old\n\n🤖 Slack Bot Agent Response:\nHello Human Old!\n\n💬 Slack Conversation:\nhttps://slack.com/app_redirect?channel=D0BUQS5V68Z&message_ts=1725111111.333';

        String tsNew = SlackBotAgentController.extractThreadTsFromDescription(sampleDescNew);
        String tsOld = SlackBotAgentController.extractThreadTsFromDescription(sampleDescOld);
        String userInq = SlackBotAgentController.extractUserInquiry(sampleDescNew);
        String botResp = SlackBotAgentController.extractBotResponse(sampleDescNew);

        Assert.areEqual('1725111111.222', tsNew, 'Should extract thread_ts');
        Assert.areEqual('1725111111.333', tsOld, 'Should extract message_ts');
        Assert.areEqual('Hello Bot', userInq, 'Should extract user inquiry');
        Assert.areEqual('Hello Human!', botResp, 'Should extract bot response');

        // Slack message parser test
        String rawUserSlack = ':bust_in_silhouette: *User* (via Salesforce LWC) on *Acc*:\n> What is up?';
        SlackBotAgentController.ThreadMessageDTO userDto = SlackBotAgentController.parseSlackMessage(rawUserSlack, '1725111111.222', '1725111111.222');
        Assert.isTrue(userDto.isUser, 'Should be parsed as user');
        Assert.areEqual('What is up?', userDto.text, 'Should strip Slack quote prefix');

        String rawBotSlack = ':robot_face: *Slack Bot Agent (Gemini 3.6 Flash):*\nAll systems nominal.';
        SlackBotAgentController.ThreadMessageDTO botDto = SlackBotAgentController.parseSlackMessage(rawBotSlack, '1725111112.333', '1725111111.222');
        Assert.isFalse(botDto.isUser, 'Should be parsed as bot');
        Assert.areEqual('All systems nominal.', botDto.text, 'Should strip Slack bot header');
        Assert.isTrue(botDto.slackThreadUrl.contains('/archives/D0BUQS5V68Z/p1725111111222'), 'Bot dto should contain direct archive url');
    }

    @IsTest
    static void testRenameThread() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Task t = new Task(
            WhatId = acc.Id,
            OwnerId = UserInfo.getUserId(),
            Subject = 'Slack Bot Agent: Initial Topic',
            Description = '👤 User Inquiry:\nInitial Topic\n\n🤖 Slack Bot Agent Response:\nAnswer\n\n💬 Slack Conversation:\nhttps://slack.com/archives/D0BUQS5V68Z/p1725888888000?thread_ts=1725888888.000&cid=D0BUQS5V68Z',
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today()
        );
        insert t;

        Test.startTest();
        Map<String, Object> renameRes = SlackBotAgentController.renameThread('1725888888.000', acc.Id, 'Q3 Pipeline Review');
        Map<String, Object> errRes = SlackBotAgentController.renameThread('', acc.Id, 'Title');
        Test.stopTest();

        Assert.areEqual(true, renameRes.get('isSuccess'), 'Rename should succeed');
        Assert.areEqual('Q3 Pipeline Review', renameRes.get('newTitle'), 'New title should match');
        Assert.areEqual(false, errRes.get('isSuccess'), 'Blank threadTs should fail');

        // Verify that getChatThreads reflects the renamed title
        List<SlackBotAgentController.ThreadSummaryDTO> threads = SlackBotAgentController.getChatThreads(acc.Id);
        Boolean foundRenamed = false;
        for (SlackBotAgentController.ThreadSummaryDTO th : threads) {
            if (th.threadTs == '1725888888.000') {
                Assert.areEqual('Q3 Pipeline Review', th.title, 'Thread summary should reflect custom renamed title');
                foundRenamed = true;
            }
        }
        Assert.isTrue(foundRenamed, 'Should find renamed thread in getChatThreads');
    }

    @IsTest
    static void testTogglePinThread() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Task t = new Task(
            WhatId = acc.Id,
            OwnerId = UserInfo.getUserId(),
            Subject = 'Slack Bot Agent: Thread to Pin',
            Description = '👤 User Inquiry:\nPin Me\n\n🤖 Slack Bot Agent Response:\nPinned Answer\n\n💬 Slack Conversation:\nhttps://slack.com/archives/D0BUQS5V68Z/p1725777777000?thread_ts=1725777777.000&cid=D0BUQS5V68Z',
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today()
        );
        insert t;

        Test.startTest();
        // 1. Pin
        Map<String, Object> pinRes = SlackBotAgentController.togglePinThread('1725777777.000', acc.Id, true);
        Assert.areEqual(true, pinRes.get('isSuccess'), 'Pin should succeed');
        Assert.areEqual(true, pinRes.get('isPinned'), 'Should return isPinned true');

        List<SlackBotAgentController.ThreadSummaryDTO> threadsPinned = SlackBotAgentController.getChatThreads(acc.Id);
        for (SlackBotAgentController.ThreadSummaryDTO th : threadsPinned) {
            if (th.threadTs == '1725777777.000') {
                Assert.isTrue(th.isPinned, 'Thread should be marked as pinned');
            }
        }

        // 2. Unpin
        Map<String, Object> unpinRes = SlackBotAgentController.togglePinThread('1725777777.000', acc.Id, false);
        Assert.areEqual(true, unpinRes.get('isSuccess'), 'Unpin should succeed');
        Assert.areEqual(false, unpinRes.get('isPinned'), 'Should return isPinned false');

        // 3. Error case
        Map<String, Object> errRes = SlackBotAgentController.togglePinThread('', acc.Id, true);
        Assert.areEqual(false, errRes.get('isSuccess'), 'Blank threadTs should fail');
        Test.stopTest();
    }

    @IsTest
    static void testDateGroupingAndHelpers() {
        Datetime nowDt = Datetime.now();
        Assert.areEqual('Today', SlackBotAgentController.calculateDateGroup(nowDt), 'Now should be Today');
        Assert.areEqual('Yesterday', SlackBotAgentController.calculateDateGroup(nowDt.addDays(-1)), 'Yesterday group');
        Assert.areEqual('Previous 7 Days', SlackBotAgentController.calculateDateGroup(nowDt.addDays(-4)), '7 days group');
        Assert.areEqual('Previous 30 Days', SlackBotAgentController.calculateDateGroup(nowDt.addDays(-15)), '30 days group');
        Assert.areEqual('Older', SlackBotAgentController.calculateDateGroup(nowDt.addDays(-45)), 'Older group');
        Assert.areEqual('Older', SlackBotAgentController.calculateDateGroup(null), 'Null dt should be Older');

        // Custom Title Helpers
        String descWithTitle = SlackBotAgentController.updateCustomTitleInDescription('Sample body', 'New Title');
        Assert.areEqual('New Title', SlackBotAgentController.extractCustomTitle(descWithTitle), 'Should extract custom title');
        String replacedTitle = SlackBotAgentController.updateCustomTitleInDescription(descWithTitle, 'Replaced Title');
        Assert.areEqual('Replaced Title', SlackBotAgentController.extractCustomTitle(replacedTitle), 'Should replace title');

        // Pinned Helpers
        String pinnedDesc = SlackBotAgentController.updatePinnedStatusInDescription('Sample body', true);
        Assert.isTrue(SlackBotAgentController.extractIsPinned(pinnedDesc), 'Should be pinned');
        String unpinnedDesc = SlackBotAgentController.updatePinnedStatusInDescription(pinnedDesc, false);
        Assert.isFalse(SlackBotAgentController.extractIsPinned(unpinnedDesc), 'Should be unpinned');
    }

    @IsTest
    static void testTaskCreationPromptAndExecution() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Test.startTest();
        // 1. Without specific details -> Agent asks for details without creating task
        SlackBotAgentController.ChatResponseDTO promptRes = SlackBotAgentController.sendMessage(
            'session-task-prompt',
            'Can you create a new task for this account?',
            acc.Id
        );
        Assert.isTrue(promptRes.isSuccess, 'Should succeed');
        Assert.isTrue(promptRes.messageText.contains('Create New Task'), 'Should ask for details');
        Assert.isTrue(promptRes.messageText.contains('Task Subject'), 'Should prompt for Subject');

        List<Task> tasksBefore = [SELECT Id FROM Task WHERE WhatId = :acc.Id AND Subject = 'Review SLA Agreement'];
        Assert.areEqual(0, tasksBefore.size(), 'Should not have created task yet');

        // 2. With specific details -> Agent creates the Task in Salesforce
        SlackBotAgentController.ChatResponseDTO execRes = SlackBotAgentController.sendMessage(
            'session-task-exec',
            'Subject: Review SLA Agreement, Due: tomorrow, Priority: High, Description: Client requested revision',
            acc.Id
        );
        Assert.isTrue(execRes.isSuccess, 'Should succeed');
        Assert.isTrue(execRes.messageText.contains('Task Successfully Created'), 'Should confirm task creation');
        Assert.isTrue(execRes.activityTimelineUpdated, 'Activity timeline should be marked as updated');

        List<Task> tasksAfter = [SELECT Id, Subject, Priority, Status FROM Task WHERE WhatId = :acc.Id AND Subject = 'Review SLA Agreement'];
        Assert.areEqual(1, tasksAfter.size(), 'Should have created exactly 1 task');
        Assert.areEqual('High', tasksAfter[0].Priority, 'Priority should be High');
        Assert.areEqual('Not Started', tasksAfter[0].Status, 'Status should be Not Started');
        Test.stopTest();
    }

    @IsTest
    static void testMeetingSchedulingPrompt() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Test.startTest();
        // When general meeting inquiry is made -> Agent asks for date/time/agenda before booking
        SlackBotAgentController.ChatResponseDTO res = SlackBotAgentController.sendMessage(
            'session-meet-prompt',
            'Can you schedule a meeting with this customer?',
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Should succeed');
        Assert.isTrue(res.messageText.contains('Schedule Meeting with'), 'Should prompt for meeting details');
        Assert.isTrue(res.messageText.contains('Date & Time'), 'Should prompt for date and time');
    }

    @IsTest
    static void testEmailGenerationPromptAndExecution() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Gateway' LIMIT 1];

        Test.startTest();
        // 1. Without specific topic -> Agent asks for details
        SlackBotAgentController.ChatResponseDTO promptRes = SlackBotAgentController.sendMessage(
            'session-mail-prompt',
            'Generate an email for this account',
            acc.Id
        );
        Assert.isTrue(promptRes.isSuccess, 'Should succeed');
        Assert.isTrue(promptRes.messageText.contains('Generate Email for'), 'Should prompt for email details');
        Assert.isTrue(promptRes.messageText.contains('Key Points to Cover'), 'Should prompt for key points');

        // 2. With topic and points -> Agent drafts full contextual email
        SlackBotAgentController.ChatResponseDTO draftRes = SlackBotAgentController.sendMessage(
            'session-mail-draft',
            'Draft an email regarding contract renewal and platform optimization with friendly tone',
            acc.Id
        );
        Assert.isTrue(draftRes.isSuccess, 'Should succeed');
        Assert.isTrue(draftRes.messageText.contains('Email Draft Ready for Review'), 'Should provide completed email draft');
        Assert.isTrue(draftRes.messageText.contains('contract renewal'), 'Draft should include topic');
        Test.stopTest();
    }

    @IsTest
    static void testUserIdentityGovernanceMethods() {
        Test.startTest();
        // 1. Get identity context
        SlackUserIdentityService.UserSlackIdentityDTO idCtx = SlackBotAgentController.getSlackIdentityContext();
        Assert.isNotNull(idCtx, 'Identity context should not be null');

        // 2. Direct link
        SlackUserIdentityService.UserSlackIdentityDTO linked = SlackBotAgentController.linkDirectSlackIdentity('D0BUNTVJCQJ');
        Assert.areEqual('D0BUNTVJCQJ', linked.slackDmChannelId, 'Channel should update to linked channel');

        // 3. Disconnect
        Boolean disResult = SlackBotAgentController.disconnectSlackAccount();
        Assert.isTrue(disResult, 'Disconnect should succeed');

        // 4. Re-sync
        SlackUserIdentityService.UserSlackIdentityDTO reSynced = SlackBotAgentController.reSyncSlackIdentity();
        Assert.isNotNull(reSynced, 'Re-synced identity should not be null');
        Test.stopTest();
    }

    @IsTest
    static void testBidirectionalMessageParsingAndUrls() {
        // Test LWC-originated message
        SlackBotAgentController.ThreadMessageDTO lwcMsg = SlackBotAgentController.parseSlackMessage(
            '👤 *Test User* (via Salesforce LWC) on *Acme*:\n> What is the health score?',
            '1725360000.123',
            '1725360000.100'
        );
        Assert.isNotNull(lwcMsg, 'LWC message should parse');
        Assert.isTrue(lwcMsg.isUser, 'Should be recognized as user');
        Assert.areEqual('What is the health score?', lwcMsg.text, 'Text should extract inquiry');

        // Test native Slack user reply (no bot_id, plain text)
        SlackBotAgentController.ThreadMessageDTO slackReply = SlackBotAgentController.parseSlackMessage(
            'Also show me the open tickets.',
            '1725360010.456',
            '1725360000.100'
        );
        Assert.isNotNull(slackReply, 'Slack native reply should parse');
        Assert.isTrue(slackReply.isUser, 'Plain text non-bot message should be recognized as user');
        Assert.areEqual('Also show me the open tickets.', slackReply.text, 'Text should match');

        // Test Bot reply
        SlackBotAgentController.ThreadMessageDTO botMsg = SlackBotAgentController.parseSlackMessage(
            '🤖 *Slack Bot Agent:*\nThere are 2 high priority open tickets.',
            '1725360020.789',
            '1725360000.100',
            'D0BUNTVJCQJ'
        );
        Assert.isNotNull(botMsg, 'Bot reply should parse');
        Assert.isFalse(botMsg.isUser, 'Bot message should not be user');
        Assert.isTrue(botMsg.text.contains('2 high priority open tickets'), 'Text should contain bot response');
        Assert.isTrue(botMsg.slackThreadUrl.contains('D0BUNTVJCQJ'), 'Slack URL should target user channel');

        // Test buildSlackThreadUrl with custom channel
        String threadUrl = SlackBotAgentController.buildSlackThreadUrl('1725360000.100', 'D0BUNTVJCQJ');
        Assert.isTrue(threadUrl.contains('archives/D0BUNTVJCQJ'), 'URL should have user channel');
    }
}
