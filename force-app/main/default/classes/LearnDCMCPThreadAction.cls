global with sharing class LearnDCMCPThreadAction {

    global class ThreadRequest {
        @InvocableVariable(label='Account Name or ID' description='Optional Account Name or ID to look up email summaries for.')
        global String accountIdentifier;

        @InvocableVariable(label='Thread ID' description='Optional specific Gmail Thread ID.')
        global String threadId;
    }

    global class ThreadResult {
        @InvocableVariable(label='Is Found' description='True if an email thread summary was found.')
        global Boolean isFound;

        @InvocableVariable(label='Thread ID' description='Gmail Thread ID.')
        global String threadId;

        @InvocableVariable(label='Executive Summary' description='High-level summary of customer communications.')
        global String executiveSummary;

        @InvocableVariable(label='Key Discussion Points' description='Key bullet points from the email thread.')
        global String keyPoints;

        @InvocableVariable(label='Action Items' description='Identified action items and next steps.')
        global String actionItems;

        @InvocableVariable(label='Message Count' description='Number of messages analyzed in the thread.')
        global Integer messageCount;

        @InvocableVariable(label='Account Name' description='Associated Account Name.')
        global String accountName;
    }

    @InvocableMethod(
        label='Get Customer Email Thread Summary'
        description='Retrieves the AI-generated executive summary, discussion highlights, and action items for an account email thread.'
    )
    global static List<ThreadResult> getThreadSummary(List<ThreadRequest> requests) {
        List<ThreadResult> results = new List<ThreadResult>();

        for (ThreadRequest req : requests) {
            ThreadResult res = new ThreadResult();
            res.isFound = false;

            // Must have at least Account Identifier OR Thread ID
            if (String.isBlank(req.accountIdentifier) && String.isBlank(req.threadId)) {
                results.add(res);
                continue;
            }

            Account targetAcc;

            // 1. If Account Identifier is provided, locate the Account
            if (String.isNotBlank(req.accountIdentifier)) {
                String searchPattern = '%' + req.accountIdentifier.trim() + '%';
                List<Account> accs = [
                    SELECT Id, Name FROM Account 
                    WHERE Name LIKE :searchPattern OR Id = :req.accountIdentifier.trim()
                    LIMIT 1
                ];
                if (!accs.isEmpty()) {
                    targetAcc = accs[0];
                    res.accountName = targetAcc.Name;
                }
            }

            // 2. If NO Account was provided, look up by Thread ID directly
            if (targetAcc == null && String.isNotBlank(req.threadId)) {
                List<Gmail_Thread_Summary__c> existing = [
                    SELECT Id, Account__c, Account__r.Name, Thread_Id__c, Executive_Summary__c, Key_Points__c, Action_Items__c, Message_Count__c
                    FROM Gmail_Thread_Summary__c
                    WHERE Thread_Id__c = :req.threadId.trim()
                    LIMIT 1
                ];

                if (!existing.isEmpty()) {
                    Gmail_Thread_Summary__c s = existing[0];
                    res.isFound = true;
                    res.threadId = s.Thread_Id__c;
                    res.executiveSummary = s.Executive_Summary__c;
                    res.keyPoints = s.Key_Points__c;
                    res.actionItems = s.Action_Items__c;
                    res.messageCount = s.Message_Count__c != null ? s.Message_Count__c.intValue() : 0;
                    res.accountName = (s.Account__r != null) ? s.Account__r.Name : null;
                    results.add(res);
                    continue;
                }

                // Check Event records with this Gmail_Thread_Id__c to identify the Account
                List<Event> threadEvents = [
                    SELECT Id, WhatId 
                    FROM Event 
                    WHERE Gmail_Thread_Id__c = :req.threadId.trim() AND WhatId != null 
                    LIMIT 1
                ];

                if (!threadEvents.isEmpty()) {
                    Id matchedAccId = threadEvents[0].WhatId;
                    List<Account> matchedAccs = [SELECT Id, Name FROM Account WHERE Id = :matchedAccId LIMIT 1];
                    if (!matchedAccs.isEmpty()) {
                        targetAcc = matchedAccs[0];
                        res.accountName = targetAcc.Name;
                    }
                }
            }

            if (targetAcc == null) {
                results.add(res);
                continue;
            }

            // 3. Look up existing thread summary on this Account
            List<Gmail_Thread_Summary__c> summaries;
            if (String.isNotBlank(req.threadId)) {
                summaries = [
                    SELECT Id, Thread_Id__c, Executive_Summary__c, Key_Points__c, Action_Items__c, Message_Count__c, Last_Generated_At__c
                    FROM Gmail_Thread_Summary__c
                    WHERE Account__c = :targetAcc.Id AND Thread_Id__c = :req.threadId.trim()
                    ORDER BY Last_Generated_At__c DESC NULLS LAST
                    LIMIT 1
                ];
            } else {
                summaries = [
                    SELECT Id, Thread_Id__c, Executive_Summary__c, Key_Points__c, Action_Items__c, Message_Count__c, Last_Generated_At__c
                    FROM Gmail_Thread_Summary__c
                    WHERE Account__c = :targetAcc.Id
                    ORDER BY Last_Generated_At__c DESC NULLS LAST
                    LIMIT 1
                ];
            }

            if (!summaries.isEmpty()) {
                Gmail_Thread_Summary__c s = summaries[0];
                res.isFound = true;
                res.threadId = s.Thread_Id__c;
                res.executiveSummary = s.Executive_Summary__c;
                res.keyPoints = s.Key_Points__c;
                res.actionItems = s.Action_Items__c;
                res.messageCount = s.Message_Count__c != null ? s.Message_Count__c.intValue() : 0;
            } else if (String.isNotBlank(req.threadId)) {
                // Dynamically invoke Gemini AI pipeline to generate fresh thread summary
                try {
                    GmailAIService.ThreadSummaryResult dynamicResult = AccountGmailController.getOrGenerateThreadSummary(req.threadId.trim(), targetAcc.Id, true);
                    if (dynamicResult != null && String.isNotBlank(dynamicResult.executiveSummary) && !dynamicResult.executiveSummary.startsWith('No messages')) {
                        res.isFound = true;
                        res.threadId = req.threadId.trim();
                        res.executiveSummary = dynamicResult.executiveSummary;
                        res.keyPoints = dynamicResult.keyPointsRaw;
                        res.actionItems = dynamicResult.actionItemsRaw;
                        res.messageCount = dynamicResult.messageCount;
                    }
                } catch (Exception ex) {
                    System.debug(LoggingLevel.WARN, 'Dynamic Gemini thread generation in MCP action: ' + ex.getMessage());
                }
            }

            results.add(res);
        }

        return results;
    }
}
