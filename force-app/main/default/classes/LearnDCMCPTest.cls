@IsTest
private class LearnDCMCPTest {

    @TestSetup
    static void setupTestData() {
        Account testAcc = new Account(
            Name = 'Acme Corp Test',
            Industry = 'Technology',
            CSM_Email__c = 'skgsummo5@gmail.com'
        );
        insert testAcc;

        Contact testContact = new Contact(
            FirstName = 'Alex',
            LastName = 'Hales',
            Email = 'alex.hales@acme.com',
            Title = 'VP of Operations',
            AccountId = testAcc.Id
        );
        insert testContact;

        Gmail_Thread_Summary__c summary = new Gmail_Thread_Summary__c(
            Account__c = testAcc.Id,
            Thread_Id__c = 'thread-12345',
            Executive_Summary__c = 'Quarterly budget alignment discussed.',
            Key_Points__c = '• Renewal expected in Q3\n• Budget approved',
            Action_Items__c = '• Send contract addendum',
            Message_Count__c = 3,
            Last_Generated_At__c = DateTime.now()
        );
        insert summary;
    }

    @IsTest
    static void testGetAccountDetails() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Acme Corp Test' LIMIT 1];

        LearnDCMCPAccountAction.AccountRequest req = new LearnDCMCPAccountAction.AccountRequest();
        req.accountIdentifier = acc.Name;

        Test.startTest();
        List<LearnDCMCPAccountAction.AccountResult> results = LearnDCMCPAccountAction.getAccountDetails(
            new List<LearnDCMCPAccountAction.AccountRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return 1 result');
        Assert.isTrue(results[0].isFound, 'Account should be found');
        Assert.areEqual(acc.Id, results[0].accountId, 'Account ID should match');
        Assert.areEqual('skgsummo5@gmail.com', results[0].csmEmail, 'CSM email should match');
    }

    @IsTest
    static void testGetThreadSummary() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Acme Corp Test' LIMIT 1];

        LearnDCMCPThreadAction.ThreadRequest req = new LearnDCMCPThreadAction.ThreadRequest();
        req.accountIdentifier = acc.Name;
        req.threadId = 'thread-12345';

        Test.startTest();
        List<LearnDCMCPThreadAction.ThreadResult> results = LearnDCMCPThreadAction.getThreadSummary(
            new List<LearnDCMCPThreadAction.ThreadRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return 1 result');
        Assert.isTrue(results[0].isFound, 'Thread summary should be found');
        Assert.areEqual('thread-12345', results[0].threadId, 'Thread ID should match');
    }

    @IsTest
    static void testGetThreadSummaryLatestForAccount() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Acme Corp Test' LIMIT 1];

        LearnDCMCPThreadAction.ThreadRequest req = new LearnDCMCPThreadAction.ThreadRequest();
        req.accountIdentifier = acc.Name;
        req.threadId = null; // Should query latest for account

        Test.startTest();
        List<LearnDCMCPThreadAction.ThreadResult> results = LearnDCMCPThreadAction.getThreadSummary(
            new List<LearnDCMCPThreadAction.ThreadRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return 1 result');
        Assert.isTrue(results[0].isFound, 'Should find latest thread summary');
    }

    @IsTest
    static void testGetThreadSummaryDynamicFallback() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Acme Corp Test' LIMIT 1];

        LearnDCMCPThreadAction.ThreadRequest req = new LearnDCMCPThreadAction.ThreadRequest();
        req.accountIdentifier = acc.Name;
        req.threadId = 'non-existent-thread-abc';

        Test.startTest();
        List<LearnDCMCPThreadAction.ThreadResult> results = LearnDCMCPThreadAction.getThreadSummary(
            new List<LearnDCMCPThreadAction.ThreadRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return 1 result');
    }

    @IsTest
    static void testThreadActionBlankAccount() {
        LearnDCMCPThreadAction.ThreadRequest req = new LearnDCMCPThreadAction.ThreadRequest();
        req.accountIdentifier = '';

        Test.startTest();
        List<LearnDCMCPThreadAction.ThreadResult> results = LearnDCMCPThreadAction.getThreadSummary(
            new List<LearnDCMCPThreadAction.ThreadRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return 1 result');
        Assert.isFalse(results[0].isFound, 'Should not find account');
    }

    @IsTest
    static void testGetThreadSummaryByThreadIdOnly() {
        LearnDCMCPThreadAction.ThreadRequest req = new LearnDCMCPThreadAction.ThreadRequest();
        req.accountIdentifier = null;
        req.threadId = 'thread-12345';

        Test.startTest();
        List<LearnDCMCPThreadAction.ThreadResult> results = LearnDCMCPThreadAction.getThreadSummary(
            new List<LearnDCMCPThreadAction.ThreadRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return 1 result');
        Assert.isTrue(results[0].isFound, 'Thread should be found by threadId only');
        Assert.areEqual('thread-12345', results[0].threadId, 'Thread ID should match');
    }

    @IsTest
    static void testScheduleMeetingValidation() {
        LearnDCMCPMeetingAction.MeetingRequest req = new LearnDCMCPMeetingAction.MeetingRequest();
        req.accountIdentifier = 'Acme Corp Test';
        req.subject = 'Q3 Business Review';
        req.startDateTime = DateTime.now().addDays(1);
        req.durationMinutes = 45;
        req.attendeeEmail = 'alex.hales@acme.com';

        Test.startTest();
        List<LearnDCMCPMeetingAction.MeetingResult> results = LearnDCMCPMeetingAction.scheduleMeeting(
            new List<LearnDCMCPMeetingAction.MeetingRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return 1 result');
    }
}
