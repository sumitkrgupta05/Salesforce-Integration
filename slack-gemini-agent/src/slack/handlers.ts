import { App } from '@slack/bolt';
import { agentSessionManager } from '../gemini/agent.js';
import { formatMarkdownForSlack, createSlackBlocks } from './formatters.js';

/**
 * Registers all Slack event listeners for channel mentions and direct messages.
 */
export function registerSlackHandlers(app: App): void {

  // ============================================================================
  // 1. Handle Channel Mentions (@Gemini ...)
  // ============================================================================
  app.event('app_mention', async ({ event, client, say }) => {
    console.log(`[Slack] Received app_mention from user "${event.user}" in channel "${event.channel}"`);

    // Clean user input: strip out bot's own mention tag <@U12345>
    const cleanText = (event.text || '').replace(/<@[A-Z0-9]+>/g, '').trim();

    if (!cleanText) {
      await say({
        text: 'Hi there! How can I assist you today? Mention me with your question or request.',
        thread_ts: event.thread_ts || event.ts,
      });
      return;
    }

    // Add thinking reaction to signal active processing
    const reactionTimestamp = event.ts;
    try {
      await client.reactions.add({
        channel: event.channel,
        timestamp: reactionTimestamp,
        name: 'thinking_face',
      });
    } catch (e) {
      // Ignore if reaction fails (e.g. permissions or already reacted)
    }

    // Thread session mapping: preserve conversation memory within the thread
    const threadTs = event.thread_ts || event.ts;
    const sessionId = `thread-${event.channel}-${threadTs}`;

    try {
      const replyText = await agentSessionManager.processMessage(sessionId, cleanText, async (toolName, args) => {
        console.log(`[Slack] Agent invoking tool "${toolName}" for thread: "${threadTs}"`);
      });

      const blocks = createSlackBlocks(replyText);

      await say({
        text: formatMarkdownForSlack(replyText),
        blocks,
        thread_ts: threadTs,
      });

      // Swap thinking reaction for checkmark
      try {
        await client.reactions.remove({
          channel: event.channel,
          timestamp: reactionTimestamp,
          name: 'thinking_face',
        });
        await client.reactions.add({
          channel: event.channel,
          timestamp: reactionTimestamp,
          name: 'white_check_mark',
        });
      } catch (e) {
        // Non-critical
      }
    } catch (error: any) {
      console.error('[Slack] Error handling app_mention:', error);

      let userErrorMessage = 'I encountered an unexpected issue while processing your request. Please try again in a moment.';
      if (error?.message?.includes('429') || error?.message?.includes('quota')) {
        userErrorMessage = '⏳ I am currently experiencing high request volume (rate limit). Please wait 30 seconds and try again.';
      }

      await say({
        text: `⚠️ *Error*: ${userErrorMessage}`,
        thread_ts: threadTs,
      });

      try {
        await client.reactions.remove({
          channel: event.channel,
          timestamp: reactionTimestamp,
          name: 'thinking_face',
        });
        await client.reactions.add({
          channel: event.channel,
          timestamp: reactionTimestamp,
          name: 'warning',
        });
      } catch (e) {
        // Non-critical
      }
    }
  });

  // ============================================================================
  // 2. Handle 1-on-1 Direct Messages (DMs)
  // ============================================================================
  app.message(async ({ message, client, say }) => {
    const msg = message as any;
    console.log('[Slack Message Event]:', {
      channel: msg.channel,
      channel_type: msg.channel_type,
      user: msg.user,
      text: msg.text,
      subtype: msg.subtype,
      bot_id: msg.bot_id,
    });

    // Ignore bot's own echoes
    if (msg.subtype === 'bot_message' || msg.bot_id) {
      return;
    }

    // Direct messages have channel starting with 'D' or channel_type === 'im'
    const isDirectMessage = msg.channel_type === 'im' || (typeof msg.channel === 'string' && msg.channel.startsWith('D'));
    if (!isDirectMessage) {
      return;
    }

    const cleanText = (msg.text || '').trim();
    if (!cleanText) return;

    console.log(`[Slack] Processing direct message from user "${msg.user}": "${cleanText}"`);

    const reactionTimestamp = msg.ts;
    try {
      await client.reactions.add({
        channel: msg.channel,
        timestamp: reactionTimestamp,
        name: 'thinking_face',
      });
    } catch (e) {
      // Non-critical
    }

    // For DMs, session ID maps to user DM channel
    const sessionId = `dm-${msg.channel}-${msg.user}`;

    try {
      const replyText = await agentSessionManager.processMessage(sessionId, cleanText);
      const blocks = createSlackBlocks(replyText);

      await say({
        text: formatMarkdownForSlack(replyText),
        blocks,
        ...(msg.thread_ts ? { thread_ts: msg.thread_ts } : {}),
      });

      try {
        await client.reactions.remove({
          channel: msg.channel,
          timestamp: reactionTimestamp,
          name: 'thinking_face',
        });
        await client.reactions.add({
          channel: msg.channel,
          timestamp: reactionTimestamp,
          name: 'white_check_mark',
        });
      } catch (e) {
        // Non-critical
      }
    } catch (error: any) {
      console.error('[Slack] Error handling direct message:', error);

      let userErrorMessage = 'I encountered an unexpected issue while processing your request. Please try again in a moment.';
      if (error?.message?.includes('429') || error?.message?.includes('quota')) {
        userErrorMessage = '⏳ I am currently experiencing high request volume (rate limit). Please wait 30 seconds and try again.';
      }

      await say({
        text: `⚠️ *Error*: ${userErrorMessage}`,
        ...(msg.thread_ts ? { thread_ts: msg.thread_ts } : {}),
      });

      try {
        await client.reactions.remove({
          channel: msg.channel,
          timestamp: reactionTimestamp,
          name: 'thinking_face',
        });
        await client.reactions.add({
          channel: msg.channel,
          timestamp: reactionTimestamp,
          name: 'warning',
        });
      } catch (e) {
        // Non-critical
      }
    }
  });

}
