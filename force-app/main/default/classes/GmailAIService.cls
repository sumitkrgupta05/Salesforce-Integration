/**
 * @description AI Service for analyzing and summarizing Gmail conversation threads.
 *              Supports Google Gemini LLM API and intelligent extractive fallback.
 */
public with sharing class GmailAIService {

    public class AISummaryException extends Exception {}

    public class ThreadSummaryResult {
        @AuraEnabled public String executiveSummary { get; set; }
        @AuraEnabled public String wholeThreadSummary { get; set; }
        @AuraEnabled public List<String> keyPoints { get; set; }
        @AuraEnabled public List<String> actionItems { get; set; }
        @AuraEnabled public String keyPointsRaw { get; set; }
        @AuraEnabled public String actionItemsRaw { get; set; }
        @AuraEnabled public Integer messageCount { get; set; }
        @AuraEnabled public String latestMessageId { get; set; }
        @AuraEnabled public DateTime lastGeneratedAt { get; set; }
        @AuraEnabled public String modelUsed { get; set; }
        @AuraEnabled public Boolean isCached { get; set; }

        public ThreadSummaryResult() {
            this.keyPoints = new List<String>();
            this.actionItems = new List<String>();
            this.isCached = false;
        }
    }

    /**
     * @description Generates an AI summary for a list of chronological messages in a thread.
     */
    public static ThreadSummaryResult generateSummary(
        String threadId, 
        Id accountId, 
        List<GmailService.GmailMessageDTO> messages
    ) {
        if (messages == null || messages.isEmpty()) {
            ThreadSummaryResult emptyRes = new ThreadSummaryResult();
            emptyRes.executiveSummary = 'No messages found in this thread to summarize.';
            emptyRes.messageCount = 0;
            emptyRes.lastGeneratedAt = DateTime.now();
            emptyRes.modelUsed = 'None';
            return emptyRes;
        }

        // 1. Build conversation transcript in chronological order
        String transcript = buildTranscript(messages);

        // 2. Check if Gemini API key is configured
        String apiKey = getGeminiApiKey();

        ThreadSummaryResult result;
        if (String.isNotBlank(apiKey)) {
            try {
                result = callGeminiApi(transcript, apiKey, messages.size());
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Gemini API call failed, using intelligent fallback: ' + ex.getMessage());
                result = generateFallbackSummary(messages);
            }
        } else {
            // Intelligent fallback summarization
            result = generateFallbackSummary(messages);
        }

        result.messageCount = messages.size();
        GmailService.GmailMessageDTO latestMsg = messages[messages.size() - 1];
        result.latestMessageId = latestMsg.id;
        result.lastGeneratedAt = DateTime.now();

        return result;
    }

    /**
     * @description Formats chronological messages into a clear conversation transcript.
     */
    private static String buildTranscript(List<GmailService.GmailMessageDTO> messages) {
        String transcript = '';
        for (Integer i = 0; i < messages.size(); i++) {
            GmailService.GmailMessageDTO msg = messages[i];
            String role = (msg.direction == 'OUTBOUND') ? 'Sales Rep (You)' : 'Client (' + msg.fromAddress + ')';
            transcript += '--- [Message ' + (i + 1) + ' of ' + messages.size() + '] ---\n';
            transcript += 'Sender: ' + role + '\n';
            transcript += 'Subject: ' + (String.isNotBlank(msg.subject) ? msg.subject : '(No Subject)') + '\n';
            if (msg.dateVal != null) {
                transcript += 'Date: ' + msg.dateVal.format('yyyy-MM-dd HH:mm:ss') + '\n';
            }
            String content = cleanEmailBody(msg);
            transcript += 'Content:\n' + content + '\n\n';
        }
        return transcript;
    }

    /**
     * @description Cleans HTML or plain text body for AI ingestion.
     */
    private static String cleanEmailBody(GmailService.GmailMessageDTO msg) {
        String raw = String.isNotBlank(msg.bodyText) ? msg.bodyText : msg.bodyHtml;
        if (String.isBlank(raw)) {
            raw = String.isNotBlank(msg.snippet) ? msg.snippet : '';
        }
        // Strip quoted email history so AI receives pure content
        String stripped = AccountGmailInboundHandler.stripQuotedReply(raw);
        // Strip HTML tags if present
        String cleaned = stripped.replaceAll('<[^>]+>', ' ').replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&');
        cleaned = cleaned.replaceAll('\\s+', ' ').trim();
        // Limit individual message content to avoid exceeding token windows
        if (cleaned.length() > 2000) {
            cleaned = cleaned.substring(0, 2000) + '... [truncated]';
        }
        return cleaned;
    }

    /**
     * @description Calls Google Gemini 1.5 Flash API to generate structured summary.
     */
    private static ThreadSummaryResult callGeminiApi(String transcript, String apiKey, Integer messageCount) {
        String endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=' + apiKey;

        String prompt = 'You are an executive AI assistant analyzing a business email thread for a CRM team.\n'
            + 'Here is the full chronological conversation transcript from the first message to the latest message:\n\n'
            + transcript + '\n\n'
            + 'Instructions:\n'
            + '1. Read every message carefully in order to understand the complete interaction history.\n'
            + '2. Generate a JSON object with EXACTLY three fields:\n'
            + '   "executiveSummary": A clear, comprehensive 2-3 sentence overview describing what communication has taken place so far across all messages and what the participants are currently talking about/focusing on.\n'
            + '   "keyPoints": A JSON array of 3 to 5 bullet points tracing what communication has been done till now across each exchange (e.g. "Exchange 1: Rep reached out with...", "Exchange 2: Client responded regarding...", "Current Topic: Active discussion on...").\n'
            + '   "actionItems": A JSON array of 1 to 3 concrete next steps or follow-ups for the sales/CSM rep based on the latest client message.\n'
            + 'Do not include Markdown backticks around the JSON. Respond with raw valid JSON only.';

        Map<String, Object> reqBody = new Map<String, Object>{
            'contents' => new List<Object>{
                new Map<String, Object>{
                    'parts' => new List<Object>{
                        new Map<String, Object>{ 'text' => prompt }
                    }
                }
            },
            'generationConfig' => new Map<String, Object>{
                'temperature' => 0.2,
                'maxOutputTokens' => 800
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(25000);
        req.setBody(JSON.serialize(reqBody));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            return parseGeminiResponse(res.getBody());
        } else {
            throw new AISummaryException('Gemini API returned status ' + res.getStatusCode() + ': ' + res.getBody());
        }
    }

    /**
     * @description Parses Gemini JSON response into ThreadSummaryResult.
     */
    private static ThreadSummaryResult parseGeminiResponse(String jsonResponse) {
        ThreadSummaryResult result = new ThreadSummaryResult();
        result.modelUsed = 'Gemini 1.5 Flash';

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
        List<Object> candidates = (List<Object>) root.get('candidates');
        if (candidates != null && !candidates.isEmpty()) {
            Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];
            Map<String, Object> content = (Map<String, Object>) firstCandidate.get('content');
            List<Object> parts = (List<Object>) content.get('parts');
            if (parts != null && !parts.isEmpty()) {
                Map<String, Object> firstPart = (Map<String, Object>) parts[0];
                String text = (String) firstPart.get('text');
                if (String.isNotBlank(text)) {
                    text = text.trim();
                    if (text.startsWith('```json')) {
                        text = text.removeStart('```json').trim();
                    }
                    if (text.startsWith('```')) {
                        text = text.removeStart('```').trim();
                    }
                    if (text.endsWith('```')) {
                        text = text.removeEnd('```').trim();
                    }

                    try {
                        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(text);
                        result.executiveSummary = (String) jsonMap.get('executiveSummary');

                        List<Object> kpList = (List<Object>) jsonMap.get('keyPoints');
                        if (kpList != null) {
                            for (Object kp : kpList) {
                                result.keyPoints.add(String.valueOf(kp));
                            }
                        }

                        List<Object> aiList = (List<Object>) jsonMap.get('actionItems');
                        if (aiList != null) {
                            for (Object ai : aiList) {
                                result.actionItems.add(String.valueOf(ai));
                            }
                        }
                    } catch (Exception parseEx) {
                        result.executiveSummary = text;
                    }
                }
            }
        }

        result.wholeThreadSummary = result.executiveSummary;
        result.keyPointsRaw = String.join(result.keyPoints, '\n');
        result.actionItemsRaw = String.join(result.actionItems, '\n');
        return result;
    }

    /**
     * @description Intelligent fallback engine that summarizes threads without external API keys.
     */
    public static ThreadSummaryResult generateFallbackSummary(List<GmailService.GmailMessageDTO> messages) {
        ThreadSummaryResult result = new ThreadSummaryResult();
        result.modelUsed = 'Smart Conversation Engine';

        Integer count = messages.size();
        GmailService.GmailMessageDTO firstMsg = messages[0];
        GmailService.GmailMessageDTO latestMsg = messages[count - 1];

        String subject = String.isNotBlank(latestMsg.subject) ? latestMsg.subject : firstMsg.subject;
        if (subject != null && subject.contains('[th_')) {
            subject = subject.replaceAll('\\[th_[^\\]]+\\]', '').trim();
        }

        // 1. Trace communication done till now across every message in the thread
        List<String> journey = new List<String>();
        for (Integer i = 0; i < count; i++) {
            GmailService.GmailMessageDTO m = messages[i];
            String role = (m.direction == 'OUTBOUND') ? 'CSM / Sales Rep' : 'Client (' + m.fromAddress + ')';
            String dateStr = (m.dateVal != null) ? m.dateVal.format('MMM d') : ('Message ' + (i + 1));
            String rawText = String.isNotBlank(m.snippet) ? m.snippet : (String.isNotBlank(m.bodyText) ? m.bodyText : '');
            String cleanSnippet = AccountGmailInboundHandler.stripQuotedReply(rawText);
            cleanSnippet = cleanSnippet.replaceAll('<[^>]+>', ' ').replaceAll('\\s+', ' ').trim();
            if (cleanSnippet.length() > 140) {
                cleanSnippet = cleanSnippet.substring(0, 140) + '...';
            }
            journey.add('Message ' + (i + 1) + ' — ' + role + ' (' + dateStr + '): "' + cleanSnippet + '"');
        }

        String latestRaw = String.isNotBlank(latestMsg.snippet) ? latestMsg.snippet : (String.isNotBlank(latestMsg.bodyText) ? latestMsg.bodyText : '');
        String latestClean = AccountGmailInboundHandler.stripQuotedReply(latestRaw);
        latestClean = latestClean.replaceAll('<[^>]+>', ' ').replaceAll('\\s+', ' ').trim();
        if (latestClean.length() > 140) {
            latestClean = latestClean.substring(0, 140) + '...';
        }

        // 2. Whole Thread Narrative Overview for CSM
        String firstRaw = String.isNotBlank(firstMsg.snippet) ? firstMsg.snippet : (String.isNotBlank(firstMsg.bodyText) ? firstMsg.bodyText : '');
        String firstClean = AccountGmailInboundHandler.stripQuotedReply(firstRaw);
        firstClean = firstClean.replaceAll('<[^>]+>', ' ').replaceAll('\\s+', ' ').trim();
        if (firstClean.length() > 140) {
            firstClean = firstClean.substring(0, 140) + '...';
        }

        if (count == 1) {
            String dirLabel = (firstMsg.direction == 'OUTBOUND') ? 'CSM outreach' : 'inbound client inquiry';
            result.executiveSummary = 'Single-message thread regarding "' + subject + '" (' + dirLabel + '). '
                + 'Topic discussed: "' + latestClean + '". '
                + (firstMsg.direction == 'OUTBOUND' ? 'Awaiting response from client.' : 'Pending review and follow-up from CSM.');
        } else {
            String firstSpeaker = (firstMsg.direction == 'OUTBOUND') ? 'CSM outreach' : 'inbound inquiry from client';
            String lastSpeaker = (latestMsg.direction == 'INBOUND') ? 'the client' : 'the CSM';
            String currentStatus = (latestMsg.direction == 'INBOUND' 
                ? 'Client reply received; pending CSM review and follow-up.' 
                : 'Latest message dispatched by CSM; awaiting client response.');

            result.executiveSummary = 'Whole thread overview (' + count + ' messages regarding "' + subject + '"): '
                + 'Communication began with ' + firstSpeaker + ' ("' + firstClean + '"). '
                + 'Across ' + count + ' exchanges, the discussion progressed with the latest update from ' + lastSpeaker + ': "' + latestClean + '". '
                + 'Current status: ' + currentStatus;
        }
        result.wholeThreadSummary = result.executiveSummary;

        // 3. Key Discussion Points: Communication done till now & active focus
        result.keyPoints.add('Primary Topic: Discussion and coordination regarding "' + subject + '".');
        for (String step : journey) {
            result.keyPoints.add(step);
        }
        if (count > 1) {
            result.keyPoints.add('Current Status: ' + (latestMsg.direction == 'INBOUND' ? 'Client reply received; pending CSM review and response.' : 'Latest message dispatched; awaiting client reply.'));
        }

        // 4. Action Items & Next Steps
        if (latestMsg.direction == 'INBOUND') {
            result.actionItems.add('Client replied: "' + latestClean + '". Review response and follow up.');
            result.actionItems.add('Coordinate on requested details, meeting schedule, or agreements.');
        } else {
            result.actionItems.add('Awaiting client reply to latest email sent on ' + (latestMsg.dateVal != null ? latestMsg.dateVal.format('MMM d') : 'recent date') + '.');
        }

        result.keyPointsRaw = String.join(result.keyPoints, '\n');
        result.actionItemsRaw = String.join(result.actionItems, '\n');
        return result;
    }

    /**
     * @description Retrieves the optional Gemini API key from Custom Metadata or Environment.
     */
    private static String getGeminiApiKey() {
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
            // Field or metadata not available yet
        }
        return null;
    }
}
