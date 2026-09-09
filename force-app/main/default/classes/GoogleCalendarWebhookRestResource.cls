@RestResource(urlMapping='/google/calendar/webhook/*')
global without sharing class GoogleCalendarWebhookRestResource {

    @HttpPost
    global static void handleNotification() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        try {
            Map<String, String> headers = req.headers;
            String channelId = headers.containsKey('x-goog-channel-id') ? headers.get('x-goog-channel-id') : headers.get('X-Goog-Channel-ID');
            String resourceState = headers.containsKey('x-goog-resource-state') ? headers.get('x-goog-resource-state') : headers.get('X-Goog-Resource-State');
            String channelToken = headers.containsKey('x-goog-channel-token') ? headers.get('x-goog-channel-token') : headers.get('X-Goog-Channel-Token');

            System.debug(LoggingLevel.INFO, 'Google Webhook Received: channelId=' + channelId + ', state=' + resourceState);

            // Google initial sync handshake
            if (resourceState == 'sync') {
                res.statusCode = 200;
                res.responseBody = Blob.valueOf('SYNC_OK');
                return;
            }

            // Target user email from channel token or resolve default
            String userEmail = String.isNotBlank(channelToken) ? channelToken : null;

            // Enqueue background processing of delta sync
            System.enqueueJob(new GoogleCalendarQueueable(userEmail, null));

            res.statusCode = 200;
            res.responseBody = Blob.valueOf('NOTIFICATION_ACCEPTED');

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Webhook Error: ' + ex.getMessage());
            res.statusCode = 200; // Return 200 so Google does not retry endlessly
            res.responseBody = Blob.valueOf('ERROR_HANDLED');
        }
    }
}
