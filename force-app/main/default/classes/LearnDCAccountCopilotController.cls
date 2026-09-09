/**
 * @description Controller for the Account Record Page Gemini Copilot LWC.
 *              Integrates Google AI Studio Gemini intelligence with deployed
 *              Salesforce MCP Invocable Actions (Account, Thread Summary, Calendar Meetings).
 *              Supports dynamic whole-thread summarization via Gemini when threadId is provided
 *              and provides formal failure explanations for any unhandled or error conditions.
 */
public with sharing class LearnDCAccountCopilotController {

    public class AccountContextDTO {
        @AuraEnabled public String accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String csmEmail { get; set; }
        @AuraEnabled public String industry { get; set; }
        @AuraEnabled public String primaryContactName { get; set; }
        @AuraEnabled public String primaryContactEmail { get; set; }
        @AuraEnabled public String initialGreeting { get; set; }
    }

    public class ChatResponseDTO {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String messageText { get; set; }
        @AuraEnabled public String messageType { get; set; } // 'text', 'accountCard', 'threadSummaryCard', 'meetingCard'
        @AuraEnabled public Map<String, Object> cardData { get; set; }
        @AuraEnabled public Boolean activityTimelineUpdated { get; set; }
        @AuraEnabled public String errorMessage { get; set; }

        public ChatResponseDTO() {
            this.isSuccess = true;
            this.messageType = 'text';
            this.cardData = new Map<String, Object>();
            this.activityTimelineUpdated = false;
        }
    }

    /**
     * @description Fetches contextual Account details and initial greeting for the active record.
     */
    @AuraEnabled(cacheable=true)
    public static AccountContextDTO getAccountContext(Id accountId) {
        AccountContextDTO dto = new AccountContextDTO();
        if (accountId == null) {
            dto.initialGreeting = '👋 Hi! I am your Gemini Copilot. Open an Account to begin.';
            return dto;
        }

        List<Account> accs = [
            SELECT Id, Name, CSM_Email__c, Industry, Phone,
                   (SELECT Id, Name, Email, Title FROM Contacts LIMIT 1)
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (!accs.isEmpty()) {
            Account acc = accs[0];
            dto.accountId = acc.Id;
            dto.accountName = acc.Name;
            dto.csmEmail = acc.CSM_Email__c;
            dto.industry = acc.Industry;

            if (acc.Contacts != null && !acc.Contacts.isEmpty()) {
                dto.primaryContactName = acc.Contacts[0].Name;
                dto.primaryContactEmail = acc.Contacts[0].Email;
            }

            dto.initialGreeting = '👋 Hi! I am your AI Copilot for **' + acc.Name + 
                '**, connected to the **LearnDC Agent MCP Server**. Ask me anything about this account or use the quick action chips below.';
        } else {
            dto.initialGreeting = '👋 Hi! I am your Gemini Copilot. How can I assist you with this account?';
        }

        return dto;
    }

    /**
     * @description Processes a user chat message within the context of the active Account record.
     */
    @AuraEnabled
    public static ChatResponseDTO sendMessage(String sessionId, String userMessage, Id accountId) {
        ChatResponseDTO response = new ChatResponseDTO();

        if (String.isBlank(userMessage)) {
            response.isSuccess = false;
            response.messageText = 'I am unable to process this request because no input or query was provided. Please type a message or select a prompt chip.';
            return response;
        }

        String lowerMsg = userMessage.toLowerCase().trim();

        // ---------------------------------------------------------------------
        // 1. Task Creation Intent (Create task, new task, add task, remind me)
        // ---------------------------------------------------------------------
        if (isTaskCreationIntent(lowerMsg)) {
            return handleTaskAction(accountId, userMessage);
        }

        // ---------------------------------------------------------------------
        // 2. Email Generation Intent (Generate email, draft mail, write email)
        // ---------------------------------------------------------------------
        if (isEmailGenerationIntent(lowerMsg)) {
            return handleEmailGenerationAction(accountId, userMessage);
        }

        // ---------------------------------------------------------------------
        // 3. Schedule Meeting Intent (Meeting, schedule, calendar, meet)
        // ---------------------------------------------------------------------
        if (isMeetingSchedulingIntent(lowerMsg)) {
            return handleMeetingAction(accountId, userMessage);
        }

        // ---------------------------------------------------------------------
        // 4. Customer Email Thread Summary (with dynamic Thread ID detection)
        // ---------------------------------------------------------------------
        if (lowerMsg.contains('summar') || lowerMsg.contains('thread') || (lowerMsg.contains('email') && (lowerMsg.contains('action item') || lowerMsg.contains('history')))) {
            String detectedThreadId = extractThreadId(userMessage);
            return executeThreadSummaryAction(accountId, detectedThreadId);
        }

        // ---------------------------------------------------------------------
        // 5. Account & CSM Details
        // ---------------------------------------------------------------------
        if (lowerMsg.contains('csm') || lowerMsg.contains('contact') || lowerMsg.contains('account') || lowerMsg.contains('who') || lowerMsg.contains('detail')) {
            return executeAccountAction(accountId);
        }

        // ---------------------------------------------------------------------
        // 6. General Inquiry / Fallback with Formal Failure handling
        // ---------------------------------------------------------------------
        return executeGeminiCallout(userMessage, accountId);
    }

    /**
     * @description Extracts a thread ID if present in the user query.
     */
    private static String extractThreadId(String message) {
        if (String.isBlank(message)) return null;

        // Pattern 1: explicit label e.g. "thread id: 18f52b618a8039d9" or "threadId 18f52b..."
        Pattern p1 = Pattern.compile('(?i)thread(?:[ _-]?id)?(?:[ :=]+)([a-zA-Z0-9_-]+)');
        Matcher m1 = p1.matcher(message);
        if (m1.find()) {
            return m1.group(1).trim();
        }

        // Pattern 2: word after "thread" e.g. "summarize thread 18f52b618a8039d9"
        Pattern p2 = Pattern.compile('(?i)\\bthread\\s+([a-zA-Z0-9_-]{6,})');
        Matcher m2 = p2.matcher(message);
        if (m2.find()) {
            return m2.group(1).trim();
        }

        // Pattern 3: standalone hex/alphanumeric ID (16+ chars typical of Gmail thread IDs)
        Pattern p3 = Pattern.compile('\\b([0-9a-fA-F]{16,})\\b');
        Matcher m3 = p3.matcher(message);
        if (m3.find()) {
            return m3.group(1).trim();
        }

        return null;
    }

    /**
     * @description Invokes the deployed LearnDCMCPAccountAction for Account data.
     *              Provides formal failure explanation if no data exists.
     */
    private static ChatResponseDTO executeAccountAction(Id accountId) {
        ChatResponseDTO res = new ChatResponseDTO();
        res.messageType = 'accountCard';

        LearnDCMCPAccountAction.AccountRequest req = new LearnDCMCPAccountAction.AccountRequest();
        req.accountIdentifier = String.valueOf(accountId);

        List<LearnDCMCPAccountAction.AccountResult> results = LearnDCMCPAccountAction.getAccountDetails(
            new List<LearnDCMCPAccountAction.AccountRequest>{ req }
        );

        if (!results.isEmpty() && results[0].isFound) {
            LearnDCMCPAccountAction.AccountResult acc = results[0];
            res.messageText = 'Here are the live account and CSM details retrieved from the **LearnDC Agent MCP Server**:';
            res.cardData.put('accountName', acc.accountName);
            res.cardData.put('accountId', acc.accountId);
            res.cardData.put('csmEmail', acc.csmEmail);
            res.cardData.put('industry', acc.industry);
            res.cardData.put('primaryContactName', acc.primaryContactName);
            res.cardData.put('primaryContactEmail', acc.primaryContactEmail);
            res.cardData.put('contactSummary', acc.contactSummary);
        } else {
            res.isSuccess = false;
            res.messageType = 'text';
            res.messageText = 'I am unable to complete this request because no Account details could be located for record ID "' + accountId + '" in Salesforce. Please verify the active account record.';
        }

        return res;
    }

    /**
     * @description Dynamically summarizes customer email thread using Gemini LLM if threadId is provided,
     *              or retrieves the latest thread intelligence from the LearnDC Agent MCP Server.
     *              Provides formal failure explanations if thread is not found.
     */
    private static ChatResponseDTO executeThreadSummaryAction(Id accountId, String threadId) {
        ChatResponseDTO res = new ChatResponseDTO();
        res.messageType = 'threadSummaryCard';

        Account targetAcc;
        if (accountId != null) {
            List<Account> accList = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];
            if (!accList.isEmpty()) {
                targetAcc = accList[0];
            }
        }
        String accName = (targetAcc != null) ? targetAcc.Name : 'Account';

        // ---------------------------------------------------------------------
        // Case A: Specific Thread ID Provided -> Dynamic Gemini LLM Summarization
        // ---------------------------------------------------------------------
        if (String.isNotBlank(threadId)) {
            String cleanThreadId = threadId.trim();

            try {
                // Dynamically build thread messages and invoke Google Gemini AI summarizer
                GmailAIService.ThreadSummaryResult dynamicResult = AccountGmailController.getOrGenerateThreadSummary(cleanThreadId, accountId, true);

                if (dynamicResult != null && String.isNotBlank(dynamicResult.executiveSummary) && !dynamicResult.executiveSummary.startsWith('No messages')) {
                    res.messageText = 'Here is the dynamic AI summary for Thread **' + cleanThreadId + '** generated using Google Gemini (' + (dynamicResult.modelUsed != null ? dynamicResult.modelUsed : 'Gemini LLM') + '):';
                    res.cardData.put('threadId', cleanThreadId);
                    res.cardData.put('accountName', accName);
                    res.cardData.put('executiveSummary', dynamicResult.executiveSummary);
                    res.cardData.put('keyPoints', dynamicResult.keyPointsRaw);
                    res.cardData.put('actionItems', dynamicResult.actionItemsRaw);
                    res.cardData.put('messageCount', dynamicResult.messageCount);
                    return res;
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Dynamic Gemini thread summarization encountered exception: ' + ex.getMessage());
            }

            // Check if thread summary is recorded in Gmail_Thread_Summary__c
            List<Gmail_Thread_Summary__c> specificSummaries = [
                SELECT Id, Thread_Id__c, Executive_Summary__c, Key_Points__c, Action_Items__c, Message_Count__c, Model_Used__c
                FROM Gmail_Thread_Summary__c
                WHERE Thread_Id__c = :cleanThreadId
                LIMIT 1
            ];

            if (!specificSummaries.isEmpty()) {
                Gmail_Thread_Summary__c s = specificSummaries[0];
                res.messageText = 'Here is the customer email intelligence summary for Thread **' + s.Thread_Id__c + '** from the **LearnDC Agent MCP Server**:';
                res.cardData.put('threadId', s.Thread_Id__c);
                res.cardData.put('accountName', accName);
                res.cardData.put('executiveSummary', s.Executive_Summary__c);
                res.cardData.put('keyPoints', s.Key_Points__c);
                res.cardData.put('actionItems', s.Action_Items__c);
                res.cardData.put('messageCount', s.Message_Count__c != null ? s.Message_Count__c.intValue() : 0);
                return res;
            }

            // Formal failure message with exact reason
            res.isSuccess = false;
            res.messageType = 'text';
            res.messageText = 'I am unable to complete this request because no email messages or records were found in Salesforce for Thread ID "' + cleanThreadId + '". Please verify the Thread ID or ensure email synchronization has been completed for this customer.';
            return res;
        }

        // ---------------------------------------------------------------------
        // Case B: No Thread ID Specified -> Return Latest Summarized Thread
        // ---------------------------------------------------------------------
        List<Gmail_Thread_Summary__c> latestSummaries = [
            SELECT Id, Thread_Id__c, Executive_Summary__c, Key_Points__c, Action_Items__c, Message_Count__c, Model_Used__c, Last_Generated_At__c
            FROM Gmail_Thread_Summary__c
            WHERE Account__c = :accountId
            ORDER BY Last_Generated_At__c DESC NULLS LAST
            LIMIT 1
        ];

        if (!latestSummaries.isEmpty()) {
            Gmail_Thread_Summary__c s = latestSummaries[0];
            res.messageText = 'Here is the latest customer email intelligence summary from the **LearnDC Agent MCP Server**:';
            res.cardData.put('threadId', s.Thread_Id__c);
            res.cardData.put('accountName', accName);
            res.cardData.put('executiveSummary', s.Executive_Summary__c);
            res.cardData.put('keyPoints', s.Key_Points__c);
            res.cardData.put('actionItems', s.Action_Items__c);
            res.cardData.put('messageCount', s.Message_Count__c != null ? s.Message_Count__c.intValue() : 0);
            return res;
        }

        // Check if there are Event records with Gmail_Thread_Id__c on this account
        List<Event> recentEvents = [
            SELECT Gmail_Thread_Id__c 
            FROM Event 
            WHERE WhatId = :accountId AND Gmail_Thread_Id__c != null 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];

        if (!recentEvents.isEmpty() && String.isNotBlank(recentEvents[0].Gmail_Thread_Id__c)) {
            return executeThreadSummaryAction(accountId, recentEvents[0].Gmail_Thread_Id__c);
        }

        // Formal failure message with exact reason
        res.isSuccess = false;
        res.messageType = 'text';
        res.messageText = 'I am unable to complete this request because no customer email communications have been synced yet for ' + accName + '. Once customer emails are synced via Gmail Integration, you can provide a Thread ID to generate a dynamic Gemini summary.';
        return res;
    }

    /**
     * @description Invokes the deployed LearnDCMCPMeetingAction to book Google Calendar meetings.
     *              Provides formal failure explanations if booking fails.
     */
    private static ChatResponseDTO executeMeetingAction(Id accountId, String userMessage) {
        ChatResponseDTO res = new ChatResponseDTO();
        res.messageType = 'meetingCard';

        List<Account> accs = [
            SELECT Id, Name, (SELECT Id, Name, Email FROM Contacts LIMIT 1) 
            FROM Account WHERE Id = :accountId LIMIT 1
        ];
        String accName = (!accs.isEmpty()) ? accs[0].Name : 'Account';
        String attendeeEmail = (!accs.isEmpty() && !accs[0].Contacts.isEmpty()) ? accs[0].Contacts[0].Email : null;

        DateTime meetingStart = DateTime.now().addDays(1); // Default tomorrow
        meetingStart = DateTime.newInstance(
            meetingStart.year(), 
            meetingStart.month(), 
            meetingStart.day(), 
            15, 0, 0
        );

        LearnDCMCPMeetingAction.MeetingRequest req = new LearnDCMCPMeetingAction.MeetingRequest();
        req.accountIdentifier = String.valueOf(accountId);
        req.subject = 'Review & Sync with ' + accName;
        req.startDateTime = meetingStart;
        req.durationMinutes = 30;
        req.attendeeEmail = attendeeEmail;
        req.description = 'Scheduled via Account Gemini Copilot (' + userMessage + ')';

        List<LearnDCMCPMeetingAction.MeetingResult> results = LearnDCMCPMeetingAction.scheduleMeeting(
            new List<LearnDCMCPMeetingAction.MeetingRequest>{ req }
        );

        if (!results.isEmpty() && results[0].isSuccess) {
            LearnDCMCPMeetingAction.MeetingResult mr = results[0];
            res.messageText = '✅ Meeting successfully scheduled with automated Google Meet video link!';
            res.cardData.put('subject', req.subject);
            res.cardData.put('eventId', mr.eventId);
            res.cardData.put('googleMeetLink', mr.googleMeetLink);
            res.cardData.put('googleEventId', mr.googleEventId);
            res.cardData.put('startDateTimeFormatted', meetingStart.format('EEE, MMM d, yyyy h:mm a'));
            res.cardData.put('attendeeEmail', attendeeEmail);
            res.activityTimelineUpdated = true;
        } else {
            res.isSuccess = false;
            res.messageType = 'text';
            String errReason = (!results.isEmpty() && String.isNotBlank(results[0].message)) 
                ? results[0].message 
                : 'Salesforce calendar integration encountered an unexpected error.';
            res.messageText = 'I am unable to schedule this meeting because ' + errReason + ' Please verify the attendee email address and try again.';
        }

        return res;
    }

    /**
     * @description Handles Meeting Scheduling requests. Asks for missing specifics (Subject, Date/Time, Attendee, Duration)
     *              or books the meeting via LearnDCMCPMeetingAction when sufficient details are supplied.
     */
    private static ChatResponseDTO handleMeetingAction(Id accountId, String userMessage) {
        ChatResponseDTO res = new ChatResponseDTO();
        String lower = userMessage.toLowerCase().trim();

        List<Account> accs = [
            SELECT Id, Name, (SELECT Id, Name, Email FROM Contacts LIMIT 1) 
            FROM Account WHERE Id = :accountId LIMIT 1
        ];
        String accName = (!accs.isEmpty()) ? accs[0].Name : 'Active Account';
        String primaryContactName = (!accs.isEmpty() && !accs[0].Contacts.isEmpty()) ? accs[0].Contacts[0].Name : 'Customer Contact';
        String primaryContactEmail = (!accs.isEmpty() && !accs[0].Contacts.isEmpty()) ? accs[0].Contacts[0].Email : 'contact@customer.com';

        // Check if user supplied specific scheduling details (date/time, specific time, or explicit parameters)
        Boolean hasSpecificTime = Pattern.compile('(?i)(?:\\b\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)\\b|\\b\\d{4}-\\d{2}-\\d{2}\\b|\\b(?:tomorrow|today|monday|tuesday|wednesday|thursday|friday)\\s+at\\b|time[ :=]+|date[ :=]+)').matcher(userMessage).find();
        Boolean hasExplicitParams = lower.contains('time:') || lower.contains('attendee:') || lower.contains('subject:');

        if (!hasSpecificTime && !hasExplicitParams) {
            // Ask for specific information first without blindly scheduling!
            res.isSuccess = true;
            res.messageType = 'text';
            res.messageText = '📅 **Schedule Meeting with ' + accName + '**\n\n' +
                'I can schedule this meeting on Google Calendar and generate a Google Meet video conference link! To set it up, please provide the following details:\n\n' +
                '• **Meeting Subject / Topic**: What is the meeting agenda? (e.g. *Q3 Business Review & Roadmap*)\n' +
                '• **Date & Time**: When would you like to meet? (e.g. `Tomorrow at 3:00 PM` or `2026-09-15 14:00`)\n' +
                '• **Attendee Email**: Who should receive the invite? *(Suggested Contact: ' + primaryContactName + ' — `' + primaryContactEmail + '`)*\n' +
                '• **Duration**: How long? (`15`, `30`, `45`, or `60` minutes — defaults to `30`)\n\n' +
                '_💡 Tip: You can reply directly with: `Subject: Quarterly Review, Time: Tomorrow at 3 PM, Attendee: ' + primaryContactEmail + ', Duration: 30` and I will book the meeting immediately!_';
            return res;
        }

        // If specific details are provided, proceed with booking
        return executeMeetingAction(accountId, userMessage);
    }

    /**
     * @description Handles Task Creation requests. Asks for missing specifics (Subject, Due Date, Priority, Description)
     *              or executes task insertion when sufficient details are supplied.
     */
    private static ChatResponseDTO handleTaskAction(Id accountId, String userMessage) {
        ChatResponseDTO res = new ChatResponseDTO();
        String lower = userMessage.toLowerCase().trim();

        Account targetAcc;
        if (accountId != null) {
            List<Account> accs = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];
            if (!accs.isEmpty()) targetAcc = accs[0];
        }
        String accName = (targetAcc != null) ? targetAcc.Name : 'Active Account';

        // Extract parameters if present
        String taskSubject = null;
        Date taskDueDate = null;
        String taskPriority = 'Normal';
        String taskDesc = userMessage;

        // 1. Check for explicit or natural subject
        Matcher subjMatcher = Pattern.compile('(?i)(?:subject|title)[ :=]+([^\n,;]+)').matcher(userMessage);
        if (subjMatcher.find()) {
            taskSubject = subjMatcher.group(1).trim();
        } else {
            Matcher naturalSubj = Pattern.compile('(?i)(?:create|add|schedule|set)\\s+(?:a\\s+)?(?:new\\s+)?task\\s+(?:to|for|about|titled|named)\\s+([^\n,;]+)').matcher(userMessage);
            if (naturalSubj.find()) {
                taskSubject = naturalSubj.group(1).trim();
            } else {
                Matcher remindMatcher = Pattern.compile('(?i)remind\\s+(?:me\\s+)?to\\s+([^\n,;]+)').matcher(userMessage);
                if (remindMatcher.find()) {
                    taskSubject = remindMatcher.group(1).trim();
                }
            }
        }

        // 2. Check for explicit or natural due date
        Matcher dueMatcher = Pattern.compile('(?i)(?:due(?: date)?|by)[ :=]+([^\n,;]+)').matcher(userMessage);
        if (dueMatcher.find()) {
            String rawDate = dueMatcher.group(1).trim().toLowerCase();
            if (rawDate.contains('today')) {
                taskDueDate = Date.today();
            } else if (rawDate.contains('tomorrow')) {
                taskDueDate = Date.today().addDays(1);
            } else if (rawDate.contains('next week')) {
                taskDueDate = Date.today().addDays(7);
            } else {
                try {
                    taskDueDate = Date.valueOf(rawDate);
                } catch (Exception e) {
                    taskDueDate = Date.today().addDays(1);
                }
            }
        } else if (lower.contains('tomorrow')) {
            taskDueDate = Date.today().addDays(1);
        } else if (lower.contains('today')) {
            taskDueDate = Date.today();
        } else if (lower.contains('next week')) {
            taskDueDate = Date.today().addDays(7);
        }

        // 3. Check for priority
        Matcher prioMatcher = Pattern.compile('(?i)priority[ :=]+(high|normal|low)').matcher(userMessage);
        if (prioMatcher.find()) {
            taskPriority = prioMatcher.group(1).capitalize();
        } else if (lower.contains('high priority') || lower.contains('urgent')) {
            taskPriority = 'High';
        } else if (lower.contains('low priority')) {
            taskPriority = 'Low';
        }

        // 4. If subject is missing or user just said "create a task", ask for specific information!
        Boolean hasSpecifics = String.isNotBlank(taskSubject) && (taskDueDate != null || lower.contains('priority:') || lower.contains('due:') || lower.contains('subject:'));
        if (!hasSpecifics) {
            res.isSuccess = true;
            res.messageType = 'text';
            res.messageText = '📋 **Create New Task for ' + accName + '**\n\n' +
                'I can help you create and assign a task on this Account in Salesforce! To make sure it is set up accurately, please provide the following details:\n\n' +
                '• **Task Subject / Title**: What needs to be done? (e.g. *Follow up on contract renewal proposal*)\n' +
                '• **Due Date**: When should it be completed? (e.g. `Tomorrow`, `2026-09-15`, `Next Monday`)\n' +
                '• **Priority**: What is the urgency level? (`High`, `Normal`, or `Low` — defaults to `Normal`)\n' +
                '• **Description / Notes**: Any additional context or instructions?\n\n' +
                '_💡 Tip: You can reply directly with: `Subject: Follow up call, Due: Tomorrow, Priority: High, Description: Discuss Q3 telemetry`_';
            return res;
        }

        // 5. If specific details provided, create the Task in Salesforce
        if (taskDueDate == null) {
            taskDueDate = Date.today().addDays(1);
        }
        if (String.isBlank(taskSubject)) {
            taskSubject = 'Follow up with ' + accName;
        }

        try {
            Task newTask = new Task(
                WhatId = accountId,
                OwnerId = UserInfo.getUserId(),
                Subject = taskSubject.abbreviate(80),
                ActivityDate = taskDueDate,
                Priority = taskPriority,
                Status = 'Not Started',
                Description = 'Created via Slack Bot Agent / Gemini Copilot.\n\nContext:\n' + userMessage
            );
            insert newTask;

            res.isSuccess = true;
            res.messageType = 'text';
            res.activityTimelineUpdated = true;
            res.messageText = '✅ **Task Successfully Created in Salesforce!**\n\n' +
                '• **Subject**: ' + newTask.Subject + '\n' +
                '• **Related To**: ' + accName + '\n' +
                '• **Due Date**: ' + String.valueOf(newTask.ActivityDate) + '\n' +
                '• **Priority**: ' + newTask.Priority + '\n' +
                '• **Status**: ' + newTask.Status + '\n' +
                '• **Assigned To**: ' + UserInfo.getName() + '\n\n' +
                'The task has been logged on the Account and is now visible in your Salesforce Activity Timeline.';
        } catch (Exception ex) {
            res.isSuccess = false;
            res.messageText = 'I am unable to create the task because: ' + ex.getMessage();
        }

        return res;
    }

    /**
     * @description Handles Email Generation / Drafting requests. Asks for missing specifics (Recipient, Subject/Topic, Key Points, Tone)
     *              or generates a customized business email draft when sufficient context is supplied.
     */
    private static ChatResponseDTO handleEmailGenerationAction(Id accountId, String userMessage) {
        ChatResponseDTO res = new ChatResponseDTO();
        String lower = userMessage.toLowerCase().trim();

        List<Account> accs = [
            SELECT Id, Name, Health_Score__c, Usage_Hours__c, Churn_Risk__c, SLA__c, Industry,
                   (SELECT Id, Name, Email, Title FROM Contacts LIMIT 1) 
            FROM Account WHERE Id = :accountId LIMIT 1
        ];
        String accName = (!accs.isEmpty()) ? accs[0].Name : 'Active Account';
        String contactName = (!accs.isEmpty() && !accs[0].Contacts.isEmpty()) ? accs[0].Contacts[0].Name : 'Customer Contact';
        String contactEmail = (!accs.isEmpty() && !accs[0].Contacts.isEmpty()) ? accs[0].Contacts[0].Email : 'contact@customer.com';
        Account acc = (!accs.isEmpty()) ? accs[0] : null;

        // Check if user supplied specific context or topic
        Boolean hasSpecificTopic = Pattern.compile('(?i)(?:about|topic|regarding|subject|points|covering|draft a mail about|write an email about|discussing)[ :=]+([^\n]+)').matcher(userMessage).find();
        Boolean hasExplicitParams = lower.contains('topic:') || lower.contains('points:') || lower.contains('tone:') || lower.contains('subject:');
        Boolean hasSufficientLength = userMessage.length() > 50 && (lower.contains('about') || lower.contains('regarding'));

        if (!hasSpecificTopic && !hasExplicitParams && !hasSufficientLength) {
            // Ask for specific information first!
            res.isSuccess = true;
            res.messageType = 'text';
            res.messageText = '✉️ **Generate Email for ' + accName + '**\n\n' +
                'I can draft a tailored, professional email for this account! To make it relevant and compelling, please specify:\n\n' +
                '• **Recipient**: Who should receive this email? *(Suggested: ' + contactName + ' <' + contactEmail + '>)*\n' +
                '• **Subject / Topic**: What is the email subject or purpose? (e.g. *Check-in on Snowflake usage*, *Contract renewal update*, *Quarterly sync follow-up*)\n' +
                '• **Key Points to Cover**: Any specific points, metrics, or action items you would like included?\n' +
                '• **Tone**: What tone should be used? (`Professional`, `Friendly`, `Urgent`, or `Executive` — defaults to `Professional & Collaborative`)\n\n' +
                '_💡 Tip: You can reply directly with: `Topic: Snowflake usage check-in, Points: review compute usage and offer optimization review, Tone: Friendly` and I will generate the complete ready-to-send draft!_';
            return res;
        }

        // Parse supplied details
        String topic = 'Account Check-in & Review';
        Matcher topicMatcher = Pattern.compile('(?i)(?:about|topic|regarding|subject)[ :=]+([^\n,;]+)').matcher(userMessage);
        if (topicMatcher.find()) {
            topic = topicMatcher.group(1).trim();
        }

        String recipient = contactName + ' <' + contactEmail + '>';
        Matcher recipMatcher = Pattern.compile('(?i)(?:to|recipient)[ :=]+([^\n,;]+)').matcher(userMessage);
        if (recipMatcher.find()) {
            recipient = recipMatcher.group(1).trim();
        }

        String userName = UserInfo.getName();
        String healthInfo = (acc != null && acc.Health_Score__c != null) 
            ? 'Your current account health score is **' + acc.Health_Score__c + '/100**, and platform compute usage is tracking steadily at **' + (acc.Usage_Hours__c != null ? String.valueOf(acc.Usage_Hours__c) : 'optimal') + ' hours**.'
            : 'We have been reviewing your recent platform usage and milestones, and everything is progressing smoothly.';

        res.isSuccess = true;
        res.messageType = 'text';
        res.messageText = '✉️ **Email Draft Ready for Review**\n\n' +
            '**To**: ' + recipient + '\n' +
            '**Subject**: ' + accName + ' — ' + topic + '\n\n' +
            '---\n\n' +
            'Hi ' + contactName.split(' ')[0] + ',\n\n' +
            'I hope this note finds you well!\n\n' +
            'I am reaching out regarding **' + topic + '** for **' + accName + '**. ' + healthInfo + '\n\n' +
            'Here are a few quick items I wanted to highlight:\n' +
            '• Our team is continuously monitoring your operational telemetry to ensure high reliability and SLA performance.\n' +
            '• We would love to partner with you to discuss upcoming milestones and optimize your workflows.\n' +
            '• If you have any open questions or feedback, we are here to support your team every step of the way.\n\n' +
            'Would you be open to a quick 15-minute sync later this week to connect on this? Please let me know what day and time works best for your schedule.\n\n' +
            'Best regards,\n\n' +
            '**' + userName + '**\n' +
            'Customer Success Manager | ' + accName;

        return res;
    }

    private static Boolean isTaskCreationIntent(String lowerMsg) {
        if (lowerMsg.contains('create') && (lowerMsg.contains('task') || lowerMsg.contains('todo') || lowerMsg.contains('to-do'))) return true;
        if (lowerMsg.contains('new task') || lowerMsg.contains('add task') || lowerMsg.contains('assign task') || lowerMsg.contains('schedule task')) return true;
        if (lowerMsg.contains('remind me to') || lowerMsg.startsWith('task:')) return true;
        if (lowerMsg.contains('subject:') && (lowerMsg.contains('due') || lowerMsg.contains('priority') || lowerMsg.contains('task'))) return true;
        return false;
    }

    private static Boolean isEmailGenerationIntent(String lowerMsg) {
        if ((lowerMsg.contains('generate') || lowerMsg.contains('draft') || lowerMsg.contains('write') || 
             lowerMsg.contains('compose') || lowerMsg.contains('send') || lowerMsg.contains('create')) && 
            (lowerMsg.contains('email') || lowerMsg.contains('mail'))) {
            return true;
        }
        if (lowerMsg.startsWith('email:') || lowerMsg.startsWith('mail:')) return true;
        return false;
    }

    private static Boolean isMeetingSchedulingIntent(String lowerMsg) {
        if (lowerMsg.contains('meeting') || lowerMsg.contains('schedule') || lowerMsg.contains('calendar') || 
            lowerMsg.contains('book a call') || lowerMsg.contains('set up a meet') || 
            (lowerMsg.contains('meet') && !lowerMsg.contains('google meet link'))) {
            return true;
        }
        return false;
    }

    /**
     * @description Makes a callout to Google AI Studio Gemini for general conversational questions.
     *              Provides formal failure explanations if unhandled or rate-limited.
     */
    private static ChatResponseDTO executeGeminiCallout(String userMessage, Id accountId) {
        ChatResponseDTO res = new ChatResponseDTO();

        String apiKey = resolveGeminiApiKey();
        if (String.isBlank(apiKey)) {
            res.isSuccess = false;
            res.messageText = 'I am unable to complete this task because Google Gemini API key is not configured in Salesforce. You can still use the quick action chips above to view Account & CSM details, summarize email threads, or schedule meetings directly via the LearnDC Agent MCP Server.';
            return res;
        }

        try {
            List<Account> accs = [
                SELECT Id, Name, CSM_Email__c, Industry 
                FROM Account WHERE Id = :accountId LIMIT 1
            ];
            String accContext = (!accs.isEmpty()) ? 
                'User is currently viewing Account: "' + accs[0].Name + '" (ID: ' + accs[0].Id + ', CSM: ' + accs[0].CSM_Email__c + ', Industry: ' + accs[0].Industry + '). ' : '';

            String endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=' + apiKey;

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(endpoint);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setTimeout(25000);

            Map<String, Object> partMap = new Map<String, Object>{ 'text' => accContext + '\nUser asks: ' + userMessage };
            Map<String, Object> contentMap = new Map<String, Object>{ 'parts' => new List<Object>{ partMap } };
            Map<String, Object> bodyMap = new Map<String, Object>{ 'contents' => new List<Object>{ contentMap } };

            httpReq.setBody(JSON.serialize(bodyMap));

            Http http = new Http();
            HttpResponse httpRes = http.send(httpReq);

            if (httpRes.getStatusCode() == 200) {
                Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
                List<Object> candidates = (List<Object>) root.get('candidates');
                if (candidates != null && !candidates.isEmpty()) {
                    Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];
                    Map<String, Object> contentObj = (Map<String, Object>) firstCandidate.get('content');
                    List<Object> parts = (List<Object>) contentObj.get('parts');
                    if (parts != null && !parts.isEmpty()) {
                        Map<String, Object> firstPart = (Map<String, Object>) parts[0];
                        res.messageText = (String) firstPart.get('text');
                        return res;
                    }
                }
            } else if (httpRes.getStatusCode() == 429) {
                res.isSuccess = false;
                res.messageText = 'I am unable to complete this request right now because Google AI Studio returned a temporary rate limit (HTTP 429). Please wait a few seconds and try again, or use the quick action chips above.';
                return res;
            } else {
                res.isSuccess = false;
                res.messageText = 'I am unable to complete this request because the external AI service returned an error (HTTP ' + httpRes.getStatusCode() + '). Please try again shortly.';
                return res;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Gemini callout failed: ' + ex.getMessage());
            res.isSuccess = false;
            res.messageText = 'I am unable to complete this request because an unexpected network error occurred: ' + ex.getMessage() + '. Please try again or use the quick action chips above.';
            return res;
        }

        // Formal response if query falls outside supported enterprise scope
        res.isSuccess = false;
        res.messageText = 'I am unable to complete this task because it falls outside my supported enterprise capabilities. I can assist you with retrieving Salesforce Account details, dynamically summarizing customer email threads with Gemini, and scheduling review meetings with Google Meet.';
        return res;
    }

    /**
     * @description Resolves Gemini API key from Google_Calendar_Setting__mdt or default fallback.
     */
    private static String resolveGeminiApiKey() {
        try {
            List<Google_Calendar_Setting__mdt> settings = [
                SELECT Gemini_API_Key__c 
                FROM Google_Calendar_Setting__mdt 
                WHERE DeveloperName = 'Default_Setting' 
                LIMIT 1
            ];
            if (!settings.isEmpty() && String.isNotBlank(settings[0].Gemini_API_Key__c)) {
                return settings[0].Gemini_API_Key__c;
            }
        } catch (Exception ex) {
            // Setting not available
        }
        return 'YOUR_GEMINI_API_KEY';
    }
}
