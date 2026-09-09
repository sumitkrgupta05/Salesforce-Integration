import http from 'http';
import { URL } from 'url';
import { loadConfig } from '../config.js';
import { getSalesforceCredentials } from '../mcp/salesforceAuth.js';

interface StatePayload {
  sfUserId: string;
  sfOrgId?: string;
  email: string;
  ts: number;
}

/**
 * Encodes a JSON payload to a base64url string.
 */
function encodeState(data: StatePayload): string {
  return Buffer.from(JSON.stringify(data)).toString('base64url');
}

/**
 * Decodes a base64url string into a StatePayload.
 */
function decodeState(stateStr: string): StatePayload | null {
  try {
    const json = Buffer.from(stateStr, 'base64url').toString('utf8');
    return JSON.parse(json);
  } catch {
    return null;
  }
}

/**
 * Renders an HTML page that posts a message to window.opener and closes the popup.
 */
function renderAuthResultHtml(isSuccess: boolean, params: {
  title?: string;
  message?: string;
  slackUserId?: string;
  slackDmChannelId?: string;
  userName?: string;
  returnUrl?: string;
}): string {
  const { title, message, slackUserId, slackDmChannelId, userName, returnUrl } = params;
  const statusClass = isSuccess ? 'success' : 'error';
  const statusIcon = isSuccess ? '✅' : '❌';
  const headerText = title || (isSuccess ? 'Slack Connected Successfully' : 'Authentication Failed');
  const descText = message || (isSuccess 
    ? 'Your private 1-on-1 Slack DM has been linked to your Salesforce user profile.' 
    : 'Unable to authenticate with Slack workspace.');

  const payloadJson = JSON.stringify({
    type: isSuccess ? 'SLACK_AUTH_SUCCESS' : 'SLACK_AUTH_ERROR',
    isConnected: isSuccess,
    slackUserId: slackUserId || '',
    slackDmChannelId: slackDmChannelId || '',
    userName: userName || '',
    message: descText
  });

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${headerText}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      padding: 20px;
      box-sizing: border-box;
    }
    .auth-card {
      background: #ffffff;
      border-radius: 12px;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.1);
      padding: 36px 28px;
      max-width: 440px;
      width: 100%;
      text-align: center;
      border: 1px solid #e2e8f0;
    }
    .title {
      font-size: 20px;
      font-weight: 700;
      margin-bottom: 8px;
      color: ${isSuccess ? '#047857' : '#b91c1c'};
    }
    .desc {
      font-size: 14px;
      color: #475569;
      line-height: 1.5;
      margin-bottom: 20px;
    }
    .badge {
      display: inline-block;
      background: #ecfdf5;
      border: 1px solid #a7f3d0;
      color: #065f46;
      padding: 6px 14px;
      border-radius: 9999px;
      font-size: 13px;
      font-weight: 600;
      font-family: monospace;
      margin-bottom: 16px;
    }
    .close-btn {
      background: #0f172a;
      color: #ffffff;
      border: none;
      border-radius: 6px;
      padding: 10px 20px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
    }
  </style>
</head>
<body>
  <div class="auth-card">
    <div class="title">${statusIcon} ${headerText}</div>
    <p class="desc">${descText}</p>
    ${isSuccess && slackDmChannelId ? `<div class="badge">DM Channel: ${slackDmChannelId}</div>` : ''}
    <p class="desc" style="font-size: 12px; color: #94a3b8;">
      Closing window and redirecting to Salesforce...
    </p>
    <button class="close-btn" onclick="window.close();">Close Window</button>
  </div>
  <script>
    try {
      if (window.opener) {
        window.opener.postMessage(${payloadJson}, '*');
        setTimeout(function() {
          window.close();
        }, 1200);
      } else if ('${returnUrl || ''}') {
        setTimeout(function() {
          window.location.href = '${returnUrl || ''}';
        }, 1500);
      }
    } catch(e) {
      console.error('PostMessage error:', e);
    }
  </script>
</body>
</html>`;
}

/**
 * Renders the interactive Slack Workspace OAuth Consent screen.
 * Displays app name, workspace, user to connect, requested scopes, and Allow / Cancel buttons.
 */
function renderSlackConsentHtml(params: {
  sfUserId: string;
  sfOrgId?: string;
  email: string;
  workspaceName?: string;
  appName?: string;
}): string {
  const { sfUserId, sfOrgId, email, workspaceName = 'AI Studio Agent with Slack', appName = 'test_agent_app' } = params;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Authorize ${appName} | Slack</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background-color: #f4ede4;
      color: #1d1c1d;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 24px 16px;
    }
    .container {
      background: #ffffff;
      border-radius: 12px;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.08);
      max-width: 520px;
      width: 100%;
      padding: 40px 36px;
      border: 1px solid #e2e8f0;
      text-align: center;
    }
    .slack-header {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 12px;
      margin-bottom: 20px;
    }
    .slack-logo {
      width: 44px;
      height: 44px;
    }
    .connect-arrow {
      font-size: 20px;
      color: #616061;
    }
    .app-icon {
      width: 44px;
      height: 44px;
      background: #4A154B;
      color: white;
      border-radius: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 700;
      font-size: 22px;
    }
    h1 {
      font-size: 20px;
      font-weight: 700;
      line-height: 1.35;
      margin-bottom: 12px;
      color: #1d1c1d;
    }
    .workspace-pill {
      display: inline-block;
      background: #f8fafc;
      border: 1px solid #cbd5e1;
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 13px;
      font-weight: 600;
      color: #334155;
      margin-bottom: 20px;
    }
    .user-info-box {
      background: #f8f9fa;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      padding: 14px 18px;
      text-align: left;
      margin-bottom: 20px;
    }
    .user-info-label {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      color: #616061;
      font-weight: 700;
      margin-bottom: 4px;
    }
    .user-info-value {
      font-size: 14px;
      color: #1d1c1d;
      font-weight: 600;
      word-break: break-all;
    }
    .permissions-section {
      text-align: left;
      margin-bottom: 24px;
    }
    .permissions-title {
      font-size: 12px;
      font-weight: 700;
      color: #616061;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 12px;
    }
    .perm-item {
      display: flex;
      align-items: flex-start;
      gap: 12px;
      margin-bottom: 10px;
      font-size: 13px;
      color: #1d1c1d;
      line-height: 1.4;
    }
    .perm-icon {
      font-size: 16px;
      line-height: 1;
      margin-top: 1px;
    }
    .btn-group {
      display: flex;
      gap: 12px;
      justify-content: center;
      margin-top: 8px;
    }
    .btn-allow {
      flex: 1;
      background: #007a5a;
      color: #ffffff;
      border: none;
      padding: 12px 24px;
      border-radius: 6px;
      font-size: 15px;
      font-weight: 700;
      cursor: pointer;
      transition: background 0.15s ease;
    }
    .btn-allow:hover {
      background: #148567;
    }
    .btn-cancel {
      flex: 1;
      background: #ffffff;
      color: #1d1c1d;
      border: 1px solid #d1d5db;
      padding: 12px 24px;
      border-radius: 6px;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.15s ease;
    }
    .btn-cancel:hover {
      background: #f9fafb;
    }
    .footer-note {
      margin-top: 18px;
      font-size: 12px;
      color: #616061;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="slack-header">
      <svg class="slack-logo" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 122.8 122.8">
        <path fill="#e01e5a" d="M25.8 77.6a12.9 12.9 0 1 1-12.9-12.9h12.9v12.9zm6.5 0a12.9 12.9 0 1 1 25.8 0v32.3a12.9 12.9 0 1 1-25.8 0V77.6z"/>
        <path fill="#36c5f0" d="M45.2 25.8a12.9 12.9 0 1 1 12.9-12.9v12.9H45.2zm0 6.5a12.9 12.9 0 1 1 0 25.8H12.9a12.9 12.9 0 1 1 0-25.8h32.3z"/>
        <path fill="#2eb67d" d="M97 45.2a12.9 12.9 0 1 1 12.9 12.9H97V45.2zm-6.5 0a12.9 12.9 0 1 1-25.8 0V12.9a12.9 12.9 0 1 1 25.8 0v32.3z"/>
        <path fill="#ecb22e" d="M77.6 97a12.9 12.9 0 1 1-12.9 12.9V97h12.9zm0-6.5a12.9 12.9 0 1 1 0-25.8h32.3a12.9 12.9 0 1 1 0 25.8H77.6z"/>
      </svg>
      <span class="connect-arrow">⇄</span>
      <div class="app-icon">⚡</div>
    </div>

    <h1><strong>${appName}</strong> is requesting permission to access the <strong>${workspaceName}</strong> workspace</h1>

    <div class="workspace-pill">
      Workspace: <strong>${workspaceName}</strong>
    </div>

    <div class="user-info-box">
      <div class="user-info-label">Salesforce Corporate User Email</div>
      <div class="user-info-value">${email}</div>
      <div class="user-info-label" style="margin-top: 8px;">Salesforce User ID</div>
      <div class="user-info-value" style="font-family: monospace; font-size: 13px;">${sfUserId}</div>
    </div>

    <div class="permissions-section">
      <div class="permissions-title">This will allow ${appName} to:</div>
      <div class="perm-item">
        <span class="perm-icon">👤</span>
        <div><strong>View your email and member profile</strong> in workspace ${workspaceName}</div>
      </div>
      <div class="perm-item">
        <span class="perm-icon">💬</span>
        <div><strong>Open a private 1-on-1 Direct Message</strong> channel between you and the Bot</div>
      </div>
      <div class="perm-item">
        <span class="perm-icon">🤖</span>
        <div><strong>Synchronize AI Agent conversations</strong> with your Salesforce account</div>
      </div>
    </div>

    <form method="POST" action="/auth/slack/confirm" id="consentForm">
      <input type="hidden" name="sfUserId" value="${sfUserId}" />
      <input type="hidden" name="sfOrgId" value="${sfOrgId || ''}" />
      <input type="hidden" name="email" value="${email}" />
      <input type="hidden" name="decision" id="decisionInput" value="allow" />

      <div class="btn-group">
        <button type="button" class="btn-cancel" onclick="cancelConsent()">Cancel</button>
        <button type="submit" class="btn-allow" id="allowBtn" onclick="submitConsent('allow')">Allow</button>
      </div>
    </form>

    <div class="footer-note">
      By clicking <strong>Allow</strong>, your private Slack DM will be linked to Salesforce.
    </div>
  </div>

  <script>
    function submitConsent(decision) {
      document.getElementById('decisionInput').value = decision;
      var btn = document.getElementById('allowBtn');
      btn.disabled = true;
      btn.innerText = 'Connecting...';
      document.getElementById('consentForm').submit();
    }

    function cancelConsent() {
      try {
        if (window.opener) {
          window.opener.postMessage({
            type: 'SLACK_AUTH_ERROR',
            message: 'User cancelled Slack authorization.'
          }, '*');
        }
      } catch (e) {}
      window.close();
    }
  </script>
</body>
</html>`;
}

/**
 * Handles GET /auth/login
 * Flow:
 * 1. Reads sfUserId, sfOrgId, email from query.
 * 2. If Slack OAuth is configured, redirects (302) to https://slack.com/oauth/v2/authorize.
 * 3. Fallback: Renders interactive Slack OAuth Consent Screen with Allow / Cancel buttons.
 */
export async function handleAuthLogin(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
  const host = req.headers.host || 'localhost:8080';
  const proto = req.headers['x-forwarded-proto'] || 'http';
  const currentUrl = new URL(req.url || '/', `${proto}://${host}`);

  const sfUserId = currentUrl.searchParams.get('sfUserId') || '';
  const sfOrgId = currentUrl.searchParams.get('sfOrgId') || '';
  const email = currentUrl.searchParams.get('email') || '';

  if (!email && !sfUserId) {
    res.writeHead(400, { 'Content-Type': 'text/html' });
    res.end(renderAuthResultHtml(false, {
      title: 'Missing User Information',
      message: 'Both sfUserId and email query parameters are missing.'
    }));
    return;
  }

  const config = loadConfig(false);
  const slackClientId = process.env.SLACK_CLIENT_ID;

  // If SLACK_CLIENT_ID is configured, perform standard OAuth 2.0 302 redirect to Slack
  if (slackClientId && slackClientId !== 'your_slack_client_id') {
    const callbackUrl = `${proto}://${host}/auth/slack/callback`;
    const statePayload: StatePayload = {
      sfUserId,
      sfOrgId,
      email,
      ts: Date.now(),
    };
    const encodedState = encodeState(statePayload);

    const slackAuthorizeUrl = new URL('https://slack.com/oauth/v2/authorize');
    slackAuthorizeUrl.searchParams.set('client_id', slackClientId);
    slackAuthorizeUrl.searchParams.set('user_scope', 'openid,email,profile');
    slackAuthorizeUrl.searchParams.set('redirect_uri', callbackUrl);
    slackAuthorizeUrl.searchParams.set('state', encodedState);

    res.writeHead(302, { Location: slackAuthorizeUrl.toString() });
    res.end();
    return;
  }

  // Interactive Slack OAuth Consent Screen (Displays app name, user email, permissions & Allow button)
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(renderSlackConsentHtml({
    sfUserId,
    sfOrgId,
    email,
    workspaceName: 'AI Studio Agent with Slack',
    appName: 'test_agent_app'
  }));
}

/**
 * Handles POST and GET /auth/slack/confirm
 * Triggered when user clicks "Allow" on the Slack Consent screen.
 */
export async function handleAuthConfirm(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
  const host = req.headers.host || 'localhost:8080';
  const proto = req.headers['x-forwarded-proto'] || 'http';
  const currentUrl = new URL(req.url || '/', `${proto}://${host}`);

  let sfUserId = currentUrl.searchParams.get('sfUserId') || '';
  let sfOrgId = currentUrl.searchParams.get('sfOrgId') || '';
  let email = currentUrl.searchParams.get('email') || '';
  let decision = currentUrl.searchParams.get('decision') || 'allow';

  if (req.method === 'POST') {
    let body = '';
    await new Promise<void>((resolve) => {
      req.on('data', (chunk) => { body += chunk; });
      req.on('end', () => resolve());
    });

    const params = new URLSearchParams(body);
    sfUserId = params.get('sfUserId') || sfUserId;
    sfOrgId = params.get('sfOrgId') || sfOrgId;
    email = params.get('email') || email;
    decision = params.get('decision') || decision;
  }

  if (decision !== 'allow') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(renderAuthResultHtml(false, {
      title: 'Authorization Cancelled',
      message: 'You clicked cancel. No Slack account was connected.'
    }));
    return;
  }

  try {
    const result = await provisionSlackUserDirectly(email, sfUserId);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(renderAuthResultHtml(result.isSuccess, {
      title: result.isSuccess ? 'Slack Connected Successfully' : 'Authentication Failed',
      message: result.message,
      slackUserId: result.slackUserId,
      slackDmChannelId: result.slackDmChannelId,
      userName: result.userName,
    }));
  } catch (err: any) {
    res.writeHead(500, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(renderAuthResultHtml(false, {
      title: 'Handshake Error',
      message: err.message || 'An error occurred during Slack provisioning.'
    }));
  }
}

/**
 * Handles GET /auth/slack/callback
 * Flow:
 * 1. Reads code, state, error from query.
 * 2. Exchanges code with Slack API (oauth.v2.access).
 * 3. Opens 1-on-1 DM channel via conversations.open.
 * 4. Updates Salesforce User record.
 * 5. Returns self-closing HTML with window.opener.postMessage.
 */
export async function handleAuthCallback(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
  const host = req.headers.host || 'localhost:8080';
  const proto = req.headers['x-forwarded-proto'] || 'http';
  const currentUrl = new URL(req.url || '/', `${proto}://${host}`);

  const code = currentUrl.searchParams.get('code');
  const stateStr = currentUrl.searchParams.get('state');
  const error = currentUrl.searchParams.get('error');

  if (error) {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(renderAuthResultHtml(false, {
      title: 'Slack Authorization Declined',
      message: `Authorization request was denied or cancelled: ${error}`
    }));
    return;
  }

  if (!code) {
    res.writeHead(400, { 'Content-Type': 'text/html' });
    res.end(renderAuthResultHtml(false, {
      title: 'Missing Authorization Code',
      message: 'No authorization code was received from Slack.'
    }));
    return;
  }

  const state = stateStr ? decodeState(stateStr) : null;
  const config = loadConfig(false);
  const slackClientId = process.env.SLACK_CLIENT_ID || '';
  const slackClientSecret = process.env.SLACK_CLIENT_SECRET || '';
  const callbackUrl = `${proto}://${host}/auth/slack/callback`;

  try {
    // 1. Exchange OAuth code with Slack
    const tokenRes = await fetch('https://slack.com/api/oauth.v2.access', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: slackClientId,
        client_secret: slackClientSecret,
        code,
        redirect_uri: callbackUrl,
      }).toString(),
    });

    const tokenData = (await tokenRes.json()) as any;
    if (!tokenData.ok) {
      throw new Error(`Slack OAuth token exchange failed: ${tokenData.error}`);
    }

    const authedUserId = tokenData.authed_user?.id;
    if (!authedUserId) {
      throw new Error('No authed_user ID returned in Slack token response.');
    }

    // 2. Open private 1-on-1 DM channel
    const dmChannelId = await openSlackDm(config.slackBotToken || '', authedUserId);

    // 3. Update Salesforce User record
    if (state && state.sfUserId) {
      await updateSalesforceUserRecord(state.sfUserId, authedUserId, dmChannelId, state.email);
    }

    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(renderAuthResultHtml(true, {
      slackUserId: authedUserId,
      slackDmChannelId: dmChannelId,
      userName: state?.email || authedUserId,
    }));
  } catch (err: any) {
    console.error('[AuthCallback] Error:', err);
    res.writeHead(500, { 'Content-Type': 'text/html' });
    res.end(renderAuthResultHtml(false, {
      title: 'OAuth Processing Error',
      message: err.message || 'Failed to complete Slack authentication handshake.'
    }));
  }
}

/**
 * Helper: Provisions Slack User directly (lookupByEmail + conversations.open + Salesforce update).
 */
async function provisionSlackUserDirectly(email: string, sfUserId: string): Promise<{
  isSuccess: boolean;
  message: string;
  slackUserId?: string;
  slackDmChannelId?: string;
  userName?: string;
}> {
  const config = loadConfig(false);
  const botToken = config.slackBotToken || '';

  // 1. Look up Slack user by email
  const lookupRes = await fetch(`https://slack.com/api/users.lookupByEmail?email=${encodeURIComponent(email)}`, {
    headers: { Authorization: `Bearer ${botToken}` }
  });
  const lookupData = (await lookupRes.json()) as any;

  if (!lookupData.ok) {
    return {
      isSuccess: false,
      message: `Slack email "${email}" was not found in the workspace (Error: ${lookupData.error}).`
    };
  }

  const slackUserId = lookupData.user.id;
  const userName = lookupData.user.real_name || lookupData.user.name || email;

  // 2. Open private DM channel
  const dmChannelId = await openSlackDm(botToken, slackUserId);

  // 3. Update Salesforce User record if sfUserId provided
  if (sfUserId) {
    await updateSalesforceUserRecord(sfUserId, slackUserId, dmChannelId, email);
  }

  return {
    isSuccess: true,
    message: `Connected successfully as ${userName}.`,
    slackUserId,
    slackDmChannelId: dmChannelId,
    userName,
  };
}

/**
 * Helper: Calls Slack conversations.open
 */
async function openSlackDm(botToken: string, slackUserId: string): Promise<string> {
  const res = await fetch('https://slack.com/api/conversations.open', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${botToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ users: slackUserId }),
  });

  const data = (await res.json()) as any;
  if (!data.ok || !data.channel?.id) {
    throw new Error(`Could not open Slack DM channel: ${data.error || 'unknown error'}`);
  }

  return data.channel.id;
}

/**
 * Helper: Updates Salesforce User record with Slack identifiers via REST API.
 */
async function updateSalesforceUserRecord(
  sfUserId: string,
  slackUserId: string,
  dmChannelId: string,
  email: string
): Promise<void> {
  try {
    const creds = await getSalesforceCredentials();
    const endpoint = `${creds.instanceUrl.replace(/\/+$/, '')}/services/data/v61.0/sobjects/User/${sfUserId}`;

    const patchRes = await fetch(endpoint, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${creds.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        Slack_User_Id__c: slackUserId,
        Slack_DM_Channel_Id__c: dmChannelId,
        Slack_Connected_Email__c: email,
      }),
    });

    if (!patchRes.ok) {
      const err = await patchRes.text();
      console.warn(`[SalesforceUpdate] PATCH User returned HTTP ${patchRes.status}: ${err}`);
    } else {
      console.log(`[SalesforceUpdate] Successfully updated User ${sfUserId} with Slack DM ${dmChannelId}.`);
    }
  } catch (err: any) {
    console.warn(`[SalesforceUpdate] Failed to update Salesforce User: ${err.message}`);
  }
}
