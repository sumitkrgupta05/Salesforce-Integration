/**
 * @description Controller for the Slack OAuth 2.0 Web Callback Visualforce page.
 *              Receives authorization code from Slack redirect, exchanges it for
 *              verified Slack user identity and 1-on-1 DM channel, and posts a
 *              success message back to the opener LWC window.
 */
public with sharing class SlackOAuthCallbackController {
    public Boolean isSuccess { get; set; }
    public String errorMessage { get; set; }
    public String slackUserId { get; set; }
    public String slackDmChannelId { get; set; }
    public String userName { get; set; }

    public SlackOAuthCallbackController() {
        isSuccess = false;
        errorMessage = '';
        slackUserId = '';
        slackDmChannelId = '';
        userName = '';
    }

    public PageReference handleCallback() {
        String code = ApexPages.currentPage().getParameters().get('code');
        String state = ApexPages.currentPage().getParameters().get('state');
        String error = ApexPages.currentPage().getParameters().get('error');

        if (String.isNotBlank(error)) {
            isSuccess = false;
            errorMessage = 'Slack authorization was declined: ' + error;
            return null;
        }

        if (String.isBlank(code)) {
            isSuccess = false;
            errorMessage = 'No authorization code was received from Slack.';
            return null;
        }

        try {
            SlackUserIdentityService.UserSlackIdentityDTO dto = SlackUserIdentityService.exchangeOAuthCode(code, state);
            if (dto != null && dto.isConnected) {
                isSuccess = true;
                slackUserId = dto.slackUserId;
                slackDmChannelId = dto.slackDmChannelId;
                userName = dto.userName;
            } else {
                isSuccess = false;
                errorMessage = (dto != null && String.isNotBlank(dto.connectionMessage)) 
                    ? dto.connectionMessage 
                    : 'Unable to authenticate with Slack workspace.';
            }
        } catch (Exception ex) {
            isSuccess = false;
            errorMessage = 'Slack OAuth processing exception: ' + ex.getMessage();
        }

        return null;
    }
}
