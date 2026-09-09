import { App } from '@slack/bolt';
import { salesforceMcpClient } from '../mcp/salesforceMcpClient.js';
import { snowflakeMcpClient } from '../mcp/snowflakeMcpClient.js';

/**
 * Registers Slash Commands for the Slack Bot.
 * Socket Mode delivers these directly across WebSocket without requiring public webhooks.
 */
export function registerSlashCommands(app: App): void {

  // ===========================================================================
  // 1. /account-brief [Account Name]
  // ===========================================================================
  app.command('/account-brief', async ({ command, ack, respond }) => {
    // Rule 1: Acknowledge within 3000ms to prevent Slack timeout
    await ack();

    const accountName = (command.text || '').trim();
    if (!accountName) {
      await respond({
        response_type: 'ephemeral',
        text: '⚠️ *Usage*: `/account-brief [Account Name]`\n*Example*: `/account-brief Edge Communications`',
      });
      return;
    }

    try {
      console.log(`[SlashCommand] /account-brief invoked by user "${command.user_id}" for: "${accountName}"`);

      // 1. Query Account & Contact Details via LearnDC MCP Action
      const acc = await salesforceMcpClient.callTool('LearnDCMCPAccountAction', {
        accountIdentifier: accountName,
      });

      if (!acc || !acc.isFound) {
        await respond({
          response_type: 'ephemeral',
          text: `I am unable to generate an account brief because no Account matching "${accountName}" was found. Please verify the account name.`,
        });
        return;
      }

      // 2. Query Recent Customer Email Intelligence via LearnDCMCPThreadAction
      let emailIntelligenceSection = '• No recent customer communications logged for this account.';
      try {
        const th = await salesforceMcpClient.callTool('LearnDCMCPThreadAction', {
          accountIdentifier: acc.accountName,
        });

        if (th && th.isFound && th.executiveSummary) {
          emailIntelligenceSection = 
            `*Executive Summary:*\n${th.executiveSummary}\n\n` +
            `*Action Items:*\n${th.actionItems || 'None pending.'}`;
        }
      } catch (thErr: any) {
        console.warn(`[SlashCommand] Thread summary query notice: ${thErr.message}`);
      }

      // 3. Query Account Telemetry via Snowflake MCP Secure View
      let telemetry: any = null;
      try {
        telemetry = await snowflakeMcpClient.callTool('snowflake_get_account_telemetry', {
          accountIdentifier: acc.accountName,
        });
      } catch (snowErr: any) {
        console.warn(`[SlashCommand] Snowflake MCP query notice: ${snowErr.message}`);
      }

      // 4. Render Unified Single-Format Dossier (Zero Platform Branding)
      const blocks: any[] = [
        {
          type: 'header',
          text: {
            type: 'plain_text',
            text: `📋 Account Dossier: ${acc.accountName}`,
            emoji: true,
          },
        },
        {
          type: 'section',
          fields: [
            { type: 'mrkdwn', text: `*Primary Contact:*\n${acc.primaryContactName || 'None'}` },
            { type: 'mrkdwn', text: `*Contact Email:*\n${acc.primaryContactEmail || 'None'}` },
            { type: 'mrkdwn', text: `*Account Manager:*\n${acc.csmEmail || 'None assigned'}` },
            { type: 'mrkdwn', text: `*Industry:*\n${acc.industry || 'Technology'}` },
          ],
        },
      ];

      if (acc.contactSummary) {
        blocks.push({
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*👥 Key Account Contacts:*\n${acc.contactSummary.replace(/\|/g, '\n•')}`,
          },
        });
      }

      // Section: Health & Platform Utilization
      if (telemetry && telemetry.isFound) {
        const rating = (telemetry.healthScore || 0) >= 80 ? '🟢 EXCELLENT' : (telemetry.healthScore || 0) >= 60 ? '🟡 FAIR' : '🔴 AT RISK';
        blocks.push({ type: 'divider' });
        blocks.push({
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*📊 Account Health & Platform Utilization:*\n` +
              `• *Health Rating*: *${telemetry.healthScore || 85} / 100* (${rating})\n` +
              `• *Monthly Platform Usage*: *${telemetry.usageHours || 0}* Compute Hours\n` +
              `• *Account Risk Level*: *${telemetry.churnRisk || 'LOW'}*\n` +
              `• *Support Entitlement*: *${telemetry.slaTier || 'Standard'}*`,
          },
        });
      }

      // Section: Recent Activity & Communication
      blocks.push({ type: 'divider' });
      blocks.push({
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*📝 Recent Activity & Communication:*\n${emailIntelligenceSection}`,
        },
      });

      // Unified Context Footer (Clean, no technical platform names)
      blocks.push({
        type: 'context',
        elements: [
          {
            type: 'mrkdwn',
            text: `Unified Account Intelligence • Up to date`,
          },
        ],
      });

      await respond({
        response_type: 'in_channel',
        blocks,
      });

    } catch (err: any) {
      console.error('[SlashCommand] Error executing /account-brief:', err);
      await respond({
        response_type: 'ephemeral',
        text: `I am unable to complete this request because an error occurred: ${err.message}`,
      });
    }
  });

  // ===========================================================================
  // 2. /summarize-thread [Thread ID]
  // ===========================================================================
  app.command('/summarize-thread', async ({ command, ack, respond }) => {
    // Rule 1: Acknowledge within 3000ms
    await ack();

    const threadId = (command.text || '').trim();
    if (!threadId) {
      await respond({
        response_type: 'ephemeral',
        text: '⚠️ *Usage*: `/summarize-thread [Thread ID]`\n*Example*: `/summarize-thread 18f52b618a8039d9`',
      });
      return;
    }

    try {
      console.log(`[SlashCommand] /summarize-thread invoked for: "${threadId}"`);

      // Call LearnDCMCPThreadAction with dynamic threadId
      const th = await salesforceMcpClient.callTool('LearnDCMCPThreadAction', {
        threadId: threadId,
      });

      if (!th || !th.isFound || !th.executiveSummary) {
        await respond({
          response_type: 'ephemeral',
          text: `I am unable to complete this request because no email messages or records were found in Salesforce for Thread ID "${threadId}". Please verify the Thread ID or ensure customer email synchronization has been completed.`,
        });
        return;
      }

      // Render Dynamic Summary Card in Slack
      const blocks: any[] = [
        {
          type: 'header',
          text: {
            type: 'plain_text',
            text: `⚡ Gemini AI Thread Summary: ${th.threadId}`,
            emoji: true,
          },
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*Executive Summary:*\n${th.executiveSummary}`,
          },
        },
      ];

      if (th.keyPoints) {
        blocks.push({
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*💡 Key Discussion Points:*\n${th.keyPoints}`,
          },
        });
      }

      if (th.actionItems) {
        blocks.push({
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*✅ Action Items:*\n${th.actionItems}`,
          },
        });
      }

      blocks.push({
        type: 'context',
        elements: [
          {
            type: 'mrkdwn',
            text: `Dynamic synthesis via Google Gemini • Messages analyzed: ${th.messageCount || 1}`,
          },
        ],
      });

      await respond({
        response_type: 'in_channel',
        blocks,
      });

    } catch (err: any) {
      console.error('[SlashCommand] Error executing /summarize-thread:', err);
      await respond({
        response_type: 'ephemeral',
        text: `I am unable to complete this request because an error occurred: ${err.message}`,
      });
    }
  });

  console.log('⚡️ Registered 2 Slack Slash Commands: [/account-brief, /summarize-thread]');
}
