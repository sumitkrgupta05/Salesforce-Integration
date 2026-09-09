public with sharing class GoogleAuthService {
    public class GoogleAuthException extends Exception {}

    private static Map<String, CachedToken> tokenCache = new Map<String, CachedToken>();

    private class CachedToken {
        public String accessToken;
        public Long expiryEpochSeconds;

        public CachedToken(String token, Integer expiresInSeconds) {
            this.accessToken = token;
            // Subtract 60 seconds buffer
            this.expiryEpochSeconds = (DateTime.now().getTime() / 1000) + expiresInSeconds - 60;
        }

        public Boolean isValid() {
            return (DateTime.now().getTime() / 1000) < this.expiryEpochSeconds;
        }
    }

    /**
     * @description Retrieves the active Google Calendar setting from Custom Metadata
     */
    public static Google_Calendar_Setting__mdt getSetting() {
        List<Google_Calendar_Setting__mdt> settings = [
            SELECT Id, DeveloperName, Service_Account_Email__c, Token_Endpoint__c,
                   Certificate_Name__c, Private_Key__c, Client_Id__c, Webhook_Callback_URL__c,
                   Workspace_User_Email__c, Gmail_PubSub_Topic__c, Gmail_History_Id__c
            FROM Google_Calendar_Setting__mdt
            WHERE DeveloperName = 'Default_Setting'
            LIMIT 1
        ];
        if (settings.isEmpty()) {
            settings = [
                SELECT Id, DeveloperName, Service_Account_Email__c, Token_Endpoint__c,
                       Certificate_Name__c, Private_Key__c, Client_Id__c, Webhook_Callback_URL__c,
                       Workspace_User_Email__c, Gmail_PubSub_Topic__c, Gmail_History_Id__c
                FROM Google_Calendar_Setting__mdt
                LIMIT 1
            ];
        }
        if (settings.isEmpty()) {
            throw new GoogleAuthException('No Google_Calendar_Setting__mdt record found. Please configure default settings.');
        }
        return settings[0];
    }

    /**
     * @description Resolves the effective Google Workspace user email.
     */
    public static String resolveUserEmail(String userEmail) {
        if (String.isNotBlank(userEmail)) {
            return userEmail;
        }
        Google_Calendar_Setting__mdt setting = getSetting();
        if (String.isNotBlank(setting.Workspace_User_Email__c)) {
            return setting.Workspace_User_Email__c;
        }
        return UserInfo.getUserEmail();
    }

    public static final String DEFAULT_SCOPES = 
        'https://www.googleapis.com/auth/calendar ' +
        'https://www.googleapis.com/auth/calendar.events ' +
        'https://www.googleapis.com/auth/gmail.readonly ' +
        'https://www.googleapis.com/auth/gmail.send ' +
        'https://www.googleapis.com/auth/gmail.modify';

    /**
     * @description Gets a valid OAuth 2.0 access token for the specified user email via Service Account JWT flow.
     * @param userEmail The Google Workspace user email to impersonate.
     * @return String The Bearer access token.
     */
    public static String getAccessToken(String userEmail) {
        return getAccessToken(userEmail, DEFAULT_SCOPES);
    }

    /**
     * @description Gets a valid OAuth 2.0 access token with specific scopes.
     */
    public static String getAccessToken(String userEmail, String scopes) {
        String effectiveEmail = resolveUserEmail(userEmail);
        String cacheKey = effectiveEmail + '|' + (String.isNotBlank(scopes) ? scopes : DEFAULT_SCOPES);

        if (tokenCache.containsKey(cacheKey) && tokenCache.get(cacheKey).isValid()) {
            return tokenCache.get(cacheKey).accessToken;
        }

        Google_Calendar_Setting__mdt setting = getSetting();
        String tokenEndpoint = String.isNotBlank(setting.Token_Endpoint__c) 
            ? setting.Token_Endpoint__c 
            : 'https://oauth2.googleapis.com/token';

        String assertion = createSignedJwtAssertion(setting, effectiveEmail, scopes);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(tokenEndpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String body = 'grant_type=' + EncodingUtil.urlEncode('urn:ietf:params:oauth:grant-type:jwt-bearer', 'UTF-8')
            + '&assertion=' + assertion;
        req.setBody(body);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String token = (String) responseMap.get('access_token');
            Integer expiresIn = responseMap.containsKey('expires_in') 
                ? (Integer) responseMap.get('expires_in') 
                : 3600;

            tokenCache.put(cacheKey, new CachedToken(token, expiresIn));
            return token;
        } else {
            throw new GoogleAuthException('Failed to obtain Google access token for ' + effectiveEmail + 
                '. Status: ' + res.getStatus() + ', Response: ' + res.getBody());
        }
    }

    /**
     * @description Creates a signed JWT Assertion for Google OAuth2 Token endpoint with default scopes.
     */
    public static String createSignedJwtAssertion(Google_Calendar_Setting__mdt setting, String userEmail) {
        return createSignedJwtAssertion(setting, userEmail, DEFAULT_SCOPES);
    }

    /**
     * @description Creates a signed JWT Assertion for Google OAuth2 Token endpoint with custom scopes.
     */
    public static String createSignedJwtAssertion(Google_Calendar_Setting__mdt setting, String userEmail, String scopes) {
        if (String.isBlank(setting.Service_Account_Email__c)) {
            throw new GoogleAuthException('Service_Account_Email__c is missing in Google_Calendar_Setting__mdt.');
        }

        Long currentEpoch = DateTime.now().getTime() / 1000;
        Long expEpoch = currentEpoch + 3600;

        // 1. JWT Header
        Map<String, Object> header = new Map<String, Object>{
            'alg' => 'RS256',
            'typ' => 'JWT'
        };
        String headerJson = JSON.serialize(header);
        String headerBase64 = base64UrlEncode(Blob.valueOf(headerJson));

        // 2. JWT Claims
        String effectiveScopes = String.isNotBlank(scopes) ? scopes : DEFAULT_SCOPES;
        Map<String, Object> claims = new Map<String, Object>{
            'iss' => setting.Service_Account_Email__c,
            'scope' => effectiveScopes,
            'aud' => String.isNotBlank(setting.Token_Endpoint__c) ? setting.Token_Endpoint__c : 'https://oauth2.googleapis.com/token',
            'exp' => expEpoch,
            'iat' => currentEpoch,
            'sub' => userEmail
        };
        String claimsJson = JSON.serialize(claims);
        String claimsBase64 = base64UrlEncode(Blob.valueOf(claimsJson));

        // 3. Signature
        String stringToSign = headerBase64 + '.' + claimsBase64;
        Blob signatureBlob;

        if (Test.isRunningTest()) {
            signatureBlob = Blob.valueOf('mock_test_signature_data');
        } else if (String.isNotBlank(setting.Certificate_Name__c)) {
            try {
                signatureBlob = Crypto.signWithCertificate('RSA-SHA256', Blob.valueOf(stringToSign), setting.Certificate_Name__c);
            } catch (Exception certEx) {
                if (String.isNotBlank(setting.Private_Key__c)) {
                    String cleanKey = cleanPemPrivateKey(setting.Private_Key__c);
                    Blob privateKeyBlob = EncodingUtil.base64Decode(cleanKey);
                    signatureBlob = Crypto.sign('RSA-SHA256', Blob.valueOf(stringToSign), privateKeyBlob);
                } else {
                    throw certEx;
                }
            }
        } else if (String.isNotBlank(setting.Private_Key__c)) {
            String cleanKey = cleanPemPrivateKey(setting.Private_Key__c);
            Blob privateKeyBlob = EncodingUtil.base64Decode(cleanKey);
            signatureBlob = Crypto.sign('RSA-SHA256', Blob.valueOf(stringToSign), privateKeyBlob);
        } else {
            throw new GoogleAuthException('Neither Certificate_Name__c nor Private_Key__c is configured in Google_Calendar_Setting__mdt.');
        }

        String signatureBase64 = base64UrlEncode(signatureBlob);
        return stringToSign + '.' + signatureBase64;
    }

    private static String base64UrlEncode(Blob input) {
        String base64 = EncodingUtil.base64Encode(input);
        return base64.replace('+', '-').replace('/', '_').replace('=', '');
    }

    private static String cleanPemPrivateKey(String pemKey) {
        return pemKey.replace('-----BEGIN RSA PRIVATE KEY-----', '')
                     .replace('-----END RSA PRIVATE KEY-----', '')
                     .replace('-----BEGIN PRIVATE KEY-----', '')
                     .replace('-----END PRIVATE KEY-----', '')
                     .replaceAll('\\s+', '');
    }
}
