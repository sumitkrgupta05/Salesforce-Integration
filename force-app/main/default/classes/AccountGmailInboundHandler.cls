/**
 * @description Inbound Email Service Handler that receives client email replies,
 *              matches the Contact & Account, logs the INBOUND Event, updates the conversation
 *              stream in real-time via Platform Events, and forwards a copy to the CSM.
 */
global without sharing class AccountGmailInboundHandler implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email, 
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        try {
            String fromAddress = email.fromAddress;
            String cleanFrom = extractEmail(fromAddress);
            String subject = email.subject != null ? email.subject : '(No Subject)';
            String bodyText = String.isNotBlank(email.plainTextBody) 
                ? email.plainTextBody 
                : (String.isNotBlank(email.htmlBody) ? email.htmlBody.replaceAll('<[^>]+>', ' ') : '');
            bodyText = stripQuotedReply(bodyText);
            String toAddress = (email.toAddresses != null && !email.toAddresses.isEmpty()) ? email.toAddresses[0] : '';

            // 1. Resolve Thread ID from Subject or Body
            String resolvedThreadId = extractThreadId(subject);
            if (String.isBlank(resolvedThreadId)) {
                resolvedThreadId = extractThreadId(bodyText);
            }

            Contact matchedContact = null;
            Id accountId = null;

            // 2. Try resolving Account & Contact via Thread ID from existing Events
            if (String.isNotBlank(resolvedThreadId)) {
                List<Event> threadEvents = [
                    SELECT WhatId, WhoId 
                    FROM Event 
                    WHERE Gmail_Thread_Id__c = :resolvedThreadId 
                    ORDER BY CreatedDate DESC 
                    LIMIT 1
                ];
                if (!threadEvents.isEmpty()) {
                    accountId = threadEvents[0].WhatId;
                    if (threadEvents[0].WhoId != null) {
                        List<Contact> conList = [
                            SELECT Id, Name, Email, AccountId 
                            FROM Contact 
                            WHERE Id = :threadEvents[0].WhoId 
                            LIMIT 1
                        ];
                        if (!conList.isEmpty()) {
                            matchedContact = conList[0];
                        }
                    }
                }
            }

            // 3. If Account not resolved from Thread ID, match Contact by sender email
            if (accountId == null) {
                List<Contact> contacts = [
                    SELECT Id, Name, Email, AccountId 
                    FROM Contact 
                    WHERE Email = :cleanFrom 
                    LIMIT 1
                ];
                if (!contacts.isEmpty()) {
                    matchedContact = contacts[0];
                    accountId = matchedContact.AccountId;
                }
            }

            // 4. Fallback: If still no Account found, match Account by CSM Email
            if (accountId == null && String.isNotBlank(toAddress)) {
                String cleanTo = extractEmail(toAddress);
                List<Account> accs = [
                    SELECT Id, CSM_Email__c, Owner.Email, Owner.Name 
                    FROM Account 
                    WHERE CSM_Email__c = :cleanTo 
                    LIMIT 1
                ];
                if (!accs.isEmpty()) {
                    accountId = accs[0].Id;
                }
            }

            // 5. If still no thread ID, match recent thread on Account or generate new
            if (String.isBlank(resolvedThreadId) && accountId != null) {
                String cleanSubject = subject.replaceAll('(?i)^(re|fwd|fw):\\s*', '').trim();
                cleanSubject = cleanSubject.replaceAll('\\[[^\\]]+\\]', '').trim();
                if (String.isNotBlank(cleanSubject)) {
                    String subPattern = '%' + String.escapeSingleQuotes(cleanSubject) + '%';
                    List<Event> subMatches = [
                        SELECT Gmail_Thread_Id__c 
                        FROM Event 
                        WHERE WhatId = :accountId 
                        AND Subject LIKE :subPattern 
                        AND Gmail_Thread_Id__c != null 
                        ORDER BY Gmail_Date__c DESC NULLS LAST, CreatedDate DESC 
                        LIMIT 1
                    ];
                    if (!subMatches.isEmpty()) {
                        resolvedThreadId = subMatches[0].Gmail_Thread_Id__c;
                    }
                }
            }
            if (String.isBlank(resolvedThreadId) && accountId != null) {
                List<Event> recentEvents = [
                    SELECT Gmail_Thread_Id__c 
                    FROM Event 
                    WHERE WhatId = :accountId 
                    AND Gmail_Thread_Id__c != null 
                    ORDER BY Gmail_Date__c DESC NULLS LAST, CreatedDate DESC 
                    LIMIT 1
                ];
                if (!recentEvents.isEmpty()) {
                    resolvedThreadId = recentEvents[0].Gmail_Thread_Id__c;
                }
            }
            if (String.isBlank(resolvedThreadId)) {
                resolvedThreadId = 'th_' + EncodingUtil.convertToHex(
                    Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(DateTime.now().getTime()) + cleanFrom))
                ).substring(0, 16);
            }

            // 6. Check if the sender is the CSM (Sent from personal email) or the Client
            Account acc = null;
            String csmEmail = null;
            String csmOwnerName = 'Customer Success Team';
            if (accountId != null) {
                acc = [SELECT Id, Name, CSM_Email__c, Owner.Email, Owner.Name FROM Account WHERE Id = :accountId LIMIT 1];
                csmEmail = String.isNotBlank(acc.CSM_Email__c) ? acc.CSM_Email__c : (acc.Owner != null ? acc.Owner.Email : '');
                if (acc.Owner != null && String.isNotBlank(acc.Owner.Name)) {
                    csmOwnerName = acc.Owner.Name;
                }
            }

            Boolean isFromCsm = String.isNotBlank(csmEmail) && cleanFrom.equalsIgnoreCase(csmEmail);

            if (isFromCsm) {
                // --- CASE A: CSM is replying from their personal email ---
                // Resolve contact if not already matched
                if (matchedContact == null && accountId != null) {
                    List<Contact> accContacts = [SELECT Id, Name, Email FROM Contact WHERE AccountId = :accountId AND Email != null ORDER BY CreatedDate ASC LIMIT 1];
                    if (!accContacts.isEmpty()) {
                        matchedContact = accContacts[0];
                    }
                }
                String contactEmail = matchedContact != null ? matchedContact.Email : '';

                // Process OUTBOUND Event
                Event ev = processInboundRecord(
                    accountId, 
                    matchedContact != null ? matchedContact.Id : null, 
                    resolvedThreadId, 
                    csmEmail, 
                    contactEmail, 
                    subject, 
                    bodyText,
                    'OUTBOUND'
                );

                // Forward to Contact if not already directly emailed
                Boolean clientAlreadyEmailed = false;
                if (String.isNotBlank(contactEmail)) {
                    if (email.toAddresses != null) {
                        for (String to : email.toAddresses) {
                            if (contactEmail.equalsIgnoreCase(extractEmail(to))) { clientAlreadyEmailed = true; break; }
                        }
                    }
                    if (!clientAlreadyEmailed && email.ccAddresses != null) {
                        for (String cc : email.ccAddresses) {
                            if (contactEmail.equalsIgnoreCase(extractEmail(cc))) { clientAlreadyEmailed = true; break; }
                        }
                    }
                    if (!clientAlreadyEmailed) {
                        forwardEmailToContact(contactEmail, subject, bodyText, resolvedThreadId, csmOwnerName);
                    }
                }
            } else {
                // --- CASE B: Client is sending a message/reply ---
                Event ev = processInboundRecord(
                    accountId, 
                    matchedContact != null ? matchedContact.Id : null, 
                    resolvedThreadId, 
                    fromAddress, 
                    toAddress, 
                    subject, 
                    bodyText,
                    'INBOUND'
                );

                // Forward to CSM's personal Gmail if not already sent directly to CSM
                if (String.isNotBlank(csmEmail)) {
                    Boolean csmAlreadyEmailed = false;
                    if (email.toAddresses != null) {
                        for (String to : email.toAddresses) {
                            if (csmEmail.equalsIgnoreCase(extractEmail(to))) { csmAlreadyEmailed = true; break; }
                        }
                    }
                    if (!csmAlreadyEmailed && email.ccAddresses != null) {
                        for (String cc : email.ccAddresses) {
                            if (csmEmail.equalsIgnoreCase(extractEmail(cc))) { csmAlreadyEmailed = true; break; }
                        }
                    }
                    if (!csmAlreadyEmailed) {
                        forwardEmailToCsm(csmEmail, fromAddress, subject, bodyText, resolvedThreadId);
                    }
                }
            }

            result.success = true;
        } catch (Exception ex) {
            System.debug('Error in AccountGmailInboundHandler: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
            result.success = true; // Avoid bouncing email on parsing failure
        }

        return result;
    }

    /**
     * @description Overload for default INBOUND direction.
     */
    public static Event processInboundRecord(
        Id accountId, 
        Id contactId, 
        String threadId, 
        String fromAddress, 
        String toAddress, 
        String subject, 
        String bodyText
    ) {
        return processInboundRecord(accountId, contactId, threadId, fromAddress, toAddress, subject, bodyText, 'INBOUND');
    }

    /**
     * @description Core processor that creates the Event (INBOUND or OUTBOUND) and publishes real-time Platform Event.
     *              Can be called directly by InboundEmailHandler or by the UI test simulator.
     */
    public static Event processInboundRecord(
        Id accountId, 
        Id contactId, 
        String threadId, 
        String fromAddress, 
        String toAddress, 
        String subject, 
        String bodyText,
        String direction
    ) {
        DateTime nowDt = DateTime.now();
        String cleanedBody = stripQuotedReply(bodyText);
        String prefix = (direction == 'OUTBOUND') ? 'msg_out_' : 'msg_in_';
        String msgId = prefix + EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(nowDt.getTime()) + fromAddress + String.valueOf(Crypto.getRandomInteger())))
        ).substring(0, 16);

        Event ev = new Event();
        if (accountId != null) {
            ev.WhatId = accountId;
        }
        if (contactId != null) {
            ev.WhoId = contactId;
        }
        ev.Subject = String.isNotBlank(subject) ? subject : (direction == 'OUTBOUND' ? 'CSM Reply' : 'Client Reply');
        ev.Description = String.isNotBlank(cleanedBody) ? cleanedBody : '';
        ev.StartDateTime = nowDt;
        ev.EndDateTime = nowDt.addMinutes(30);

        // Custom Gmail Fields
        ev.Gmail_Message_Id__c = msgId;
        ev.Gmail_Thread_Id__c = threadId;
        ev.Gmail_Snippet__c = (cleanedBody != null && cleanedBody.length() > 255) 
            ? cleanedBody.substring(0, 255) 
            : cleanedBody;
        ev.Gmail_From_Address__c = fromAddress;
        ev.Gmail_To_Address__c = toAddress != null && toAddress.length() > 255 ? toAddress.substring(0, 255) : toAddress;
        ev.Gmail_Direction__c = String.isNotBlank(direction) ? direction : 'INBOUND';
        ev.Gmail_Date__c = nowDt;
        ev.Gmail_Has_Attachments__c = false;
        ev.Last_Sync_Source__c = 'SALESFORCE';
        ev.Sync_Status__c = 'Synced';

        insert ev;

        // Publish real-time Platform Event to notify LWC via empApi
        if (accountId != null) {
            EventBus.publish(new Gmail_Sync_Notification__e(
                AccountId__c = accountId,
                ThreadId__c = threadId,
                MessageId__c = msgId,
                Action__c = (direction == 'OUTBOUND') ? 'SENT' : 'RECEIVED',
                Timestamp__c = nowDt
            ));
        }

        return ev;
    }

    /**
     * @description Extracts threadId matching format th_[a-zA-Z0-9_-]+
     */
    public static String extractThreadId(String text) {
        if (String.isBlank(text)) return null;
        Pattern p = Pattern.compile('(?i)(th_[a-zA-Z0-9_-]{4,40})');
        Matcher m = p.matcher(text);
        if (m.find()) {
            return m.group(1);
        }
        return null;
    }

    /**
     * @description Extracts pure email address from string format "Name <email@example.com>"
     */
    public static String extractEmail(String raw) {
        if (String.isBlank(raw)) return '';
        if (raw.contains('<') && raw.contains('>')) {
            return raw.substringBetween('<', '>').trim().toLowerCase();
        }
        return raw.trim().toLowerCase();
    }

    /**
     * @description Builds RFC 2822 References and In-Reply-To header values for a thread
     */
    public static Map<String, String> getThreadHeaders(String threadId, List<Event> priorEvents) {
        Map<String, String> headers = new Map<String, String>{
            'inReplyTo' => '',
            'references' => ''
        };
        if (String.isBlank(threadId)) return headers;

        List<Event> events = (priorEvents != null) ? priorEvents : [
            SELECT Id, Gmail_Message_Id__c 
            FROM Event 
            WHERE Gmail_Thread_Id__c = :threadId 
            ORDER BY CreatedDate ASC 
            LIMIT 30
        ];

        if (!events.isEmpty()) {
            List<String> msgIds = new List<String>();
            for (Event ev : events) {
                String mid = String.isNotBlank(ev.Gmail_Message_Id__c) ? ev.Gmail_Message_Id__c : ('msg_' + ev.Id);
                if (!mid.contains('@')) {
                    mid = mid + '@' + threadId + '.salesforce.com';
                }
                msgIds.add('<' + mid + '>');
            }
            headers.put('inReplyTo', msgIds[msgIds.size() - 1]);
            headers.put('references', String.join(msgIds, ' '));
        }
        return headers;
    }

    /**
     * @description Formats the complete conversation history into an email quote block (matching LWC styling)
     */
    public static String buildThreadedBody(String threadId, String currentBodyHtml, List<Event> priorEvents) {
        if (String.isBlank(threadId)) {
            return currentBodyHtml;
        }

        List<Event> historyEvents = (priorEvents != null) ? priorEvents : [
            SELECT Id, Subject, Description, Gmail_Snippet__c, Gmail_From_Address__c, 
                   Gmail_To_Address__c, Gmail_Direction__c, Gmail_Date__c, CreatedDate, Who.Name 
            FROM Event 
            WHERE Gmail_Thread_Id__c = :threadId 
            ORDER BY CreatedDate DESC 
            LIMIT 15
        ];

        if (historyEvents.isEmpty()) {
            return currentBodyHtml;
        }

        String historyHtml = '<br/><br/>'
            + '<div class="gmail_quote" style="border-left: 3px solid #0176d3; padding-left: 14px; margin-top: 18px; font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, Arial, sans-serif; font-size: 13px; color: #3e3e3c;">'
            + '<div style="font-weight: 700; color: #706e6b; font-size: 11px; text-transform: uppercase; margin-bottom: 12px; letter-spacing: 0.5px;">'
            + '----- Conversation History (Thread: ' + threadId.escapeHtml4() + ') -----'
            + '</div>';

        for (Event ev : historyEvents) {
            String senderLabel = (ev.Gmail_Direction__c == 'INBOUND')
                ? ((ev.Who != null && String.isNotBlank(ev.Who.Name)) ? ev.Who.Name + ' (Client)' : 'Client')
                : 'CSM / Account Team';
            
            String fromAddr = String.isNotBlank(ev.Gmail_From_Address__c) ? ' &lt;' + ev.Gmail_From_Address__c.escapeHtml4() + '&gt;' : '';
            DateTime dt = ev.Gmail_Date__c != null ? ev.Gmail_Date__c : ev.CreatedDate;
            String dateStr = dt != null ? dt.format('MMM d, yyyy, h:mm a') : '';
            
            String msgContent = String.isNotBlank(ev.Description) ? ev.Description : ev.Gmail_Snippet__c;
            if (String.isNotBlank(msgContent)) {
                msgContent = stripQuotedReply(msgContent);
                if (msgContent.length() > 500) {
                    msgContent = msgContent.substring(0, 500) + '...';
                }
                msgContent = msgContent.escapeHtml4().replaceAll('\n', '<br/>');
            } else {
                msgContent = '(No content)';
            }

            String accentColor = (ev.Gmail_Direction__c == 'INBOUND') ? '#2e844a' : '#0176d3';

            historyHtml += '<div style="margin-bottom: 12px; padding: 8px 12px; background-color: #f8f9fa; border-radius: 4px; border-left: 3px solid ' + accentColor + ';">'
                + '<div style="font-size: 12px; font-weight: 600; color: ' + accentColor + '; margin-bottom: 4px;">'
                + senderLabel.escapeHtml4() + fromAddr + ' &bull; <span style="font-weight: normal; color: #706e6b;">' + dateStr + '</span>'
                + '</div>'
                + '<div style="font-size: 13px; line-height: 1.5; color: #181818;">'
                + msgContent
                + '</div>'
                + '</div>';
        }

        historyHtml += '</div>';

        return currentBodyHtml + historyHtml;
    }

    /**
     * @description Forwards received client reply to the CSM's personal email (e.g. Gmail) with zero GCP dependency.
     */
    public static void forwardToCsm(String csmEmail, String clientFrom, String subject, String body) {
        forwardEmailToCsm(csmEmail, clientFrom, subject, body, null);
    }

    public static void forwardEmailToCsm(String csmEmail, String clientFrom, String subject, String body) {
        forwardEmailToCsm(csmEmail, clientFrom, subject, body, null);
    }

    /**
     * @description Dispatches email notification to CSM's personal inbox with full thread history and threading headers.
     */
    public static void forwardEmailToCsm(String csmEmail, String clientFrom, String subject, String body, String threadId) {
        if (String.isBlank(csmEmail)) return;

        String forwardSubject = String.isNotBlank(subject) 
            ? (subject.startsWith('Re:') || subject.startsWith('Client Reply:') ? subject : 'Re: ' + subject)
            : 'Client Reply';

        if (String.isNotBlank(threadId) && !forwardSubject.contains(threadId)) {
            forwardSubject = forwardSubject + ' [' + threadId + ']';
        }

        String inboundServiceAddress = AccountGmailController.getInboundEmailAddress();
        String effectiveReplyTo = String.isNotBlank(inboundServiceAddress) ? inboundServiceAddress : clientFrom;

        Map<String, String> threadHeaders = getThreadHeaders(threadId, null);
        String currentMsgHtml = '<p><strong>New client reply received from:</strong> ' + clientFrom.escapeHtml4() + '</p>'
            + '<hr/>'
            + '<p>' + (String.isNotBlank(body) ? body.escapeHtml4().replaceAll('\n', '<br/>') : '') + '</p>'
            + '<hr/>'
            + '<p style="font-size:12px;color:#777;"><em>Tip: Reply directly to this email from your personal Gmail or reply from the Salesforce Account page.</em></p>';

        String threadedHtmlBody = buildThreadedBody(threadId, currentMsgHtml, null);

        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            List<User> csmUsers = [SELECT Id FROM User WHERE Email = :csmEmail AND IsActive = true LIMIT 1];
            if (!csmUsers.isEmpty()) {
                mail.setTargetObjectId(csmUsers[0].Id);
            } else {
                mail.setToAddresses(new List<String>{ csmEmail });
            }

            mail.setReplyTo(effectiveReplyTo);
            mail.setSenderDisplayName(clientFrom + ' via Salesforce');
            mail.setSubject(forwardSubject);
            mail.setHtmlBody(threadedHtmlBody);
            if (String.isNotBlank(threadHeaders.get('inReplyTo'))) {
                mail.setInReplyTo(threadHeaders.get('inReplyTo'));
                mail.setReferences(threadHeaders.get('references'));
            }
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception ex) {
            System.debug('Notice: CSM forwarding skipped or failed: ' + ex.getMessage());
        }
    }

    /**
     * @description Forwards CSM reply sent from personal Gmail to the client contact with full thread history and threading headers.
     */
    public static void forwardEmailToContact(String contactEmail, String subject, String body, String threadId, String csmDisplayName) {
        if (String.isBlank(contactEmail)) return;

        String outboundSubject = subject;
        if (String.isNotBlank(threadId) && !outboundSubject.contains(threadId)) {
            outboundSubject = outboundSubject + ' [' + threadId + ']';
        }

        String inboundServiceAddress = AccountGmailController.getInboundEmailAddress();
        Map<String, String> threadHeaders = getThreadHeaders(threadId, null);
        String currentMsgHtml = '<p>' + (String.isNotBlank(body) ? body.escapeHtml4().replaceAll('\n', '<br/>') : '') + '</p>';
        String threadedHtmlBody = buildThreadedBody(threadId, currentMsgHtml, null);

        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            List<User> conUsers = [SELECT Id FROM User WHERE Email = :contactEmail AND IsActive = true LIMIT 1];
            if (!conUsers.isEmpty()) {
                mail.setTargetObjectId(conUsers[0].Id);
            } else {
                mail.setToAddresses(new List<String>{ contactEmail });
            }

            if (String.isNotBlank(inboundServiceAddress)) {
                mail.setReplyTo(inboundServiceAddress);
            }
            mail.setSenderDisplayName(String.isNotBlank(csmDisplayName) ? csmDisplayName : 'Customer Success Team');
            mail.setSubject(outboundSubject);
            mail.setHtmlBody(threadedHtmlBody);
            if (String.isNotBlank(threadHeaders.get('inReplyTo'))) {
                mail.setInReplyTo(threadHeaders.get('inReplyTo'));
                mail.setReferences(threadHeaders.get('references'));
            }
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception ex) {
            System.debug('Notice: Contact forwarding skipped or failed: ' + ex.getMessage());
        }
    }

    /**
     * @description Strips quoted email reply headers and previous message history
     *              so only the actual new reply content is preserved.
     */
    public static String stripQuotedReply(String raw) {
        if (String.isBlank(raw)) return '';

        // 1. Remove HTML quote blocks if present
        String cleaned = raw;
        cleaned = cleaned.replaceAll('(?is)<(div|blockquote)[^>]*class=[\'"][^\'"]*gmail_quote[^\'"]*[\'"][^>]*>.*', '');
        cleaned = cleaned.replaceAll('(?is)<blockquote[^>]*>.*', '');
        cleaned = cleaned.replaceAll('(?is)<div[^>]*id=[\'"]divRplyFwdMsg[\'"][^>]*>.*', '');

        // 2. Outlook / Generic / Conversation History divider lines
        cleaned = cleaned.replaceAll('(?is)-----+\\s*Conversation History.*', '');
        cleaned = cleaned.replaceAll('(?is)-----Original Message-----.*', '');
        cleaned = cleaned.replaceAll('(?is)________________________________.*', '');

        // 3. Gmail & iOS Mail: "On [Date/Time], [Sender] wrote:"
        cleaned = cleaned.replaceAll('(?is)\n\\s*On\\s+.{5,200}\\s+wrote:\\s*.*', '');
        cleaned = cleaned.replaceAll('(?is)^\\s*On\\s+.{5,200}\\s+wrote:\\s*.*', '');

        // 4. Outlook header block: "From: ... Sent: ... To: ... Subject: ..."
        cleaned = cleaned.replaceAll('(?is)\n\\s*From:\\s*.{1,120}\n\\s*Sent:\\s*.{1,100}\n\\s*To:\\s*.*', '');

        // 5. Filter out remaining lines starting with '>' or '&gt;'
        List<String> lines = cleaned.split('\n');
        List<String> preserved = new List<String>();
        for (String line : lines) {
            String trimmed = line.trim();
            if (trimmed.startsWith('>') || trimmed.startsWith('&gt;')) {
                continue;
            }
            preserved.add(line);
        }
        cleaned = String.join(preserved, '\n');

        return cleaned.trim();
    }
}
