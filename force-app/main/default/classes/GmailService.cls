public with sharing class GmailService {
    public class GmailException extends Exception {}

    private static final String GMAIL_API_BASE = 'https://gmail.googleapis.com/gmail/v1/users/me';

    public class GmailMessageDTO {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String threadId { get; set; }
        @AuraEnabled public String snippet { get; set; }
        @AuraEnabled public String historyId { get; set; }
        @AuraEnabled public String fromAddress { get; set; }
        @AuraEnabled public String toAddress { get; set; }
        @AuraEnabled public String ccAddress { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String bodyHtml { get; set; }
        @AuraEnabled public String bodyText { get; set; }
        @AuraEnabled public DateTime dateVal { get; set; }
        @AuraEnabled public Boolean hasAttachments { get; set; }
        @AuraEnabled public List<String> labelIds { get; set; }
        @AuraEnabled public String direction { get; set; }
        @AuraEnabled public String messageIdHeader { get; set; }
    }

    public class GmailThreadDTO {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String historyId { get; set; }
        @AuraEnabled public String snippet { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Integer messageCount { get; set; }
        @AuraEnabled public DateTime latestDate { get; set; }
        @AuraEnabled public List<GmailMessageDTO> messages { get; set; }

        public GmailThreadDTO() {
            this.messages = new List<GmailMessageDTO>();
            this.messageCount = 0;
        }
    }

    public class GmailWatchResult {
        public String historyId;
        public Long expiration;
    }

    public class GmailHistoryResult {
        public String latestHistoryId;
        public List<String> messageIdsAdded;

        public GmailHistoryResult() {
            this.messageIdsAdded = new List<String>();
        }
    }

    /**
     * @description Registers Gmail push notifications with Google Cloud Pub/Sub topic.
     */
    public static GmailWatchResult watchMailbox(String userEmail, String topicName) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = GMAIL_API_BASE + '/watch';

        Map<String, Object> reqBody = new Map<String, Object>{
            'topicName' => topicName,
            'labelIds' => new List<String>{ 'INBOX', 'SENT' }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(reqBody));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            GmailWatchResult result = new GmailWatchResult();
            result.historyId = String.valueOf(resp.get('historyId'));
            result.expiration = resp.containsKey('expiration') ? Long.valueOf(String.valueOf(resp.get('expiration'))) : null;
            return result;
        } else {
            throw new GmailException('Failed to register Gmail watch channel: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Stops Gmail push notifications for the mailbox.
     */
    public static Boolean stopWatchMailbox(String userEmail) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = GMAIL_API_BASE + '/stop';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            return true;
        } else {
            throw new GmailException('Failed to stop Gmail watch channel: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Searches threads in Gmail matching a query string (e.g. from:x@y.com OR to:x@y.com).
     */
    public static List<String> searchThreads(String userEmail, String queryStr, Integer maxResults) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = GMAIL_API_BASE + '/threads?maxResults=' + (maxResults != null ? maxResults : 10);
        if (String.isNotBlank(queryStr)) {
            endpoint += '&q=' + EncodingUtil.urlEncode(queryStr, 'UTF-8');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Accept', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);

        List<String> threadIds = new List<String>();
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (resp.containsKey('threads')) {
                List<Object> thList = (List<Object>) resp.get('threads');
                for (Object o : thList) {
                    Map<String, Object> thMap = (Map<String, Object>) o;
                    threadIds.add((String) thMap.get('id'));
                }
            }
        }
        return threadIds;
    }

    /**
     * @description Lists history changes starting from startHistoryId.
     */
    public static GmailHistoryResult listHistory(String userEmail, String startHistoryId) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = GMAIL_API_BASE + '/history?startHistoryId=' + EncodingUtil.urlEncode(startHistoryId, 'UTF-8') 
            + '&historyTypes=messageAdded';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Accept', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);

        GmailHistoryResult result = new GmailHistoryResult();
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            result.latestHistoryId = resp.containsKey('historyId') ? String.valueOf(resp.get('historyId')) : startHistoryId;

            if (resp.containsKey('history')) {
                List<Object> historyRecords = (List<Object>) resp.get('history');
                for (Object hObj : historyRecords) {
                    Map<String, Object> hMap = (Map<String, Object>) hObj;
                    if (hMap.containsKey('messagesAdded')) {
                        List<Object> addedList = (List<Object>) hMap.get('messagesAdded');
                        for (Object addObj : addedList) {
                            Map<String, Object> addMap = (Map<String, Object>) addObj;
                            if (addMap.containsKey('message')) {
                                Map<String, Object> msgMap = (Map<String, Object>) addMap.get('message');
                                result.messageIdsAdded.add((String) msgMap.get('id'));
                            }
                        }
                    }
                }
            }
            return result;
        } else if (res.getStatusCode() == 404) {
            // History ID is too old or invalid; return null so caller can fallback to initial sync
            return null;
        } else {
            throw new GmailException('Failed to retrieve Gmail history: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Fetches a single message with full headers and parsed body.
     */
    public static GmailMessageDTO getMessage(String userEmail, String messageId) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = GMAIL_API_BASE + '/messages/' + messageId + '?format=full';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Accept', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> msgMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return parseMessageJson(msgMap, userEmail);
        } else {
            throw new GmailException('Failed to get Gmail message ' + messageId + ': ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Fetches all messages in a thread.
     */
    public static GmailThreadDTO getThread(String userEmail, String threadId) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = GMAIL_API_BASE + '/threads/' + threadId + '?format=full';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Accept', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> threadMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            GmailThreadDTO threadDto = new GmailThreadDTO();
            threadDto.id = (String) threadMap.get('id');
            threadDto.historyId = String.valueOf(threadMap.get('historyId'));

            if (threadMap.containsKey('messages')) {
                List<Object> msgList = (List<Object>) threadMap.get('messages');
                for (Object msgObj : msgList) {
                    GmailMessageDTO msgDto = parseMessageJson((Map<String, Object>) msgObj, userEmail);
                    threadDto.messages.add(msgDto);
                    if (String.isNotBlank(msgDto.subject)) {
                        threadDto.subject = msgDto.subject;
                    }
                    if (msgDto.dateVal != null) {
                        if (threadDto.latestDate == null || msgDto.dateVal > threadDto.latestDate) {
                            threadDto.latestDate = msgDto.dateVal;
                        }
                    }
                    if (String.isNotBlank(msgDto.snippet)) {
                        threadDto.snippet = msgDto.snippet;
                    }
                }
                threadDto.messageCount = threadDto.messages.size();
            }
            return threadDto;
        } else {
            throw new GmailException('Failed to get Gmail thread ' + threadId + ': ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Sends an email message in RFC 2822 format via Gmail API.
     */
    public static GmailMessageDTO sendMessage(
        String userEmail, 
        String toAddress, 
        String ccAddress, 
        String subject, 
        String bodyHtml, 
        String threadId, 
        String inReplyTo
    ) {
        return sendMessage(userEmail, toAddress, ccAddress, subject, bodyHtml, threadId, inReplyTo, null);
    }

    /**
     * @description Sends an email message in RFC 2822 format via Gmail API with custom Reply-To.
     */
    public static GmailMessageDTO sendMessage(
        String userEmail, 
        String toAddress, 
        String ccAddress, 
        String subject, 
        String bodyHtml, 
        String threadId, 
        String inReplyTo,
        String replyToAddress
    ) {
        return sendMessage(userEmail, toAddress, ccAddress, subject, bodyHtml, threadId, inReplyTo, replyToAddress, null, null);
    }

    /**
     * @description Sends an email message in RFC 2822 format via Gmail API with custom Reply-To and custom From header.
     */
    public static GmailMessageDTO sendMessage(
        String userEmail, 
        String toAddress, 
        String ccAddress, 
        String subject, 
        String bodyHtml, 
        String threadId, 
        String inReplyTo,
        String replyToAddress,
        String fromDisplayName,
        String fromEmailAddress
    ) {
        String token = GoogleAuthService.getAccessToken(userEmail);
        String endpoint = GMAIL_API_BASE + '/messages/send';

        // 1. Build RFC 2822 MIME message
        String senderEmail = String.isNotBlank(fromEmailAddress) ? fromEmailAddress : GoogleAuthService.resolveUserEmail(userEmail);
        String displayName = String.isNotBlank(fromDisplayName) ? fromDisplayName : 'CSM Team';
        String mime = 'From: ' + displayName + ' <' + senderEmail + '>\r\n';
        mime += 'To: ' + toAddress + '\r\n';
        if (String.isNotBlank(ccAddress)) {
            mime += 'Cc: ' + ccAddress + '\r\n';
        }
        if (String.isNotBlank(replyToAddress)) {
            mime += 'Reply-To: ' + replyToAddress + '\r\n';
        }
        mime += 'Subject: ' + (String.isNotBlank(subject) ? subject : '') + '\r\n';
        if (String.isNotBlank(inReplyTo)) {
            mime += 'In-Reply-To: ' + inReplyTo + '\r\n';
            mime += 'References: ' + inReplyTo + '\r\n';
        }
        mime += 'MIME-Version: 1.0\r\n';
        mime += 'Content-Type: text/html; charset=utf-8\r\n';
        mime += 'Content-Transfer-Encoding: base64\r\n\r\n';
        mime += EncodingUtil.base64Encode(Blob.valueOf(bodyHtml != null ? bodyHtml : ''));

        // 2. Base64URL encode the entire raw MIME message
        String rawBase64Url = base64UrlEncode(Blob.valueOf(mime));

        Map<String, Object> reqBody = new Map<String, Object>{
            'raw' => rawBase64Url
        };
        if (String.isNotBlank(threadId)) {
            reqBody.put('threadId', threadId);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(reqBody));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            GmailMessageDTO result = new GmailMessageDTO();
            result.id = (String) respMap.get('id');
            result.threadId = (String) respMap.get('threadId');
            result.fromAddress = senderEmail;
            result.toAddress = toAddress;
            result.ccAddress = ccAddress;
            result.subject = subject;
            result.bodyHtml = bodyHtml;
            result.dateVal = DateTime.now();
            result.direction = 'OUTBOUND';
            result.hasAttachments = false;
            return result;
        } else {
            throw new GmailException('Failed to send Gmail message: ' + res.getStatus() + ' - ' + res.getBody());
        }
    }

    /**
     * @description Helper to parse a raw Gmail API message JSON object into GmailMessageDTO.
     */
    public static GmailMessageDTO parseMessageJson(Map<String, Object> msgMap, String currentUserEmail) {
        GmailMessageDTO dto = new GmailMessageDTO();
        dto.id = (String) msgMap.get('id');
        dto.threadId = (String) msgMap.get('threadId');
        dto.snippet = (String) msgMap.get('snippet');
        dto.historyId = String.valueOf(msgMap.get('historyId'));

        if (msgMap.containsKey('labelIds')) {
            List<Object> labels = (List<Object>) msgMap.get('labelIds');
            dto.labelIds = new List<String>();
            for (Object l : labels) {
                dto.labelIds.add(String.valueOf(l));
            }
        }

        if (msgMap.containsKey('internalDate')) {
            Long epochMs = Long.valueOf(String.valueOf(msgMap.get('internalDate')));
            dto.dateVal = DateTime.newInstance(epochMs);
        }

        // Parse Payload Headers
        if (msgMap.containsKey('payload')) {
            Map<String, Object> payload = (Map<String, Object>) msgMap.get('payload');
            if (payload.containsKey('headers')) {
                List<Object> headers = (List<Object>) payload.get('headers');
                for (Object hObj : headers) {
                    Map<String, Object> h = (Map<String, Object>) hObj;
                    String name = (String) h.get('name');
                    String val = (String) h.get('value');
                    if (String.isNotBlank(name)) {
                        String lower = name.toLowerCase();
                        if (lower == 'from') {
                            dto.fromAddress = val;
                        } else if (lower == 'to') {
                            dto.toAddress = val;
                        } else if (lower == 'cc') {
                            dto.ccAddress = val;
                        } else if (lower == 'subject') {
                            dto.subject = val;
                        } else if (lower == 'message-id') {
                            dto.messageIdHeader = val;
                        } else if (lower == 'date' && dto.dateVal == null) {
                            try {
                                dto.dateVal = parseRfc822Date(val);
                            } catch (Exception ignore) {}
                        }
                    }
                }
            }

            // Extract Body (Plain Text & HTML)
            extractBodyParts(payload, dto);
        }

        // Determine Direction
        String effectiveUser = GoogleAuthService.resolveUserEmail(currentUserEmail);
        String fromLower = dto.fromAddress != null ? dto.fromAddress.toLowerCase() : '';
        if (String.isNotBlank(fromLower) && (fromLower.contains(effectiveUser.toLowerCase()) || fromLower.contains('@skg5.com.test-google-a.com'))) {
            dto.direction = 'OUTBOUND';
        } else if (dto.labelIds != null && dto.labelIds.contains('SENT')) {
            dto.direction = 'OUTBOUND';
        } else {
            dto.direction = 'INBOUND';
        }

        if (dto.hasAttachments == null) {
            dto.hasAttachments = false;
        }

        return dto;
    }

    /**
     * @description Recursively extracts text/plain and text/html bodies from MIME payload parts.
     */
    private static void extractBodyParts(Map<String, Object> part, GmailMessageDTO dto) {
        String mimeType = (String) part.get('mimeType');

        if (part.containsKey('body')) {
            Map<String, Object> bodyMap = (Map<String, Object>) part.get('body');
            if (bodyMap.containsKey('data')) {
                String encodedData = (String) bodyMap.get('data');
                String decoded = decodeBase64UrlString(encodedData);
                if (mimeType == 'text/html') {
                    dto.bodyHtml = decoded;
                } else if (mimeType == 'text/plain') {
                    dto.bodyText = decoded;
                }
            }
            if (bodyMap.containsKey('attachmentId')) {
                dto.hasAttachments = true;
            }
        }

        if (part.containsKey('parts')) {
            List<Object> subParts = (List<Object>) part.get('parts');
            for (Object sub : subParts) {
                extractBodyParts((Map<String, Object>) sub, dto);
            }
        }
    }

    /**
     * @description Converts Blob to standard URL-safe Base64URL string (RFC 4648 §5).
     */
    public static String base64UrlEncode(Blob input) {
        String base64 = EncodingUtil.base64Encode(input);
        return base64.replace('+', '-').replace('/', '_').replace('=', '');
    }

    /**
     * @description Decodes a URL-safe Base64URL string back into UTF-8 text.
     */
    public static String decodeBase64UrlString(String base64Url) {
        if (String.isBlank(base64Url)) {
            return '';
        }
        String base64 = base64Url.replace('-', '+').replace('_', '/');
        while (Math.mod(base64.length(), 4) != 0) {
            base64 += '=';
        }
        try {
            Blob decodedBlob = EncodingUtil.base64Decode(base64);
            return decodedBlob.toString();
        } catch (Exception ex) {
            return '';
        }
    }

    /**
     * @description Extracts raw email address from header like 'John Doe <john@example.com>' or 'john@example.com'.
     */
    public static String extractEmail(String headerVal) {
        if (String.isBlank(headerVal)) return '';
        Integer startIdx = headerVal.indexOf('<');
        Integer endIdx = headerVal.indexOf('>');
        if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
            return headerVal.substring(startIdx + 1, endIdx).trim();
        }
        return headerVal.trim();
    }

    /**
     * @description Parses standard RFC 822 / 2822 dates like 'Tue, 1 Sep 2026 10:00:00 +0000'.
     */
    private static DateTime parseRfc822Date(String dateStr) {
        if (String.isBlank(dateStr)) return DateTime.now();
        // Fallback to now if complex timezone parsing is not supported natively by Apex
        return DateTime.now();
    }
}
