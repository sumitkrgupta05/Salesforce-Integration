@IsTest
private class LearnDCAccountCopilotControllerTest {

    private class GeminiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"candidates":[{"content":{"parts":[{"text":"Hello! I am your AI Copilot for this account."}]}}]}');
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        Account testAcc = new Account(
            Name = 'Edge Communications Copilot',
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
            Thread_Id__c = 'copilot-thread-123',
            Executive_Summary__c = 'Quarterly customer check-in.',
            Key_Points__c = '• System adoption on track',
            Action_Items__c = '• Schedule follow up meeting',
            Message_Count__c = 2,
            Last_Generated_At__c = DateTime.now()
        );
        insert summary;
    }

    @IsTest
    static void testGetAccountContext() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Copilot' LIMIT 1];

        Test.startTest();
        LearnDCAccountCopilotController.AccountContextDTO ctx = LearnDCAccountCopilotController.getAccountContext(acc.Id);
        LearnDCAccountCopilotController.AccountContextDTO emptyCtx = LearnDCAccountCopilotController.getAccountContext(null);
        Test.stopTest();

        Assert.areEqual(acc.Id, ctx.accountId, 'Account ID should match');
        Assert.areEqual('Edge Communications Copilot', ctx.accountName, 'Name should match');
        Assert.isTrue(ctx.initialGreeting.contains('Edge Communications Copilot'), 'Greeting should mention account');
        Assert.isNotNull(emptyCtx.initialGreeting, 'Empty context greeting should not be null');
    }

    @IsTest
    static void testSendMessageAccountIntent() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Copilot' LIMIT 1];

        Test.startTest();
        LearnDCAccountCopilotController.ChatResponseDTO res = LearnDCAccountCopilotController.sendMessage(
            'session-1', 
            'Who is the CSM on this account?', 
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Should succeed');
        Assert.areEqual('accountCard', res.messageType, 'Should return accountCard');
        Assert.areEqual('Edge Communications Copilot', (String) res.cardData.get('accountName'), 'Account name should match');
    }

    @IsTest
    static void testSendMessageThreadSummaryIntent() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Copilot' LIMIT 1];

        Test.startTest();
        LearnDCAccountCopilotController.ChatResponseDTO res = LearnDCAccountCopilotController.sendMessage(
            'session-1', 
            'Summarize the recent email thread', 
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Should succeed');
        Assert.areEqual('threadSummaryCard', res.messageType, 'Should return threadSummaryCard');
        Assert.areEqual('copilot-thread-123', (String) res.cardData.get('threadId'), 'Thread ID should match');
    }

    @IsTest
    static void testSendMessageWithSpecificThreadId() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Copilot' LIMIT 1];

        Test.startTest();
        LearnDCAccountCopilotController.ChatResponseDTO res = LearnDCAccountCopilotController.sendMessage(
            'session-1', 
            'Summarize email thread id: copilot-thread-123', 
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Should succeed with existing thread');
        Assert.areEqual('copilot-thread-123', (String) res.cardData.get('threadId'), 'Should extract and match threadId');
    }

    @IsTest
    static void testSendMessageThreadIdNotFoundFormalFailure() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Copilot' LIMIT 1];

        Test.startTest();
        LearnDCAccountCopilotController.ChatResponseDTO res = LearnDCAccountCopilotController.sendMessage(
            'session-1', 
            'Summarize thread non-existent-thread-999', 
            acc.Id
        );
        Test.stopTest();

        Assert.isFalse(res.isSuccess, 'Should indicate failure');
        Assert.isTrue(res.messageText.contains('I am unable to complete this request because'), 'Should contain formal failure message');
        Assert.isTrue(res.messageText.contains('non-existent-thread-999'), 'Should mention the failed thread ID');
    }

    @IsTest
    static void testSendMessageMeetingIntent() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Copilot' LIMIT 1];

        Test.startTest();
        LearnDCAccountCopilotController.ChatResponseDTO res = LearnDCAccountCopilotController.sendMessage(
            'session-1', 
            'Schedule a review meeting tomorrow', 
            acc.Id
        );
        Test.stopTest();

        Assert.isNotNull(res, 'Response should not be null');
    }

    @IsTest
    static void testSendMessageGeminiGeneralInquiry() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Edge Communications Copilot' LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new GeminiMock());

        Test.startTest();
        LearnDCAccountCopilotController.ChatResponseDTO res = LearnDCAccountCopilotController.sendMessage(
            'session-1', 
            'What is the recommended strategy for technology companies?', 
            acc.Id
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Should succeed');
        Assert.isTrue(res.messageText.contains('AI Copilot'), 'Should return mocked response');
    }

    @IsTest
    static void testEmptyMessageFormalFailure() {
        Test.startTest();
        LearnDCAccountCopilotController.ChatResponseDTO res = LearnDCAccountCopilotController.sendMessage(
            'session-1', 
            '', 
            null
        );
        Test.stopTest();

        Assert.isFalse(res.isSuccess, 'Empty message should not succeed');
        Assert.isTrue(res.messageText.contains('I am unable to process this request because'), 'Should return formal reason');
    }
}
