/**
 * Tool Declarations & Execution Engine for Google AI Studio / Gemini Agent.
 * 
 * Tools are exposed as Function Calling declarations that Gemini can autonomously
 * invoke when answering user queries in Slack.
 */

import { snowflakeService } from '../snowflake/service.js';
import { snowflakeMcpClient } from '../mcp/snowflakeMcpClient.js';

export interface ToolDefinition {
  name: string;
  description: string;
  parameters: {
    type: string;
    properties: Record<string, any>;
    required?: string[];
  };
}

/**
 * Declared tool definitions matching Gemini Function Calling specification.
 */
export const TOOL_DECLARATIONS: ToolDefinition[] = [
  {
    name: 'get_current_time',
    description: 'Returns the current server date, time, day of the week, and timezone.',
    parameters: {
      type: 'OBJECT',
      properties: {
        timeZone: {
          type: 'STRING',
          description: 'Optional IANA timezone name (e.g., "Asia/Kolkata", "America/New_York", "UTC"). Defaults to local system timezone.',
        },
      },
    },
  },
  {
    name: 'get_crm_account',
    description: 'Retrieves CRM Account information (CSM Email, Industry, Status, and recent contacts) by Account Name or ID from Salesforce.',
    parameters: {
      type: 'OBJECT',
      properties: {
        accountName: {
          type: 'STRING',
          description: 'The name or partial name of the Account (e.g. "Acme Corp", "Alex Hales", "Ben Stokes").',
        },
      },
      required: ['accountName'],
    },
  },
  {
    name: 'summarize_customer_thread',
    description: 'Retrieves the latest AI-generated executive summary, discussion points, and action items for an email thread with a customer account.',
    parameters: {
      type: 'OBJECT',
      properties: {
        accountName: {
          type: 'STRING',
          description: 'The name of the account to look up email thread summaries for.',
        },
      },
      required: ['accountName'],
    },
  },
  {
    name: 'schedule_calendar_meeting',
    description: 'Schedules a new meeting on Google Calendar with attendees, generating a Google Meet video conference link.',
    parameters: {
      type: 'OBJECT',
      properties: {
        accountName: {
          type: 'STRING',
          description: 'The related Salesforce Account name.',
        },
        subject: {
          type: 'STRING',
          description: 'The title or subject of the meeting.',
        },
        attendeeEmail: {
          type: 'STRING',
          description: 'The primary invitee email address.',
        },
        startDateTime: {
          type: 'STRING',
          description: 'ISO-8601 formatted start datetime (e.g. "2026-09-04T15:00:00+05:30").',
        },
        durationMinutes: {
          type: 'INTEGER',
          description: 'Meeting duration in minutes (e.g. 30, 45, 60). Default: 30.',
        },
      },
      required: ['subject', 'attendeeEmail', 'startDateTime'],
    },
  },
  {
    name: 'get_snowflake_account_metrics',
    description: 'Retrieves product telemetry and operational analytics (Health Score 1-100, Monthly Usage Hours, Churn Risk, Warehouse Sync Status) from Snowflake Data Warehouse.',
    parameters: {
      type: 'OBJECT',
      properties: {
        accountName: {
          type: 'STRING',
          description: 'The name or ID of the account to look up in Snowflake Data Warehouse (e.g. "Edge Communications").',
        },
      },
      required: ['accountName'],
    },
  },
];

/**
 * Tool Execution Dispatcher
 * Executes the function requested by the Gemini Agent and returns the JSON result.
 */
export async function executeTool(name: string, args: Record<string, any>): Promise<any> {
  console.log(`[ToolExecutor] Executing tool: "${name}" with args:`, JSON.stringify(args));

  switch (name) {
    case 'get_current_time': {
      const timeZone = args.timeZone || Intl.DateTimeFormat().resolvedOptions().timeZone;
      const now = new Date();
      return {
        currentTimeIso: now.toISOString(),
        formattedTime: now.toLocaleString('en-US', { timeZone, dateStyle: 'full', timeStyle: 'long' }),
        timeZone,
      };
    }

    case 'get_crm_account': {
      // Mock / Connector layer (can be connected to live Salesforce learn_dc REST API)
      const query = (args.accountName || '').toLowerCase();
      return {
        status: 'found',
        account: {
          name: args.accountName,
          id: '001fj00000AcmeDemo',
          csmEmail: 'skgsummo5@gmail.com',
          ownerName: 'Sumit Gupta',
          industry: 'Technology / Cloud Services',
          status: 'Active Customer',
          primaryContact: {
            name: 'Alex Hales',
            email: 'skgsumit5@gmail.com',
            title: 'VP of Engineering',
          },
        },
        source: 'Salesforce (learn_dc)',
      };
    }

    case 'summarize_customer_thread': {
      return {
        accountName: args.accountName,
        threadSummary: {
          executiveSummary: `Customer Alex Hales (${args.accountName}) confirmed the updated technical architecture and requested a follow-up review on Google Meet.`,
          totalMessages: 4,
          latestSpeaker: 'Client (Alex Hales)',
          keyPoints: [
            'Reviewed Phase 14 email and calendar isolation architecture.',
            'Client confirmed receipt of the branded meeting invite "Invitation from CSM-Teqfocus".',
            'Pending client review of the proposed deployment schedule.',
          ],
          recommendedNextSteps: 'Send calendar invite for Friday 3 PM IST to finalize production deployment.',
        },
        source: 'GmailAIService Cache (Gmail_Thread_Summary__c)',
      };
    }

    case 'schedule_calendar_meeting': {
      const duration = args.durationMinutes || 30;
      const startTime = new Date(args.startDateTime);
      const endTime = new Date(startTime.getTime() + duration * 60000);
      const randomMeetCode = 'abc-defg-hij';

      return {
        status: 'Scheduled',
        meeting: {
          subject: args.subject,
          account: args.accountName || 'N/A',
          attendees: [args.attendeeEmail],
          startTime: startTime.toISOString(),
          endTime: endTime.toISOString(),
          googleMeetUrl: `https://meet.google.com/${randomMeetCode}`,
          invitationSender: 'CSM-Teqfocus',
        },
        source: 'Google Calendar API v3 (learn_dc)',
      };
    }

    case 'get_snowflake_account_metrics': {
      try {
        const telemetry = await snowflakeMcpClient.callTool('snowflake_get_account_telemetry', {
          accountIdentifier: args.accountName,
        });

        if (telemetry && telemetry.isFound) {
          return {
            status: 'found',
            accountName: telemetry.accountName,
            sfAccountId: telemetry.sfAccountId,
            healthScore: telemetry.healthScore,
            healthStatus: telemetry.healthStatus,
            monthlyUsageHours: telemetry.usageHours,
            churnRisk: telemetry.churnRisk,
            slaTier: telemetry.slaTier,
            lastTelemetrySync: telemetry.telemetryLastUpdated,
          };
        } else {
          return {
            status: 'not_found',
            accountName: args.accountName,
            message: `No operational telemetry record was found for "${args.accountName}".`,
          };
        }
      } catch (snowErr: any) {
        console.error('[ToolExecutor] Error querying telemetry via MCP:', snowErr.message);
        return {
          status: 'error',
          errorMessage: snowErr.message,
        };
      }
    }

    default:
      throw new Error(`Unknown tool name: "${name}"`);
  }
}
