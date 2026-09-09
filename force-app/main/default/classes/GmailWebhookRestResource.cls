@RestResource(urlMapping='/gmail/webhook/*')
global with sharing class GmailWebhookRestResource {

    @HttpGet
    global static void handleGet() {
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf('Gmail Webhook Active');
    }

    @HttpPost
    global static void handlePost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String requestBody = req.requestBody != null ? req.requestBody.toString() : '';
            System.debug('Gmail Webhook Received: ' + requestBody);

            if (String.isNotBlank(requestBody)) {
                Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(requestBody);

                if (payload.containsKey('message')) {
                    Map<String, Object> messageObj = (Map<String, Object>) payload.get('message');
                    String dataBase64 = (String) messageObj.get('data');

                    if (String.isNotBlank(dataBase64)) {
                        // Pub/Sub payload data is base64 encoded
                        Blob decodedBlob = EncodingUtil.base64Decode(dataBase64);
                        String decodedJson = decodedBlob.toString();
                        System.debug('Decoded Pub/Sub Data: ' + decodedJson);

                        Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(decodedJson);
                        String userEmail = (String) dataMap.get('emailAddress');
                        String historyId = String.valueOf(dataMap.get('historyId'));

                        // Enqueue async worker to fetch history & sync CRM records
                        if (String.isNotBlank(userEmail)) {
                            System.enqueueJob(new GmailSyncQueueable(userEmail, historyId));
                        }
                    }
                }
            }

            // Always respond HTTP 200 OK immediately to satisfy Pub/Sub push SLA
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('OK');

        } catch (Exception ex) {
            System.debug('Error in GmailWebhookRestResource: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
            res.statusCode = 200; // Still return 200 so Pub/Sub does not flood retries on malformed payloads
            res.responseBody = Blob.valueOf('ERROR_LOGGED');
        }
    }
}
