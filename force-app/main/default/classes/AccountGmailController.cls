public without sharing class AccountGmailController {
    public class ControllerException extends Exception {}

    public class ThreadSummaryDTO {
        @AuraEnabled public String threadId { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String snippet { get; set; }
        @AuraEnabled public String quickSummary { get; set; }
        @AuraEnabled public String fromAddress { get; set; }
        @AuraEnabled public String toAddress { get; set; }
        @AuraEnabled public String direction { get; set; }
        @AuraEnabled public DateTime latestDate { get; set; }
        @AuraEnabled public Integer messageCount { get; set; }
        @AuraEnabled public Boolean isMultipleMessages { get; set; }
        @AuraEnabled public String messageCountLabel { get; set; }
        @AuraEnabled public Boolean hasAttachments { get; set; }
        @AuraEnabled public String contactName { get; set; }
        @AuraEnabled public String contactId { get; set; }
        @AuraEnabled public String latestEventId { get; set; }
        @AuraEnabled public String lastMessageIdHeader { get; set; }
    }

    public class AccountContactDTO {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String title { get; set; }
    }

    /**
     * @description Gets the Account details and associated Contacts.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAccountContext(Id accountId) {
        if (accountId == null) {
            throw new ControllerException('Account ID is required.');
        }

        Account acc = [
            SELECT Id, Name, CSM_Email__c, Owner.Name, Owner.Email 
            FROM Account 
            WHERE Id = :accountId 
            LIMIT 1
        ];

        List<Contact> contacts = [
            SELECT Id, Name, Email, Title 
            FROM Contact 
            WHERE AccountId = :accountId 
            AND Email != null 
            ORDER BY Name ASC 
            LIMIT 100
        ];

        List<AccountContactDTO> contactList = new List<AccountContactDTO>();
        for (Contact c : contacts) {
            AccountContactDTO dto = new AccountContactDTO();
            dto.id = c.Id;
            dto.name = c.Name;
            dto.email = c.Email;
            dto.title = c.Title;
            contactList.add(dto);
        }

        String effectiveCsmEmail = String.isNotBlank(acc.CSM_Email__c) 
            ? acc.CSM_Email__c 
            : (acc.Owner != null && String.isNotBlank(acc.Owner.Email) ? acc.Owner.Email : UserInfo.getUserEmail());

        return new Map<String, Object>{
            'account' => acc,
            'contacts' => contactList,
            'csmEmail' => effectiveCsmEmail,
            'userEmail' => effectiveCsmEmail,
            'configured' => true
        };
    }

    /**
     * @description Actively returns email thread summaries linked to the Account.
     */
    @AuraEnabled
    public static List<ThreadSummaryDTO> getAccountEmailThreads(Id accountId, String searchKey) {
        if (accountId == null) {
            return new List<ThreadSummaryDTO>();
        }

        // Query all Event records linked to this Account with Gmail thread information
        String query = 'SELECT Id, Subject, WhoId, Who.Name, Description, '
            + 'Gmail_Message_Id__c, Gmail_Thread_Id__c, Gmail_Snippet__c, '
            + 'Gmail_From_Address__c, Gmail_To_Address__c, Gmail_CC_Address__c, '
            + 'Gmail_Direction__c, Gmail_Date__c, Gmail_Has_Attachments__c, CreatedDate '
            + 'FROM Event '
            + 'WHERE WhatId = :accountId '
            + 'AND Gmail_Thread_Id__c != null ';

        if (String.isNotBlank(searchKey)) {
            String term = '%' + String.escapeSingleQuotes(searchKey.trim()) + '%';
            query += 'AND (Subject LIKE :term OR Gmail_Snippet__c LIKE :term OR Gmail_From_Address__c LIKE :term OR Gmail_To_Address__c LIKE :term) ';
        }

        query += 'ORDER BY Gmail_Date__c DESC NULLS LAST, CreatedDate DESC LIMIT 300';

        List<Event> events = Database.query(query);

        // Group by Gmail_Thread_Id__c
        Map<String, List<Event>> threadMap = new Map<String, List<Event>>();
        List<String> threadOrder = new List<String>();

        for (Event ev : events) {
            String thId = ev.Gmail_Thread_Id__c;
            if (!threadMap.containsKey(thId)) {
                threadMap.put(thId, new List<Event>());
                threadOrder.add(thId);
            }
            threadMap.get(thId).add(ev);
        }

        List<ThreadSummaryDTO> results = new List<ThreadSummaryDTO>();
        for (String thId : threadOrder) {
            List<Event> evList = threadMap.get(thId);
            Event latest = evList[0]; // Ordered by date DESC, so index 0 is latest message

            ThreadSummaryDTO dto = new ThreadSummaryDTO();
            dto.threadId = thId;
            dto.latestEventId = latest.Id;
            dto.subject = latest.Subject;
            String cleanSnippet = AccountGmailInboundHandler.stripQuotedReply(latest.Gmail_Snippet__c);
            if (String.isBlank(cleanSnippet)) cleanSnippet = latest.Subject;
            if (cleanSnippet != null && cleanSnippet.length() > 90) cleanSnippet = cleanSnippet.substring(0, 90) + '...';
            dto.snippet = cleanSnippet;
            if (evList.size() > 1) {
                dto.quickSummary = evList.size() + ' msgs • ' + (latest.Gmail_Direction__c == 'INBOUND' ? 'Client replied: ' : 'Our team: ') + '"' + cleanSnippet + '"';
            } else {
                dto.quickSummary = (latest.Gmail_Direction__c == 'INBOUND' ? 'Client: ' : 'Sent: ') + '"' + cleanSnippet + '"';
            }
            dto.fromAddress = latest.Gmail_From_Address__c;
            dto.toAddress = latest.Gmail_To_Address__c;
            dto.direction = latest.Gmail_Direction__c;
            dto.latestDate = latest.Gmail_Date__c != null ? latest.Gmail_Date__c : latest.CreatedDate;
            dto.hasAttachments = latest.Gmail_Has_Attachments__c;
            dto.contactName = latest.Who != null ? latest.Who.Name : '';
            dto.contactId = latest.WhoId != null ? String.valueOf(latest.WhoId) : '';
            dto.messageCount = evList.size();
            dto.isMultipleMessages = (evList.size() > 1);
            dto.messageCountLabel = evList.size() + (evList.size() == 1 ? ' message' : ' messages');

            results.add(dto);
        }

        return results;
    }

    /**
     * @description Syncs emails for an account (Domain-free: Handled via Salesforce Inbound Email Service)
     */
    public static void syncAccountEmails(Id accountId) {
        // Domain-free architecture: Inbound client replies and emails are synced in real-time via Salesforce Inbound Email Service
    }

    /**
     * @description Fetches all messages in a thread from Salesforce Event records in chronological order.
     */
    @AuraEnabled
    public static Map<String, Object> getThreadDetails(String threadId, Id accountId) {
        if (String.isBlank(threadId)) {
            throw new ControllerException('Thread ID is required.');
        }

        // Build thread directly from Salesforce Event records (Domain-Free)
        GmailService.GmailThreadDTO threadDto = buildThreadFromEvents(threadId, accountId);

        // Load or generate summary immediately in the same request for instant UI presentation
        GmailAIService.ThreadSummaryResult summaryRes = null;
        try {
            summaryRes = getOrGenerateThreadSummary(threadId, accountId, false);
        } catch (Exception ex) {
            System.debug('Non-critical summary generation notice: ' + ex.getMessage());
        }

        return new Map<String, Object>{
            'thread' => threadDto,
            'summary' => summaryRes
        };
    }

    /**
     * @description Retrieves the cached AI summary for a thread or generates a new one
     *              if no summary exists, if a new message was added, or if forced.
     */
    @AuraEnabled
    public static GmailAIService.ThreadSummaryResult getOrGenerateThreadSummary(
        String threadId, 
        Id accountId, 
        Boolean forceRefresh
    ) {
        if (String.isBlank(threadId)) {
            throw new ControllerException('Thread ID is required.');
        }

        // Build thread directly from Salesforce Event records (Domain-Free)
        GmailService.GmailThreadDTO threadDto = buildThreadFromEvents(threadId, accountId);

        if (threadDto == null || threadDto.messages == null || threadDto.messages.isEmpty()) {
            GmailAIService.ThreadSummaryResult emptyRes = new GmailAIService.ThreadSummaryResult();
            emptyRes.executiveSummary = 'No messages found in this thread.';
            return emptyRes;
        }

        Integer currentMsgCount = threadDto.messages.size();
        GmailService.GmailMessageDTO latestMsg = threadDto.messages[currentMsgCount - 1];

        // 2. Check for cached summary in Gmail_Thread_Summary__c (safely wrapped)
        if (!forceRefresh) {
            try {
                List<Gmail_Thread_Summary__c> cachedList = [
                    SELECT Id, Thread_Id__c, Account__c, Executive_Summary__c, Key_Points__c, Action_Items__c,
                           Message_Count__c, Latest_Message_Id__c, Latest_Message_Date__c, Last_Generated_At__c, Model_Used__c
                    FROM Gmail_Thread_Summary__c
                    WHERE Thread_Id__c = :threadId
                    LIMIT 1
                ];

                if (!cachedList.isEmpty()) {
                    Gmail_Thread_Summary__c cached = cachedList[0];
                    if (cached.Message_Count__c == currentMsgCount && 
                        (String.isBlank(cached.Latest_Message_Id__c) || cached.Latest_Message_Id__c == latestMsg.id)) {
                        
                        GmailAIService.ThreadSummaryResult res = new GmailAIService.ThreadSummaryResult();
                        res.executiveSummary = cached.Executive_Summary__c;
                        res.wholeThreadSummary = cached.Executive_Summary__c;
                        res.keyPointsRaw = cached.Key_Points__c;
                        res.actionItemsRaw = cached.Action_Items__c;
                        if (String.isNotBlank(cached.Key_Points__c)) {
                            res.keyPoints = cached.Key_Points__c.split('\n');
                        }
                        if (String.isNotBlank(cached.Action_Items__c)) {
                            res.actionItems = cached.Action_Items__c.split('\n');
                        }
                        res.messageCount = Integer.valueOf(cached.Message_Count__c);
                        res.latestMessageId = cached.Latest_Message_Id__c;
                        res.lastGeneratedAt = cached.Last_Generated_At__c;
                        res.modelUsed = cached.Model_Used__c;
                        res.isCached = true;
                        return res;
                    }
                }
            } catch (Exception ex) {
                System.debug('Cache read skipped or unavailable: ' + ex.getMessage());
            }
        }

        // 3. Cache MISS: Generate fresh AI summary using all messages in chronological order
        GmailAIService.ThreadSummaryResult freshResult = GmailAIService.generateSummary(threadId, accountId, threadDto.messages);
        freshResult.isCached = false;

        // 5. Store / Update in database for subsequent lightning-fast loads
        try {
            Gmail_Thread_Summary__c gts = new Gmail_Thread_Summary__c();
            gts.Thread_Id__c = threadId;
            if (accountId != null) {
                gts.Account__c = accountId;
            }
            gts.Executive_Summary__c = freshResult.executiveSummary;
            gts.Key_Points__c = freshResult.keyPointsRaw;
            gts.Action_Items__c = freshResult.actionItemsRaw;
            gts.Message_Count__c = currentMsgCount;
            gts.Latest_Message_Id__c = latestMsg.id;
            gts.Latest_Message_Date__c = latestMsg.dateVal;
            gts.Last_Generated_At__c = DateTime.now();
            gts.Model_Used__c = freshResult.modelUsed;

            upsert gts Thread_Id__c;
        } catch (Exception ex) {
            System.debug('Error caching AI thread summary: ' + ex.getMessage());
        }

        return freshResult;
    }

    /**
     * @description Sends an email communicating with contact record, using CSM Email from Account.
     *              Dispatches via native Salesforce email (with Reply-To = CSM Email) and logs the Event.
     */
    @AuraEnabled
    public static Map<String, Object> sendEmail(
        Id accountId, 
        Id contactId, 
        String toAddress, 
        String ccAddress, 
        String subject, 
        String bodyHtml, 
        String threadId, 
        String inReplyTo
    ) {
        if (accountId == null) {
            throw new ControllerException('Account ID is required.');
        }
        if (String.isBlank(toAddress)) {
            throw new ControllerException('Recipient email address is required.');
        }

        // Retrieve Account & CSM Email
        Account acc = [
            SELECT Id, Name, CSM_Email__c, Owner.Name, Owner.Email 
            FROM Account 
            WHERE Id = :accountId 
            LIMIT 1
        ];

        String effectiveCsmEmail = String.isNotBlank(acc.CSM_Email__c) 
            ? acc.CSM_Email__c 
            : (acc.Owner != null && String.isNotBlank(acc.Owner.Email) ? acc.Owner.Email : UserInfo.getUserEmail());

        String resolvedThreadId = String.isNotBlank(threadId) 
            ? threadId 
            : 'th_' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(DateTime.now().getTime()) + toAddress))).substring(0, 16);
        String resolvedMsgId = 'msg_' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(DateTime.now().getTime()) + subject))).substring(0, 16);

        // Append thread tracking token so customer replies are reliably matched to this thread
        String outboundSubject = subject;
        if (!outboundSubject.contains(resolvedThreadId)) {
            outboundSubject = outboundSubject + ' [' + resolvedThreadId + ']';
        }

        // Route replies to Salesforce Inbound Email Service (csm-reply@...)
        String inboundAddress = getInboundEmailAddress();
        String effectiveReplyTo = String.isNotBlank(inboundAddress) ? inboundAddress : effectiveCsmEmail;

        String senderName = (acc.Owner != null && String.isNotBlank(acc.Owner.Name)) ? acc.Owner.Name : 'Customer Success Team';

        // Auto-resolve contact if not explicitly provided
        Id effectiveContactId = contactId;
        if (effectiveContactId == null && String.isNotBlank(toAddress)) {
            List<Contact> matchedCons = [
                SELECT Id FROM Contact 
                WHERE AccountId = :accountId AND Email = :toAddress 
                LIMIT 1
            ];
            if (!matchedCons.isEmpty()) {
                effectiveContactId = matchedCons[0].Id;
            }
        }

        // Retrieve prior thread events to construct RFC 2822 threading headers and conversation history
        List<Event> priorEvents = [
            SELECT Id, Subject, Description, Gmail_Snippet__c, Gmail_From_Address__c, 
                   Gmail_To_Address__c, Gmail_Direction__c, Gmail_Date__c, Gmail_Message_Id__c, 
                   CreatedDate, Who.Name 
            FROM Event 
            WHERE Gmail_Thread_Id__c = :resolvedThreadId 
            ORDER BY CreatedDate ASC 
            LIMIT 30
        ];

        Map<String, String> threadHeaders = AccountGmailInboundHandler.getThreadHeaders(resolvedThreadId, priorEvents);
        String threadedBody = AccountGmailInboundHandler.buildThreadedBody(resolvedThreadId, bodyHtml, priorEvents);

        // 1. Dispatch via Native Salesforce SingleEmailMessage with zero GCP dependency
        try {
            List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

            // Primary email to Contact recipient
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            List<User> toUsers = [SELECT Id FROM User WHERE Email = :toAddress AND IsActive = true LIMIT 1];
            if (!toUsers.isEmpty()) {
                mail.setTargetObjectId(toUsers[0].Id);
            } else {
                mail.setToAddresses(new List<String>{ toAddress });
                if (effectiveContactId != null) {
                    mail.setTargetObjectId(effectiveContactId);
                    mail.setTreatTargetObjectAsRecipient(true);
                }
            }

            if (String.isNotBlank(ccAddress)) {
                mail.setCcAddresses(new List<String>{ ccAddress });
            }
            mail.setSubject(outboundSubject);
            mail.setHtmlBody(threadedBody);
            mail.setReplyTo(effectiveReplyTo);
            mail.setSenderDisplayName(senderName);

            if (String.isNotBlank(threadHeaders.get('inReplyTo'))) {
                mail.setInReplyTo(threadHeaders.get('inReplyTo'));
                mail.setReferences(threadHeaders.get('references'));
            }

            mail.setWhatId(accountId);
            mail.setSaveAsActivity(false); // We save our custom Event record below
            emailsToSend.add(mail);

            // Copy to CSM's Personal Email so they can track email history with full threading in their personal inbox
            if (String.isNotBlank(effectiveCsmEmail) && !effectiveCsmEmail.equalsIgnoreCase(toAddress)) {
                Messaging.SingleEmailMessage csmMail = new Messaging.SingleEmailMessage();
                List<User> csmUsers = [SELECT Id FROM User WHERE Email = :effectiveCsmEmail AND IsActive = true LIMIT 1];
                if (!csmUsers.isEmpty()) {
                    csmMail.setTargetObjectId(csmUsers[0].Id);
                } else {
                    csmMail.setToAddresses(new List<String>{ effectiveCsmEmail });
                }

                csmMail.setSubject(outboundSubject);
                csmMail.setHtmlBody(threadedBody);
                csmMail.setReplyTo(effectiveReplyTo);
                csmMail.setSenderDisplayName(senderName + ' (via Salesforce)');
                if (String.isNotBlank(threadHeaders.get('inReplyTo'))) {
                    csmMail.setInReplyTo(threadHeaders.get('inReplyTo'));
                    csmMail.setReferences(threadHeaders.get('references'));
                }
                csmMail.setSaveAsActivity(false);
                emailsToSend.add(csmMail);
            }

            Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(emailsToSend, false);
            if (sendResults != null && !sendResults.isEmpty() && !sendResults[0].isSuccess()) {
                String errMsg = sendResults[0].getErrors()[0].getMessage();
                System.debug('SingleEmail dispatch notice: ' + errMsg);
                if (errMsg.contains('NO_MASS_MAIL_PERMISSION') || errMsg.contains('EMAIL_FAILED')) {
                    throw new ControllerException('Email dispatch error: ' + errMsg);
                }
            }
        } catch (ControllerException ce) {
            throw ce;
        } catch (Exception ex) {
            System.debug('Native SingleEmail exception: ' + ex.getMessage());
        }

        GmailService.GmailMessageDTO msgResult = new GmailService.GmailMessageDTO();
        msgResult.id = resolvedMsgId;
        msgResult.threadId = resolvedThreadId;
        msgResult.fromAddress = effectiveCsmEmail;
        msgResult.toAddress = toAddress;
        msgResult.ccAddress = ccAddress;
        msgResult.subject = subject;
        msgResult.bodyHtml = bodyHtml;
        msgResult.snippet = bodyHtml != null ? bodyHtml.replaceAll('<[^>]+>', ' ') : '';
        msgResult.direction = 'OUTBOUND';
        msgResult.dateVal = DateTime.now();

        // 2. Create Event Record in Salesforce
        DateTime nowDt = DateTime.now();
        Event ev = new Event();
        ev.WhatId = accountId;
        if (effectiveContactId != null) {
            ev.WhoId = effectiveContactId;
        }
        ev.Subject = String.isNotBlank(subject) ? subject : '(No Subject)';
        ev.Description = String.isNotBlank(bodyHtml) ? bodyHtml.replaceAll('<[^>]+>', ' ') : '';
        ev.StartDateTime = nowDt;
        ev.EndDateTime = nowDt.addMinutes(30);

        // Custom Gmail Fields
        ev.Gmail_Message_Id__c = resolvedMsgId;
        ev.Gmail_Thread_Id__c = resolvedThreadId;
        ev.Gmail_Snippet__c = bodyHtml != null && bodyHtml.length() > 255 
            ? bodyHtml.replaceAll('<[^>]+>', ' ').substring(0, Math.min(255, bodyHtml.length()))
            : bodyHtml;
        ev.Gmail_From_Address__c = effectiveCsmEmail;
        ev.Gmail_To_Address__c = toAddress != null && toAddress.length() > 255 ? toAddress.substring(0, 255) : toAddress;
        ev.Gmail_CC_Address__c = ccAddress != null && ccAddress.length() > 255 ? ccAddress.substring(0, 255) : ccAddress;
        ev.Gmail_Direction__c = 'OUTBOUND';
        ev.Gmail_Date__c = nowDt;
        ev.Gmail_Has_Attachments__c = false;
        ev.Last_Sync_Source__c = 'SALESFORCE';
        ev.Sync_Status__c = 'Synced';

        insert ev;

        // 3. Publish Platform Event for instant LWC refresh
        EventBus.publish(new Gmail_Sync_Notification__e(
            AccountId__c = accountId,
            ThreadId__c = resolvedThreadId,
            MessageId__c = resolvedMsgId,
            Action__c = 'SENT',
            Timestamp__c = nowDt
        ));

        return new Map<String, Object>{
            'success' => true,
            'eventId' => ev.Id,
            'message' => msgResult,
            'threadId' => resolvedThreadId
        };
    }

    /**
     * @description Reconstructs thread messages from local Salesforce Event records
     *              when Gmail API is offline or for CSM-sent emails.
     */
    public static GmailService.GmailThreadDTO buildThreadFromEvents(String threadId, Id accountId) {
        List<Event> evList = [
            SELECT Id, Subject, Description, StartDateTime, Gmail_Message_Id__c, Gmail_Thread_Id__c,
                   Gmail_Snippet__c, Gmail_From_Address__c, Gmail_To_Address__c, Gmail_CC_Address__c,
                   Gmail_Direction__c, Gmail_Date__c
            FROM Event
            WHERE (WhatId = :accountId OR WhatId = null) AND Gmail_Thread_Id__c = :threadId
            ORDER BY Gmail_Date__c ASC NULLS LAST, CreatedDate ASC
        ];

        GmailService.GmailThreadDTO dto = new GmailService.GmailThreadDTO();
        dto.id = threadId;
        dto.messages = new List<GmailService.GmailMessageDTO>();

        for (Event e : evList) {
            GmailService.GmailMessageDTO m = new GmailService.GmailMessageDTO();
            m.id = e.Gmail_Message_Id__c;
            m.threadId = e.Gmail_Thread_Id__c;
            m.subject = e.Subject;
            String rawDesc = e.Description;
            String cleanText = AccountGmailInboundHandler.stripQuotedReply(rawDesc);
            m.snippet = String.isNotBlank(cleanText) && cleanText.length() > 255 ? cleanText.substring(0, 255) : cleanText;
            m.bodyHtml = '<p>' + (String.isNotBlank(cleanText) ? cleanText.escapeHtml4().replaceAll('\n', '<br/>') : '') + '</p>';
            m.fromAddress = e.Gmail_From_Address__c;
            m.toAddress = e.Gmail_To_Address__c;
            m.ccAddress = e.Gmail_CC_Address__c;
            m.direction = e.Gmail_Direction__c != null ? e.Gmail_Direction__c : 'OUTBOUND';
            m.dateVal = e.Gmail_Date__c != null ? e.Gmail_Date__c : e.StartDateTime;
            dto.messages.add(m);

            if (String.isNotBlank(e.Subject)) dto.subject = e.Subject;
            if (m.dateVal != null) dto.latestDate = m.dateVal;
            if (String.isNotBlank(m.snippet)) dto.snippet = m.snippet;
        }
        dto.messageCount = dto.messages.size();
        return dto;
    }

    /**
     * @description Ingests or simulates an inbound client reply on a thread.
     *              Creates the INBOUND Event, attaches it to the thread, fires Platform Event for real-time LWC empApi refresh.
     */
    @AuraEnabled
    public static Map<String, Object> simulateInboundReply(
        Id accountId, 
        Id contactId, 
        String threadId, 
        String replyText
    ) {
        if (accountId == null) {
            throw new ControllerException('Account ID is required.');
        }
        if (String.isBlank(replyText)) {
            throw new ControllerException('Reply text cannot be empty.');
        }

        // Get Contact & Account details
        Contact con;
        if (contactId != null) {
            con = [SELECT Id, Name, Email, Account.CSM_Email__c FROM Contact WHERE Id = :contactId LIMIT 1];
        } else {
            List<Contact> conList = [SELECT Id, Name, Email, Account.CSM_Email__c FROM Contact WHERE AccountId = :accountId AND Email != null LIMIT 1];
            if (!conList.isEmpty()) con = conList[0];
        }

        String clientEmail = con != null && String.isNotBlank(con.Email) ? con.Email : 'client@example.com';
        String clientName = con != null ? con.Name : 'Client';

        Account acc = [SELECT Id, CSM_Email__c, Owner.Email FROM Account WHERE Id = :accountId LIMIT 1];
        String csmEmail = String.isNotBlank(acc.CSM_Email__c) ? acc.CSM_Email__c : (acc.Owner != null ? acc.Owner.Email : 'csm@company.com');

        // Resolve subject from latest thread event
        String subject = 'Re: Discussion';
        if (String.isNotBlank(threadId)) {
            List<Event> prevEvents = [SELECT Subject FROM Event WHERE Gmail_Thread_Id__c = :threadId ORDER BY CreatedDate DESC LIMIT 1];
            if (!prevEvents.isEmpty() && String.isNotBlank(prevEvents[0].Subject)) {
                subject = prevEvents[0].Subject.startsWith('Re:') ? prevEvents[0].Subject : 'Re: ' + prevEvents[0].Subject;
            }
        }

        Event ev = AccountGmailInboundHandler.processInboundRecord(
            accountId, 
            con != null ? con.Id : null, 
            threadId, 
            clientName + ' <' + clientEmail + '>', 
            csmEmail, 
            subject, 
            replyText
        );

        return new Map<String, Object>{
            'success' => true,
            'eventId' => ev.Id,
            'messageId' => ev.Gmail_Message_Id__c,
            'threadId' => threadId
        };
    }

    /**
     * @description Resolves active Salesforce Inbound Email Service address for AccountGmailInbound.
     */
    public static String getInboundEmailAddress() {
        try {
            List<EmailServicesAddress> addrs = [
                SELECT LocalPart, EmailDomainName 
                FROM EmailServicesAddress 
                WHERE Function.FunctionName = 'AccountGmailInbound' 
                AND IsActive = true 
                LIMIT 1
            ];
            if (!addrs.isEmpty()) {
                return addrs[0].LocalPart + '@' + addrs[0].EmailDomainName;
            }
        } catch (Exception ex) {
            System.debug('Could not resolve inbound email address: ' + ex.getMessage());
        }
        return null;
    }
}
