const fs = require('fs');
const path = require('path');
const { Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell, BorderStyle, WidthType, AlignmentType, ShadingType } = require('docx');

async function generateDocx() {
  const primaryBlue = "1A73E8";
  const darkNavy = "0F172A";
  const textGrey = "334155";
  const lightBg = "F8FAFC";
  const borderGrey = "CBD5E1";

  const doc = new Document({
    creator: "Sumit Kr Gupta - Teqfocus",
    title: "Salesforce, Slack & Google AI Studio Integration Guide",
    description: "Enterprise Technical Architecture & Integration Guide",
    styles: {
      default: {
        document: {
          run: {
            font: "Segoe UI",
            size: 22, // 11pt
            color: textGrey,
          },
        },
      },
    },
    sections: [
      {
        properties: {
          page: {
            margin: {
              top: 1440, // 1 inch
              bottom: 1440,
              left: 1440,
              right: 1440,
            },
          },
        },
        children: [
          // Document Title
          new Paragraph({
            text: "Salesforce, Slack & Google AI Studio Autonomous Agent Integration",
            heading: HeadingLevel.TITLE,
            run: {
              font: "Segoe UI",
              size: 44, // 22pt
              bold: true,
              color: darkNavy,
            },
            spacing: { after: 120 },
          }),

          // Subtitle
          new Paragraph({
            text: "Enterprise-grade bidirectional technical guide connecting Slack chat interface with Google AI Studio (Gemini 3.6 Flash) autonomous reasoning and Salesforce CRM retrieval.",
            run: {
              font: "Segoe UI",
              size: 24, // 12pt
              color: "64748B",
              italics: true,
            },
            spacing: { after: 360 },
          }),

          // Metadata Table
          new Table({
            width: { size: 100, type: WidthType.PERCENTAGE },
            rows: [
              new TableRow({
                children: [
                  new TableCell({
                    width: { size: 25, type: WidthType.PERCENTAGE },
                    shading: { fill: lightBg },
                    children: [new Paragraph({ text: "Project Org", run: { bold: true, color: darkNavy } })],
                  }),
                  new TableCell({
                    width: { size: 75, type: WidthType.PERCENTAGE },
                    children: [new Paragraph("learn_dc (sumit.gupta@datacloud.com)")],
                  }),
                ],
              }),
              new TableRow({
                children: [
                  new TableCell({
                    shading: { fill: lightBg },
                    children: [new Paragraph({ text: "GCP Project", run: { bold: true, color: darkNavy } })],
                  }),
                  new TableCell({
                    children: [new Paragraph("exalted-justice-507211-v9")],
                  }),
                ],
              }),
              new TableRow({
                children: [
                  new TableCell({
                    shading: { fill: lightBg },
                    children: [new Paragraph({ text: "AI Model", run: { bold: true, color: darkNavy } })],
                  }),
                  new TableCell({
                    children: [new Paragraph("Google Gemini 3.6 Flash (via @google/genai SDK)")],
                  }),
                ],
              }),
              new TableRow({
                children: [
                  new TableCell({
                    shading: { fill: lightBg },
                    children: [new Paragraph({ text: "Slack Protocol", run: { bold: true, color: darkNavy } })],
                  }),
                  new TableCell({
                    children: [new Paragraph("Slack Socket Mode (WebSocket wss:// - Zero Public IP/Domain)")],
                  }),
                ],
              }),
              new TableRow({
                children: [
                  new TableCell({
                    shading: { fill: lightBg },
                    children: [new Paragraph({ text: "Container Runtime", run: { bold: true, color: darkNavy } })],
                  }),
                  new TableCell({
                    children: [new Paragraph("Multi-Stage Alpine Docker Container (Auto-Restart Enabled)")],
                  }),
                ],
              }),
            ],
          }),

          new Paragraph({ text: "", spacing: { after: 300 } }),

          // Section 1: Executive Summary
          new Paragraph({
            text: "1. Executive Summary & Core Objectives",
            heading: HeadingLevel.HEADING_1,
            run: { font: "Segoe UI", size: 32, bold: true, color: primaryBlue },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "This integration delivers an autonomous enterprise assistant inside Slack, powered by Google AI Studio's Gemini 3.6 Flash engine, with live tool-calling integration into Salesforce CRM (learn_dc).",
            spacing: { after: 120 },
          }),
          new Paragraph({
            text: "• Slack Chat Interface: Natural conversational user interface for channel mentions (@Gemini) and 1-on-1 Direct Messages (DMs).",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Google AI Studio Brain: Custom system prompts, conversation guidelines, safety guardrails, and autonomous Function Calling declarations.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Salesforce CRM Live Data: Pulls Account details, active CSM email (Account.CSM_Email__c), Contact roles, customer email summaries, and Google Calendar appointments.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Slack Socket Mode: Secure outbound WebSocket connection (wss://) eliminating the need for public IPs, SSL certificates, or ngrok tunnels.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Multi-Turn Thread Memory: Maps Slack thread timestamps (thread_ts) to ongoing chat sessions, allowing continuous contextual conversations without repeating context.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• 24/7 Background Container Service: Runs inside an isolated, lightweight Docker container (66.5 MB) with auto-restart policies (--restart unless-stopped) and built-in HTTP health check probes.",
            bullet: { level: 0 },
            spacing: { after: 240 },
          }),

          // Section 2: Architecture & Data Flow
          new Paragraph({
            text: "2. Architecture & Step-by-Step Data Flow",
            heading: HeadingLevel.HEADING_1,
            run: { font: "Segoe UI", size: 32, bold: true, color: primaryBlue },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "The integration follows an asynchronous event-driven pattern designed to satisfy Slack's 3-second delivery timeout while allowing LLM reasoning and CRM tool execution:",
            spacing: { after: 120 },
          }),
          new Paragraph({
            text: "1. User Interaction: A user mentions the bot in Slack or sends a Direct Message.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "2. WebSocket Ingestion: Slack delivers the event over the persistent Socket Mode WebSocket to the Slack Bolt middleware.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "3. 3-Second SLA Mitigation: Bolt immediately acknowledges the event and applies a :thinking_face: reaction to the message, confirming that processing has begun.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "4. Session Resolution: The session manager retrieves or initializes the Gemini Chat session corresponding to the Slack thread_ts.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "5. Gemini Autonomous Reasoning: The prompt and conversation history are evaluated by Gemini 3.6 Flash.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "6. Function Calling Loop: If external data is required, Gemini issues a functionCall (e.g., get_crm_account). The execution layer queries Salesforce records, packages the output into a functionResponse, and returns it to Gemini.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "7. Delivery & Presentation: Gemini synthesizes the final text, which is converted to native Slack mrkdwn and Block Kit cards. The :thinking_face: reaction is replaced with a :white_check_mark:, and the response is posted in the thread.",
            bullet: { level: 0 },
            spacing: { after: 240 },
          }),

          // Section 3: Detailed Implementation Steps
          new Paragraph({
            text: "3. Implementation Steps: How Everything Was Achieved",
            heading: HeadingLevel.HEADING_1,
            run: { font: "Segoe UI", size: 32, bold: true, color: primaryBlue },
            spacing: { before: 240, after: 120 },
          }),

          // Phase 1
          new Paragraph({
            text: "Phase 1: Google AI Studio Agent Creation & Configuration",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({
            text: "• System Prompt & Persona (src/gemini/prompt.ts): Configured the agent as 'Gemini Agent', an enterprise assistant with formatting optimized for Slack (concise bullet points, bold text, code blocks) and strict instructions not to hallucinate CRM data.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Model Selection: Configured gemini-3.6-flash, providing low latency and multi-tool reasoning capabilities.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Tool Schemas (src/gemini/tools.ts): Declared function calling schemas for get_current_time, get_crm_account, summarize_customer_thread, and schedule_calendar_meeting.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Session Management (src/gemini/agent.ts): Implemented in-memory chat session caching with TTL cleanup and exponential backoff retry for transient API demand spikes.",
            bullet: { level: 0 },
          }),

          // Phase 2
          new Paragraph({
            text: "Phase 2: Slack App Creation & Scopes",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({
            text: "• Manifest Deployment (slack-manifest.yaml / slack-manifest.json): Pre-configured with Socket Mode and App Home Messages tab enabled.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Bot Token Scopes: Granted app_mentions:read, chat:write, im:history, im:read, im:write, channels:history, groups:history, and reactions:write.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Socket Mode App Token: Generated xapp token with connections:write scope for outbound WebSocket connection.",
            bullet: { level: 0 },
          }),

          // Phase 3
          new Paragraph({
            text: "Phase 3: Middleware Integration Service (Slack Bolt)",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({
            text: "• Bolt Socket Mode App (src/index.ts): Initializes the Slack Bolt application in Socket Mode, connecting directly to Slack without requiring an ingress domain.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Event Handlers (src/slack/handlers.ts): Listens to app_mention and message (direct messages), cleans mention tags, manages reactions, and dispatches to the Gemini session manager.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Block Kit Formatter (src/slack/formatters.ts): Converts Gemini's standard markdown into Slack mrkdwn and formats responses into cards with dividers and branding.",
            bullet: { level: 0 },
          }),

          // Phase 4
          new Paragraph({
            text: "Phase 4: How Data is Fetched from Salesforce (learn_dc)",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({
            text: "• Account & CSM Lookup: When asked about an account, Gemini triggers get_crm_account. The tool extracts the Account Name, Status, Industry, and assigned Account.CSM_Email__c, along with related Contact records.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Customer Email Summaries: When asked to summarize customer communications, Gemini calls summarize_customer_thread, retrieving the AI narrative and action items generated by GmailAIService and cached in Gmail_Thread_Summary__c.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Calendar Meeting Coordination: When meeting scheduling is requested, Gemini invokes schedule_calendar_meeting, generating start/end datetimes and Google Meet video links matching the AccountCalendarController schema.",
            bullet: { level: 0 },
          }),

          // Phase 5
          new Paragraph({
            text: "Phase 5: Containerization & 24/7 Execution",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({
            text: "• Production Multi-Stage Dockerfile: Uses node:22-alpine to compile TypeScript and create an ultra-compact 66.5 MB runtime container running under a non-root user.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• Built-In HTTP Health Server: Listens on port 8080 responding 200 OK to /health, satisfying Google Cloud Run readiness/liveness requirements.",
            bullet: { level: 0 },
          }),
          new Paragraph({
            text: "• 24/7 Local Auto-Restart: Configured with --restart unless-stopped under container name slack-gemini-agent-service, ensuring continuous uptime across reboots at $0 cost.",
            bullet: { level: 0 },
            spacing: { after: 240 },
          }),

          // Section 4: Operational Commands
          new Paragraph({
            text: "4. Daily Operational Commands",
            heading: HeadingLevel.HEADING_1,
            run: { font: "Segoe UI", size: 32, bold: true, color: primaryBlue },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "To monitor and manage the active 24/7 container service from slack-gemini-agent/:",
            spacing: { after: 120 },
          }),
          new Paragraph({ text: "• npm run container:logs — Stream live chat events, tool triggers, and responses in real time.", bullet: { level: 0 } }),
          new Paragraph({ text: "• npm run container:status — Check health and uptime of the container.", bullet: { level: 0 } }),
          new Paragraph({ text: "• npm run container:restart — Restart the container service.", bullet: { level: 0 } }),
          new Paragraph({ text: "• npm run container:stop — Stop the background container.", bullet: { level: 0 } }),
          new Paragraph({ text: "• npm run container:start — Start the background container.", bullet: { level: 0 }, spacing: { after: 240 } }),

          // Section 5: Future Cloud Run Deployment
          new Paragraph({
            text: "5. Optional Google Cloud Run Deployment",
            heading: HeadingLevel.HEADING_1,
            run: { font: "Segoe UI", size: 32, bold: true, color: primaryBlue },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "If you decide to link billing to your Google Cloud project (exalted-justice-507211-v9) to claim $300 in free credits, this exact container can be deployed to Cloud Run in one command:",
            spacing: { after: 120 },
          }),
          new Paragraph({
            text: "gcloud run deploy slack-gemini-agent \\\n  --source . \\\n  --project exalted-justice-507211-v9 \\\n  --region us-central1 \\\n  --platform managed \\\n  --allow-unauthenticated \\\n  --min-instances 1 \\\n  --max-instances 2 \\\n  --memory 512Mi \\\n  --no-cpu-throttling \\\n  --set-env-vars \"GEMINI_API_KEY=YOUR_KEY,GEMINI_MODEL=gemini-3.6-flash,SLACK_BOT_TOKEN=xoxb-...,SLACK_APP_TOKEN=xapp-...,SLACK_SIGNING_SECRET=...\"",
            run: { font: "Consolas", size: 18, color: darkNavy },
            spacing: { after: 240 },
          }),

          // Section 6: From Scratch Implementation Tutorial
          new Paragraph({
            text: "6. Complete 'From-Scratch' Implementation Tutorial (Zero-to-Hero Guide)",
            heading: HeadingLevel.HEADING_1,
            run: { font: "Segoe UI", size: 32, bold: true, color: primaryBlue },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "Follow this step-by-step developer tutorial to implement the entire system from scratch on any project or org:",
            spacing: { after: 120 },
          }),

          // Step 1
          new Paragraph({
            text: "Step 1: Prerequisites & Developer Environment",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({ text: "1. Node.js (v20+ or v22+) & npm: Verify via 'node -v' and 'npm -v'.", bullet: { level: 0 } }),
          new Paragraph({ text: "2. Docker Desktop: Required for local 24/7 background container execution ('docker -v').", bullet: { level: 0 } }),
          new Paragraph({ text: "3. Slack Workspace Admin Access: Permission to create and install apps at api.slack.com/apps.", bullet: { level: 0 } }),
          new Paragraph({ text: "4. Google AI Studio Account: Free API key generated at aistudio.google.com.", bullet: { level: 0 } }),
          new Paragraph({ text: "5. Salesforce Target Org: Developer Edition, Sandbox, or Scratch Org with Account data.", bullet: { level: 0 }, spacing: { after: 180 } }),

          // Step 2
          new Paragraph({
            text: "Step 2: Initialize Project & Install Dependencies",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({ text: "Create an isolated directory and install dependencies:", spacing: { after: 80 } }),
          new Paragraph({
            text: "mkdir slack-gemini-agent && cd slack-gemini-agent\nnpm init -y\nnpm install @slack/bolt @google/genai dotenv docx\nnpm install --save-dev typescript @types/node tsx",
            run: { font: "Consolas", size: 18, color: darkNavy },
            spacing: { after: 120 },
          }),
          new Paragraph({ text: "Initialize tsconfig.json targeting ES2022 with NodeNext module resolution and dist/ outDir.", bullet: { level: 0 }, spacing: { after: 180 } }),

          // Step 3
          new Paragraph({
            text: "Step 3: Create & Configure the Slack App",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({ text: "1. Create App from Manifest: Go to api.slack.com/apps -> Create New App -> From an app manifest.", bullet: { level: 0 } }),
          new Paragraph({ text: "2. Paste Manifest: Include bot_user, app_home with messages_tab_enabled: true, and socket_mode_enabled: true.", bullet: { level: 0 } }),
          new Paragraph({ text: "3. Generate App-Level Token: Under Basic Information -> App-Level Tokens, generate a token with 'connections:write' scope (xapp-...).", bullet: { level: 0 } }),
          new Paragraph({ text: "4. Install to Workspace: Install app, then copy Bot User OAuth Token (xoxb-...) and Signing Secret.", bullet: { level: 0 } }),
          new Paragraph({ text: "5. Enable 1-on-1 Messages (Critical): Under Features -> App Home -> Messages Tab, check 'Allow users to send Slash commands and messages from the messages tab'.", bullet: { level: 0 }, spacing: { after: 180 } }),

          // Step 4
          new Paragraph({
            text: "Step 4: Configure Environment Secrets (.env)",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({ text: "Create a .env file containing:", spacing: { after: 80 } }),
          new Paragraph({
            text: "GEMINI_API_KEY=your_gemini_api_key\nGEMINI_MODEL=gemini-3.6-flash\nSLACK_BOT_TOKEN=xoxb-your-bot-token\nSLACK_APP_TOKEN=xapp-your-app-token\nSLACK_SIGNING_SECRET=your-signing-secret\nENABLE_SALESFORCE_TOOLS=true",
            run: { font: "Consolas", size: 18, color: darkNavy },
            spacing: { after: 180 },
          }),

          // Step 5
          new Paragraph({
            text: "Step 5: Implement the Core Application Files",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({ text: "• src/config.ts: Loads and validates environment variables on startup.", bullet: { level: 0 } }),
          new Paragraph({ text: "• src/gemini/prompt.ts: System prompt defining persona, Slack-friendly formatting rules, and guardrails against hallucinating CRM data.", bullet: { level: 0 } }),
          new Paragraph({ text: "• src/gemini/tools.ts: Function calling JSON schemas for get_current_time, get_crm_account, summarize_customer_thread, and schedule_calendar_meeting.", bullet: { level: 0 } }),
          new Paragraph({ text: "• src/gemini/agent.ts: Chat session manager mapping thread_ts to chats.create(), autonomous tool execution loop, and exponential backoff retry.", bullet: { level: 0 } }),
          new Paragraph({ text: "• src/slack/formatters.ts: Translates markdown to Slack mrkdwn and wraps output into interactive Block Kit cards.", bullet: { level: 0 } }),
          new Paragraph({ text: "• src/slack/handlers.ts: Listens to app_mention and message (direct messages), handles :thinking_face: SLA reaction, and delivers replies.", bullet: { level: 0 } }),
          new Paragraph({ text: "• src/index.ts: Initializes Bolt in Socket Mode and binds an HTTP health check server on port 8080 (0.0.0.0:8080/health).", bullet: { level: 0 }, spacing: { after: 180 } }),

          // Step 6
          new Paragraph({
            text: "Step 6: Test & Verify Locally",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({ text: "1. CLI Sanity Test: Run 'npm run test:agent' to verify prompt reasoning, tool calling, and multi-turn memory without Slack.", bullet: { level: 0 } }),
          new Paragraph({ text: "2. Local Dev Mode: Run 'npm run dev' to connect to Slack in real-time.", bullet: { level: 0 } }),
          new Paragraph({ text: "3. Test in Slack: Send 1-on-1 DM ('Hi! Who are you?') and test tool execution ('Look up details for Acme Corp').", bullet: { level: 0 }, spacing: { after: 180 } }),

          // Step 7
          new Paragraph({
            text: "Step 7: Containerize for 24/7 Production Execution",
            heading: HeadingLevel.HEADING_2,
            run: { font: "Segoe UI", size: 26, bold: true, color: darkNavy },
            spacing: { before: 180, after: 80 },
          }),
          new Paragraph({ text: "Build the multi-stage Alpine Docker container and launch with auto-restart:", spacing: { after: 80 } }),
          new Paragraph({
            text: "docker build -t slack-gemini-agent:latest .\ndocker run -d --name slack-gemini-agent-service --restart unless-stopped -p 8080:8080 --env-file .env slack-gemini-agent:latest",
            run: { font: "Consolas", size: 18, color: darkNavy },
            spacing: { after: 120 },
          }),
          new Paragraph({ text: "The container service will run 24/7 in the background, automatically resuming after computer reboots with zero cloud costs!", bullet: { level: 0 }, spacing: { after: 240 } }),

          // Section 7: Salesforce-Hosted MCP Integration
          new Paragraph({
            text: "7. Native Salesforce-Hosted MCP Integration (Model Context Protocol)",
            heading: HeadingLevel.HEADING_1,
            run: { font: "Segoe UI", size: 32, bold: true, color: primaryBlue },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "Salesforce now provides managed Hosted MCP Servers configured directly in Salesforce Setup, enabling standard JSON-RPC 2.0 over Server-Sent Events (SSE):",
            spacing: { after: 120 },
          }),
          new Paragraph({ text: "• Setup Configuration: Go to Setup -> MCP Server -> New Custom MCP Server, name it (e.g. LearnDC_Agent_MCP_Server), and curate the tools (Account, Contact, Event, Gmail_Thread_Summary__c, and Apex actions).", bullet: { level: 0 } }),
          new Paragraph({ text: "• Dynamic Tool Discovery: On startup, the agent calls listTools() against the Salesforce MCP endpoint over SSE. It automatically discovers and binds all configured tools into Gemini without code modifications.", bullet: { level: 0 } }),
          new Paragraph({ text: "• Built-In Resiliency: If SF_MCP_ENDPOINT_URL is not configured, the bot automatically continues running using its built-in CRM tools, ensuring zero downtime.", bullet: { level: 0 } }),
          new Paragraph({ text: "• Diagnostics: Run 'npm run test:mcp' to verify session credentials with learn_dc and test tool discovery.", bullet: { level: 0 }, spacing: { after: 240 } }),
        ],
      },
    ],
  });

  const buffer = await Packer.toBuffer(doc);
  
  // Save both .docx and .docs in workspace root for sharing
  const docxPath = path.resolve(__dirname, '../../SALESFORCE_SLACK_GOOGLE_AI_STUDIO_INTEGRATION.docx');
  const docsPath = path.resolve(__dirname, '../../SALESFORCE_SLACK_GOOGLE_AI_STUDIO_INTEGRATION.docs');

  fs.writeFileSync(docxPath, buffer);
  fs.writeFileSync(docsPath, buffer);

  console.log(`✅ Word document generated successfully:`);
  console.log(`   - ${docxPath}`);
  console.log(`   - ${docsPath}`);
}

generateDocx().catch(console.error);
