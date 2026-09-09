import { App } from '@slack/bolt';
import { agentSessionManager } from '../gemini/agent.js';

export interface GatewayChatRequest {
  sessionId: string;
  userMessage: string;
  accountId?: string;
  accountName?: string;
  userName?: string;
  threadTs?: string;
  slackChannel?: string;
  slackUserId?: string;
}

export interface GatewayChatResponse {
  isSuccess: boolean;
  messageText: string;
  slackThreadUrl?: string;
  threadTs?: string;
  errorMessage?: string;
}

/**
 * Handles incoming chat requests from the Salesforce LWC (slackBotAgent).
 * Posts the user's inquiry to Slack, executes the Gemini Agent with MCP tools,
 * posts the reply as a thread in Slack (creating permanent history), and returns
 * the response to Salesforce.
 */
export async function handleLwcChatRequest(
  app: App,
  payload: GatewayChatRequest
): Promise<GatewayChatResponse> {
  const channel = payload.slackChannel || process.env.SLACK_DEFAULT_CHANNEL || 'D0BUQS5V68Z'; // Dynamic per-user DM channel or fallback
  const userName = payload.userName || 'Salesforce User';
  const accountName = payload.accountName || 'Active Account';
  const accountId = payload.accountId || '';

  let threadTs: string | undefined = payload.threadTs;
  let slackThreadUrl: string | undefined;

  try {
    // 1. Post User Query to Slack to establish permanent thread in history or reply in existing thread
    try {
      const slackUserPost = await app.client.chat.postMessage({
        channel,
        ...(threadTs ? { thread_ts: threadTs } : {}),
        text: `👤 *${userName}* (via Salesforce LWC) on *${accountName}*:\n> ${payload.userMessage}`,
      });
      if (!threadTs) {
        threadTs = slackUserPost.ts;
      }
      slackThreadUrl = buildSlackThreadUrl(channel, threadTs);
    } catch (slackErr: any) {
      console.warn(`[Gateway] Notice: Could not post user message to Slack (${slackErr.message}). Proceeding with agent execution.`);
    }

    // 2. Execute Gemini Agent with Account context & LearnDC MCP Tools
    const enrichedPrompt = `[Context: Viewing Account "${accountName}", ID: "${accountId}"]\n${payload.userMessage}`;
    console.log(`[Gateway] Forwarding LWC inquiry to Gemini Agent for session "${payload.sessionId}"...`);

    const agentReply = await agentSessionManager.processMessage(
      payload.sessionId || `lwc-${accountId}-${Date.now()}`,
      enrichedPrompt
    );

    // 3. Post Agent Reply in Slack as a Thread Reply (Permanent History)
    if (threadTs) {
      try {
        await app.client.chat.postMessage({
          channel,
          thread_ts: threadTs,
          text: agentReply,
        });
        console.log(`[Gateway] Successfully preserved conversation thread in Slack: ${slackThreadUrl}`);
      } catch (slackReplyErr: any) {
        console.warn(`[Gateway] Notice: Could not post agent reply to Slack thread: ${slackReplyErr.message}`);
      }
    }

    return {
      isSuccess: true,
      messageText: agentReply,
      slackThreadUrl,
      threadTs,
    };
  } catch (err: any) {
    console.error(`[Gateway] Error processing LWC request:`, err);
    return {
      isSuccess: false,
      messageText: `I am unable to complete this request because the Slack Bot Agent encountered an error: ${err.message}`,
      errorMessage: err.message,
    };
  }
}

/**
 * Generates the official Slack web and desktop direct thread archive permalink.
 */
export function buildSlackThreadUrl(channel: string, threadTs?: string): string {
  if (!threadTs) {
    return `https://slack.com/app_redirect?channel=${channel}`;
  }
  const pTs = threadTs.replace('.', '');
  return `https://slack.com/archives/${channel}/p${pTs}?thread_ts=${threadTs}&cid=${channel}`;
}
