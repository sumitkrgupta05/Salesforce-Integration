/**
 * @description Comprehensive unit tests for SlackUserIdentityService.
 */
@IsTest
private class SlackUserIdentityServiceTest {

    private class SlackMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            if (req.getEndpoint().contains('users.lookupByEmail')) {
                res.setBody('{"ok":true,"user":{"id":"U0C036Y8XC0","name":"sumit"}}');
            } else if (req.getEndpoint().contains('conversations.open')) {
                res.setBody('{"ok":true,"channel":{"id":"D0BUQS5V68Z"}}');
            } else {
                res.setBody('{"ok":true}');
            }
            return res;
        }
    }

    @IsTest
    static void testResolveCurrentIdentityFirstTimeAndCacheHit() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());

        Test.startTest();
        // First-time resolution (auto-discovery)
        SlackUserIdentityService.UserSlackIdentityDTO dto1 = SlackUserIdentityService.getOrResolveUserIdentity();
        Assert.isNotNull(dto1, 'Identity DTO should not be null');
        Assert.isTrue(dto1.isConnected, 'Should be connected');
        Assert.isNotNull(dto1.slackDmChannelId, 'Channel ID should be populated');

        // Subsequent resolution (persistent database cache hit)
        SlackUserIdentityService.UserSlackIdentityDTO dto2 = SlackUserIdentityService.getOrResolveUserIdentity();
        Assert.isTrue(dto2.isConnected, 'Should remain connected on cache hit');
        Assert.areEqual(dto1.slackDmChannelId, dto2.slackDmChannelId, 'Channel ID should match cached value');
        Test.stopTest();
    }

    @IsTest
    static void testEmailDriftSelfHealing() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());

        User currentUser = [SELECT Id, Email, Slack_Connected_Email__c, Slack_DM_Channel_Id__c FROM User WHERE Id = :UserInfo.getUserId()];
        currentUser.Slack_DM_Channel_Id__c = 'D_OLD_CHANNEL';
        currentUser.Slack_Connected_Email__c = 'old_email@example.com';
        update currentUser;

        Test.startTest();
        // On routine getOrResolveUserIdentity, the cached channel is preserved without unexpected disconnects
        SlackUserIdentityService.UserSlackIdentityDTO cachedDto = SlackUserIdentityService.getOrResolveUserIdentity();
        Assert.isTrue(cachedDto.isConnected, 'Should remain connected using cached channel');
        Assert.areEqual('D_OLD_CHANNEL', cachedDto.slackDmChannelId, 'Cached channel is preserved');

        // When reSyncSlackIdentity is explicitly called, it re-discovers and updates the identity
        SlackUserIdentityService.UserSlackIdentityDTO reSyncedDto = SlackUserIdentityService.reSyncSlackIdentity();
        Assert.isTrue(reSyncedDto.isConnected, 'Should reconnect upon re-syncing');
        Assert.areNotEqual('D_OLD_CHANNEL', reSyncedDto.slackDmChannelId, 'Channel should be updated to new discovery');
        Test.stopTest();
    }

    @IsTest
    static void testCompletePairingSuccessAndInvalid() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());

        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        currentUser.Slack_Pairing_Code__c = '999888';
        update currentUser;

        Test.startTest();
        // 1. Success pairing
        Map<String, Object> successRes = SlackUserIdentityService.completePairing('999888', 'U_CUSTOM_USER', 'D_CUSTOM_CHAN');
        Assert.areEqual(true, successRes.get('isSuccess'), 'Pairing should succeed');

        User updatedUser = [SELECT Slack_DM_Channel_Id__c, Slack_Pairing_Code__c FROM User WHERE Id = :UserInfo.getUserId()];
        Assert.areEqual('D_CUSTOM_CHAN', updatedUser.Slack_DM_Channel_Id__c, 'Channel should be updated');
        Assert.isNull(updatedUser.Slack_Pairing_Code__c, 'Pairing code should be cleared');

        // 2. Invalid pairing code
        Map<String, Object> failRes = SlackUserIdentityService.completePairing('000000', 'U_FAKE', 'D_FAKE');
        Assert.areEqual(false, failRes.get('isSuccess'), 'Invalid pairing code should fail');
        Test.stopTest();
    }

    @IsTest
    static void testLinkDirectSlackIdentity() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());

        Test.startTest();
        // Link via member ID
        SlackUserIdentityService.UserSlackIdentityDTO dto = SlackUserIdentityService.linkDirectSlackIdentity('U0BUGJC5U5R');
        Assert.isTrue(dto.isConnected, 'Should be connected via direct member ID');

        // Link via DM channel directly
        SlackUserIdentityService.UserSlackIdentityDTO dto2 = SlackUserIdentityService.linkDirectSlackIdentity('D0BUNTVJCQJ');
        Assert.areEqual('D0BUNTVJCQJ', dto2.slackDmChannelId, 'Should link direct channel');
        Test.stopTest();
    }

    @IsTest
    static void testDisconnectAndReSyncSlackIdentity() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());

        Test.startTest();
        Boolean disconnected = SlackUserIdentityService.disconnectSlackAccount();
        Assert.isTrue(disconnected, 'Disconnect should return true');

        User u = [SELECT Slack_DM_Channel_Id__c FROM User WHERE Id = :UserInfo.getUserId()];
        Assert.isNull(u.Slack_DM_Channel_Id__c, 'Channel should be cleared');

        SlackUserIdentityService.UserSlackIdentityDTO reSynced = SlackUserIdentityService.reSyncSlackIdentity();
        Assert.isTrue(reSynced.isConnected, 'Re-sync should re-connect user');
        Test.stopTest();
    }

    @IsTest
    static void testBuildUserSlackThreadUrl() {
        String urlWithTs = SlackUserIdentityService.buildUserSlackThreadUrl('1788513404.400199', 'D0BUNTVJCQJ');
        Assert.isTrue(urlWithTs.contains('D0BUNTVJCQJ'), 'Should include specific user channel');
        Assert.isTrue(urlWithTs.contains('thread_ts=1788513404.400199'), 'Should include thread timestamp');

        String fallbackUrl = SlackUserIdentityService.buildUserSlackThreadUrl('', 'D0BUNTVJCQJ');
        Assert.isTrue(fallbackUrl.contains('app_redirect?channel=D0BUNTVJCQJ'), 'Should fallback to user channel redirect');
    }

    @IsTest
    static void testAuthenticateWithSlack() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());

        Test.startTest();
        SlackUserIdentityService.UserSlackIdentityDTO authDto = SlackUserIdentityService.authenticateWithSlack();
        Assert.isNotNull(authDto, 'Auth DTO should not be null');
        Assert.isTrue(authDto.isConnected, 'Should be successfully connected via official authentication');
        Assert.isNotNull(authDto.slackDmChannelId, 'DM channel should be populated');

        // Test via controller
        SlackUserIdentityService.UserSlackIdentityDTO ctrlDto = SlackBotAgentController.authenticateWithSlack();
        Assert.isNotNull(ctrlDto, 'Controller auth DTO should not be null');
        Assert.isTrue(ctrlDto.isConnected, 'Controller auth should succeed');

        // Test authenticateWithSlackCredentials
        SlackUserIdentityService.UserSlackIdentityDTO credDto = SlackUserIdentityService.authenticateWithSlackCredentials('skgsummo5@gmail.com');
        Assert.isNotNull(credDto, 'Cred DTO should not be null');
        Assert.isTrue(credDto.isConnected, 'Should connect with Slack credentials');
        Assert.areEqual('U0BUGJC5U5R', credDto.slackUserId, 'Should match Summo Slack user');

        // Test via controller
        SlackUserIdentityService.UserSlackIdentityDTO ctrlCredDto = SlackBotAgentController.authenticateWithSlackCredentials('skgsumit5@gmail.com');
        Assert.isNotNull(ctrlCredDto, 'Controller Cred DTO should not be null');
        Assert.isTrue(ctrlCredDto.isConnected, 'Controller Cred auth should succeed');
        Test.stopTest();
    }

    @IsTest
    static void testOAuthUrlAndExchange() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());

        Test.startTest();
        // Initially empty Client ID
        String nullUrl = SlackUserIdentityService.getSlackOAuthUrl();
        Assert.isNull(nullUrl, 'Should return null when Client ID is not configured');

        // Set test Client ID
        SlackUserIdentityService.SLACK_CLIENT_ID = '11959489480023.test';
        SlackUserIdentityService.SLACK_CLIENT_SECRET = 'test_secret';
        String oauthUrl = SlackUserIdentityService.getSlackOAuthUrl();
        Assert.isNotNull(oauthUrl, 'OAuth URL should be generated');
        Assert.isTrue(oauthUrl.contains('slack.com/oauth/v2/authorize'), 'URL should point to Slack authorize');

        String ctrlOauthUrl = SlackBotAgentController.getSlackOAuthUrl();
        Assert.isNotNull(ctrlOauthUrl, 'Controller should return OAuth URL');

        String nullGcpUrl = SlackUserIdentityService.getGcpSlackAuthUrl();
        Assert.isNull(nullGcpUrl, 'Should return null when GCP URL is not configured');

        SlackUserIdentityService.GCP_SLACK_AUTH_URL = 'https://my-gcp-service.run.app/auth/login';
        String gcpUrl = SlackUserIdentityService.getGcpSlackAuthUrl();
        Assert.isNotNull(gcpUrl, 'GCP Auth URL should not be null');
        Assert.isTrue(gcpUrl.contains('/auth/login'), 'Should contain /auth/login');
        String ctrlGcpUrl = SlackBotAgentController.getGcpSlackAuthUrl();
        Assert.isNotNull(ctrlGcpUrl, 'Controller GCP Auth URL should not be null');

        // Test code exchange
        SlackUserIdentityService.UserSlackIdentityDTO exchanged = SlackUserIdentityService.exchangeOAuthCode('test_auth_code', UserInfo.getUserId() + ':12345');
        Assert.isNotNull(exchanged, 'Exchanged DTO should not be null');
        Assert.isTrue(exchanged.isConnected, 'Should be connected after code exchange');
        Test.stopTest();
    }

    @IsTest
    static void testSlackOAuthCallbackController() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());

        Test.startTest();
        // 1. Success callback
        PageReference pageRef = Page.SlackOAuthCallback;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('code', 'valid_test_code');
        ApexPages.currentPage().getParameters().put('state', UserInfo.getUserId() + ':9999');

        SlackOAuthCallbackController ctrl = new SlackOAuthCallbackController();
        ctrl.handleCallback();
        Assert.isTrue(ctrl.isSuccess, 'Callback should succeed with valid code');
        Assert.isNotNull(ctrl.slackUserId, 'Slack User ID should be populated');

        // 2. Error callback
        ApexPages.currentPage().getParameters().clear();
        ApexPages.currentPage().getParameters().put('error', 'access_denied');
        SlackOAuthCallbackController errCtrl = new SlackOAuthCallbackController();
        errCtrl.handleCallback();
        Assert.isFalse(errCtrl.isSuccess, 'Callback should fail when error received');

        // 3. Blank code callback
        ApexPages.currentPage().getParameters().clear();
        SlackOAuthCallbackController blankCtrl = new SlackOAuthCallbackController();
        blankCtrl.handleCallback();
        Assert.isFalse(blankCtrl.isSuccess, 'Callback should fail when code is blank');
        Test.stopTest();
    }

    @IsTest
    static void testWorkspaceMembersAndLinkWorkspaceUser() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());

        Test.startTest();
        List<SlackUserIdentityService.WorkspaceMemberDTO> members = SlackUserIdentityService.getWorkspaceMembers();
        Assert.isNotNull(members, 'Members list should not be null');
        Assert.isFalse(members.isEmpty(), 'Members list should contain members');

        List<SlackUserIdentityService.WorkspaceMemberDTO> ctrlMembers = SlackBotAgentController.getWorkspaceMembers();
        Assert.isNotNull(ctrlMembers, 'Controller members should not be null');

        SlackUserIdentityService.UserSlackIdentityDTO linked = SlackBotAgentController.linkWorkspaceMember('U0BUGJC5U5R');
        Assert.isNotNull(linked, 'Linked identity should not be null');
        Assert.isTrue(linked.isConnected, 'Should be connected after linking member');
        Test.stopTest();
    }
}
