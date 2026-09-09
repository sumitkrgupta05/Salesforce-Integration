# Salesforce, Slack & Google AI Studio Autonomous Agent Integration

A complete, enterprise-grade technical guide and implementation documentation detailing the end-to-end integration between **Slack**, **Google AI Studio (Gemini 3.6 Flash)**, and **Salesforce CRM (`learn_dc`)**.

---

## 1. Executive Summary & Objective

This integration connects **Slack** as a conversational chat interface to an autonomous **Google AI Studio Custom Agent** that reasons, triggers tools, and retrieves live data from the **Salesforce `learn_dc`** CRM environment.

### Core Capabilities:
1. **Slack Conversational Interface**: Team members interact with the bot in public/private channels (`@Gemini`) and 1-on-1 Direct Messages (DMs).
2. **Google AI Studio Brain (Gemini 3.6 Flash)**: Employs system instructions, reasoning, and native **Function Calling** to understand natural language intent.
3. **Autonomous Salesforce CRM Retrieval**: Pulls live Account details, CSM assignments (`Account.CSM_Email__c`), Contacts, customer email summaries, and Google Calendar meetings.
4. **Slack Socket Mode (`wss://`)**: Outbound WebSocket architecture eliminating public IPs, open firewall ports, SSL certificates, or `ngrok` tunnels.
5. **Multi-Turn Thread Continuity**: Automatically binds Slack thread timestamps (`thread_ts`) to ongoing Gemini chat sessions for natural, contextual dialogues.
6. **24/7 Containerized Runtime**: Multi-stage Docker container with automatic restart policies (`--restart unless-stopped`) and built-in HTTP health check probes.

---

## 2. Architecture & Data Flow

```mermaid
graph TD
    subgraph "Slack Collaboration Workspace"
        User["Slack User"]
        Channel["Slack Channel / DM / Thread"]
        SlackPlatform["Slack API Engine<br/>(Socket Mode Gateway)"]
    end

    subgraph "Middleware Service (slack-gemini-agent)"
        BoltApp["Slack Bolt Framework<br/>(WebSocket Listener)"]
        SessionMgr["Session Manager<br/>(thread_ts ➔ Gemini Chat Session)"]
        Formatter["Slack Block Kit Formatter<br/>(Markdown ➔ Slack mrkdwn)"]
        ToolRouter["Tool Dispatcher & Executor<br/>(Autonomous Function Loop)"]
        HealthServer["HTTP Health Server<br/>(0.0.0.0:8080 /health)"]
    end

    subgraph "Google AI Studio & Gemini API"
        GeminiModel["Gemini 3.6 Flash Engine<br/>(System Instructions + Tools)"]
    end

    subgraph "Salesforce Org (learn_dc)"
        AccountObj["Account Record<br/>(CSM_Email__c, Status)"]
        ContactObj["Contact Records<br/>(Email, Title)"]
        EmailSummaryObj["Gmail_Thread_Summary__c<br/>(AI Narrative & Action Items)"]
        EventObj["Standard Event Object<br/>(Google Meet & Meetings)"]
    end

    %% User Interaction Flow
    User -->|"1. Types message or @mention"| Channel
    Channel -->|"2. Dispatches event via WSS"| SlackPlatform
    SlackPlatform -->|"3. Delivers payload to WebSocket"| BoltApp

    %% 3-Second SLA Mitigation
    BoltApp -->|"4. Immediate ACK + reacts ⏳"| SlackPlatform
    
    %% Session & AI Reasoning
    BoltApp -->|"5. Resolve session history"| SessionMgr
    SessionMgr -->|"6. Send prompt + conversation history"| GeminiModel
    
    %% Function Calling Loop
    GeminiModel -->|"7. Returns functionCalls (e.g. get_crm_account)"| ToolRouter
    ToolRouter -->|"8. Queries CRM data"| AccountObj
    ToolRouter -->|"8. Queries CRM data"| ContactObj
    ToolRouter -->|"8. Queries email summary"| EmailSummaryObj
    ToolRouter -->|"9. Return tool output (functionResponse)"| GeminiModel
    
    %% Response Delivery
    GeminiModel -->|"10. Final synthesized answer"| SessionMgr
    SessionMgr -->|"11. Converts to Block Kit"| Formatter
    Formatter -->|"12. Removes ⏳, adds ✅, posts thread reply"| SlackPlatform
    SlackPlatform -->|"13. Renders rich card in thread"| User
```

---

## 3. Step-by-Step Implementation Breakdown

### Phase 1: Google AI Studio Agent Creation & Configuration

1. **System Prompt & Persona Design (`src/gemini/prompt.ts`)**:
   - Defined the persona: **Gemini Agent**, a concise, proactive Enterprise Assistant operating inside Slack.
   - Enforced Slack formatting rules: clean bullet points, bold headers, inline code tags, and short paragraphs.
   - Configured guardrails against hallucinating CRM data or scheduling conflicts.

2. **Model Selection**:
   - Configured with `gemini-3.6-flash` (recommended current model for low-latency chat and multi-tool reasoning).

3. **Tool Declarations & Function Calling Schemas (`src/gemini/tools.ts`)**:
   Defined JSON Schema parameter specifications that Gemini autonomously selects:
   - **`get_current_time`**: Real-time server and timezone date/time queries.
   - **`get_crm_account`**: Queries Salesforce Account, CSM email, status, and contacts.
   - **`summarize_customer_thread`**: Pulls customer email narrative summaries and action items.
   - **`schedule_calendar_meeting`**: Books calendar appointments with Google Meet links.

4. **Autonomous Function Calling Loop & Resilience (`src/gemini/agent.ts`)**:
   - Built a dynamic loop: when Gemini requests a tool, the engine executes it, wraps the result in a `functionResponse`, and sends it back to the model until a final text answer is produced.
   - Added exponential backoff retry logic to smoothly handle transient API demand spikes.
   - Implemented an in-memory session cache with TTL cleanup to prevent memory leaks across long-running threads.

---

### Phase 2: Slack App Creation & Permissions Setup

1. **Created Slack App via Manifest (`slack-manifest.yaml` / `slack-manifest.json`)**:
   - App Name: `Gemini Agent` (or `test_agent_app`).
   - Enabled **Socket Mode** (`socket_mode_enabled: true`).
   - Enabled **Messages Tab** (`messages_tab_enabled: true`, `messages_tab_read_only_enabled: false`) to permit 1-on-1 Direct Messaging.

2. **Configured Bot Token Scopes**:
   - `app_mentions:read`: Listen to `@mention` in channels.
   - `chat:write`: Post messages and replies.
   - `im:history`, `im:read`, `im:write`: Direct message thread history and responses.
   - `channels:history`, `groups:history`: Channel message thread context.
   - `reactions:write`: Add `:thinking_face:` and `:white_check_mark:` status indicators.

3. **Obtained Required Tokens in `.env`**:
   - `SLACK_BOT_TOKEN`: `xoxb-...` (Bot User OAuth Token).
   - `SLACK_APP_TOKEN`: `xapp-...` (App-Level Token with `connections:write`).
   - `SLACK_SIGNING_SECRET`: Secret for verifying Slack signatures.

---

### Phase 3: Middleware Integration Service (Slack Bolt)

1. **Slack Socket Mode Listener (`src/index.ts`)**:
   - Uses `@slack/bolt` with `socketMode: true`.
   - Connects over an outbound WebSocket (`wss://`) to Slack's servers, eliminating the need for public IP addresses, domain names, or reverse proxy tunnels like `ngrok`.

2. **3-Second SLA Mitigation (`src/slack/handlers.ts`)**:
   - Slack mandates that event delivery be acknowledged within 3 seconds.
   - The handler immediately acknowledges the event and adds a `:thinking_face:` emoji reaction to the user's message, letting the user know the AI is actively working.

3. **Multi-Turn Thread Continuity**:
   - Maps each Slack `thread_ts` to a unique Gemini chat session (`thread-{channel}-{thread_ts}`).
   - Direct messages use `dm-{channel}-{user}`.
   - Follow-up questions in the same thread preserve full conversational memory without needing to restate context.

4. **Slack mrkdwn & Block Kit Formatter (`src/slack/formatters.ts`)**:
   - Automatically translates standard markdown (`**bold**`, `[link](url)`, `### headers`) into Slack-native `mrkdwn`.
   - Packages responses into structured Block Kit cards with subtle divider lines and branding footers.

---

### Phase 4: How the Agent Fetches Data from Salesforce

The agent interacts with Salesforce CRM (`learn_dc`) through declared function calls:

```mermaid
sequenceDiagram
    autonumber
    actor User as Slack User
    participant Slack as Slack App
    participant Bolt as Bolt Middleware
    participant Gemini as Gemini 3.6 Flash
    participant SF as Salesforce Org (learn_dc)

    User->>Slack: "@Gemini check CRM details for Acme Corp"
    Slack->>Bolt: Delivers app_mention event over WebSocket
    Bolt->>Slack: Adds :thinking_face: reaction
    Bolt->>Gemini: Sends user prompt + tool declarations
    Note over Gemini: Gemini evaluates declared tools
    Gemini-->>Bolt: Emits functionCall: get_crm_account(accountName: "Acme Corp")
    Bolt->>SF: Queries Account (CSM_Email__c, Contacts, Status)
    SF-->>Bolt: Returns Account JSON payload
    Bolt->>Gemini: Feeds functionResponse back to chat
    Note over Gemini: Gemini synthesizes the Salesforce data
    Gemini-->>Bolt: Returns final structured answer
    Bolt->>Slack: Swaps reaction to :white_check_mark: & posts Block Kit reply
    Slack-->>User: Displays Account card with CSM & Contact details
```

1. **User asks natural language question**: e.g., *"Who is the assigned CSM and primary contact for Acme Corp?"*
2. **Gemini analyzes intent**: Matches intent to `get_crm_account(accountName: "Acme Corp")`.
3. **Execution layer queries Salesforce**:
   - Reads Account Name, Status, Industry, and assigned `Account.CSM_Email__c`.
   - Pulls related `Contact` records (Name, Email, Title).
   - If requested, queries `Gmail_Thread_Summary__c` for executive email summaries.
4. **Gemini synthesizes the payload**: Converts raw CRM records into a clean, actionable summary for the user in Slack.

---

### Phase 5: Containerization & 24/7 Background Hosting

1. **Multi-Stage Dockerfile (`Dockerfile`)**:
   - Stage 1 (Builder): Installs dependencies and compiles TypeScript with `tsc`.
   - Stage 2 (Runner): Lightweight Alpine Linux image (`node:22-alpine`) copying only production dependencies and compiled JavaScript (`dist/`).
   - Image footprint: **66.5 MB**.
   - Runs as non-root user `node` for enterprise security.

2. **Cloud Run & Health Check Probes**:
   - Built-in HTTP server listening on `0.0.0.0:8080`.
   - `GET /health` returns HTTP 200:
     ```json
     {
       "status": "healthy",
       "service": "slack-gemini-agent",
       "runtime": "Google Cloud Run",
       "model": "gemini-3.6-flash",
       "uptimeSeconds": 1018,
       "timestamp": "2026-09-03T07:47:01.457Z"
     }
     ```

3. **24/7 Local Execution with Auto-Restart Policy**:
   - Started with `--restart unless-stopped` under container name **`slack-gemini-agent-service`**.
   - Automatically restarts on system reboot or Docker Desktop restart without manual intervention.

---

## 4. Directory & File Structure

```
Learn DC/
├── force-app/                                           # Existing Salesforce Org Metadata (Untouched)
├── SALESFORCE_GMAIL_INTEGRATION.md                      # Existing Gmail Integration Documentation
├── SALESFORCE_GOOGLE_CALENDAR_INTEGRATION.md            # Existing Google Calendar Documentation
├── SALESFORCE_SLACK_GOOGLE_AI_STUDIO_INTEGRATION.md     # This Documentation File
├── SALESFORCE_SLACK_GOOGLE_AI_STUDIO_INTEGRATION.docx   # Microsoft Word Version for Sharing
└── slack-gemini-agent/                                  # Isolated Slack Gemini Agent Module
    ├── Dockerfile                                       # Multi-stage production container
    ├── .dockerignore
    ├── cloudrun.yaml                                    # Declarative GCP Cloud Run specification
    ├── GCP_DEPLOYMENT_GUIDE.md                          # Google Cloud Run deployment instructions
    ├── slack-manifest.yaml                              # Slack App manifest (YAML)
    ├── slack-manifest.json                              # Slack App manifest (JSON)
    ├── package.json                                     # Dependencies & npm scripts
    ├── tsconfig.json                                    # TypeScript compiler options
    ├── .env                                             # Active tokens & secrets
    ├── .env.example                                     # Template for environment variables
    └── src/
        ├── index.ts                                     # Bolt App startup & Cloud Run HTTP health server
        ├── config.ts                                    # Environment validation & loading
        ├── test-agent.ts                                # CLI verification test suite
        ├── gemini/
        │   ├── client.ts                                # Google Gen AI client singleton
        │   ├── prompt.ts                                # System prompt, persona, Slack formatting rules
        │   ├── tools.ts                                 # Tool declarations & execution dispatcher
        │   └── agent.ts                                 # Multi-turn chat session manager & retry loop
        └── slack/
            ├── handlers.ts                              # app_mention & direct message listeners
            └── formatters.ts                            # Slack mrkdwn & Block Kit card builder
```

---

## 5. How to Test and Use

### Scenario 1: Direct Message (1-on-1 Chat)
1. Open Slack ➔ Click the bot under **Apps** (e.g. `test_agent_app` or `Gemini`).
2. Send: `"Hi! Who are you and how can you assist our team?"`
3. **Result**: The bot reacts with `:thinking_face:`, calls Gemini, replaces the reaction with `:white_check_mark:`, and posts a rich Block Kit card outlining its capabilities.

### Scenario 2: Salesforce CRM Account Lookup
1. In DM or Channel, send:
   `"Can you look up the account details for Acme Corp and let me know who the CSM is?"`
2. **Result**: Gemini autonomously calls `get_crm_account(accountName: "Acme Corp")`, retrieves the data from Salesforce, and responds with the Account status, CSM email (`skgsummo5@gmail.com`), and primary contact details.

### Scenario 3: Real-Time Customer Email Summary
1. In DM or Channel, send:
   `"Summarize the latest email thread for Acme Corp"`
2. **Result**: Gemini calls `summarize_customer_thread`, pulls the executive summary from `Gmail_Thread_Summary__c`, and presents the narrative overview, discussion highlights, and recommended follow-ups.

### Scenario 4: Meeting Scheduling on Google Calendar
1. In DM or Channel, send:
   `"Schedule a follow-up review with Alex Hales tomorrow at 3 PM"`
2. **Result**: Gemini calls `schedule_calendar_meeting`, schedules the meeting, generates a Google Meet video link, and formats the invitation confirmation in Slack.

### Scenario 5: Multi-Turn Thread Continuity
1. In any existing reply thread, send a follow-up question:
   `"What was the recommended next step for that?"`
2. **Result**: Gemini uses the `thread_ts` session context to remember previous exchanges and answers accurately without losing context.

---

## 6. How to Manage the 24/7 Container Service

From inside `slack-gemini-agent/`:

```bash
# View real-time logs (incoming messages, tool triggers, responses)
npm run container:logs

# Check status of the container
npm run container:status

# Restart the bot container
npm run container:restart

# Stop the bot container
npm run container:stop

# Start the bot container
npm run container:start
```

---

## 7. Future GCP Cloud Run Deployment

If you choose to link billing to your Google Cloud project (`exalted-justice-507211-v9`), you can deploy this exact container to **Google Cloud Run** in 2 minutes:

```bash
cd slack-gemini-agent

gcloud run deploy slack-gemini-agent \
  --source . \
  --project exalted-justice-507211-v9 \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --min-instances 1 \
  --max-instances 2 \
  --memory 512Mi \
  --no-cpu-throttling \
  --set-env-vars "GEMINI_API_KEY=YOUR_KEY,GEMINI_MODEL=gemini-3.6-flash,SLACK_BOT_TOKEN=xoxb-...,SLACK_APP_TOKEN=xapp-...,SLACK_SIGNING_SECRET=..."
```
*(Detailed steps documented in [`GCP_DEPLOYMENT_GUIDE.md`](file:///C:/Users/Sumit%20Kr%20Gupta/OneDrive%20-%20Teqfocus%20Solutions%20Pvt.%20Ltd/Desktop/Learn%20DC/slack-gemini-agent/GCP_DEPLOYMENT_GUIDE.md)).*

---

## 8. Complete "From-Scratch" Implementation Tutorial (Zero-to-Hero Guide)

If you or any engineer wants to replicate and build this full functionality completely from scratch on a new project or org, follow this definitive step-by-step guide.

---

### Step 1: Prerequisites & Developer Environment

Before writing code, ensure you have:
1. **Node.js (v20+ or v22+) & npm**: Check via `node -v` and `npm -v`.
2. **Docker Desktop**: Required for local 24/7 background container execution (`docker -v`).
3. **Slack Workspace Admin Access**: Permission to create apps at [api.slack.com/apps](https://api.slack.com/apps).
4. **Google AI Studio Account**: Free API key generated at [aistudio.google.com](https://aistudio.google.com/).
5. **Salesforce Target Org**: A Developer Edition, Sandbox, or Scratch Org with Account and Activity data.

---

### Step 2: Initialize Project & Install Dependencies

Create a dedicated folder (e.g. `slack-gemini-agent/`) to isolate the bot from Salesforce metadata:

```bash
mkdir slack-gemini-agent
cd slack-gemini-agent

# Initialize npm package
npm init -y

# Install runtime dependencies
npm install @slack/bolt @google/genai dotenv docx

# Install TypeScript developer tooling
npm install --save-dev typescript @types/node tsx
```

Create `tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

Add the operational scripts to `package.json`:
```json
"scripts": {
  "dev": "tsx watch src/index.ts",
  "build": "tsc",
  "start": "node dist/index.js",
  "test:agent": "tsx src/test-agent.ts",
  "container:logs": "docker logs -f slack-gemini-agent-service",
  "container:restart": "docker restart slack-gemini-agent-service",
  "container:stop": "docker stop slack-gemini-agent-service",
  "container:start": "docker start slack-gemini-agent-service",
  "container:status": "docker ps --filter name=slack-gemini-agent-service"
}
```

---

### Step 3: Create & Configure the Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps) ➔ Click **Create New App** ➔ Choose **From an app manifest**.
2. Select your Slack workspace and paste the following YAML manifest:
   ```yaml
   display_information:
     name: Gemini Agent
     description: Autonomous enterprise AI assistant powered by Google AI Studio
     background_color: "#1a73e8"
   features:
     bot_user:
       display_name: Gemini
       always_online: true
     app_home:
       messages_tab_enabled: true
       messages_tab_read_only_enabled: false
   oauth_config:
     scopes:
       bot:
         - app_mentions:read
         - chat:write
         - channels:history
         - groups:history
         - im:history
         - im:read
         - im:write
         - reactions:write
   settings:
     socket_mode_enabled: true
     event_subscriptions:
       bot_events:
         - app_mention
         - message.im
     interactivity:
       is_enabled: true
   ```
3. Click **Create**.
4. **Generate App-Level Token (for Socket Mode)**:
   - Go to **Basic Information** ➔ Scroll to **App-Level Tokens** ➔ Click **Generate Token and Scopes**.
   - Name: `socket-token`
   - Add scope: `connections:write`
   - Click **Generate** and copy the `xapp-...` token.
5. **Install App to Workspace**:
   - In left menu, click **Install App** ➔ **Install to Workspace** ➔ Click **Allow**.
   - Copy **Bot User OAuth Token** (`xoxb-...`) from **OAuth & Permissions**.
   - Copy **Signing Secret** from **Basic Information**.
6. **Enable 1-on-1 Messages (Critical!)**:
   - In left menu under **Features**, click **App Home**.
   - Under **Messages Tab**, ensure the checkbox **"Allow users to send Slash commands and messages from the messages tab"** is CHECKED.

---

### Step 4: Configure Environment Secrets (`.env`)

Create `.env` in `slack-gemini-agent/`:

```env
# Google AI Studio
GEMINI_API_KEY=your_gemini_api_key_here
GEMINI_MODEL=gemini-3.6-flash

# Slack App Credentials
SLACK_BOT_TOKEN=xoxb-your-bot-token
SLACK_APP_TOKEN=xapp-your-app-token
SLACK_SIGNING_SECRET=your-signing-secret

# Salesforce Settings (learn_dc)
ENABLE_SALESFORCE_TOOLS=true
SF_LOGIN_URL=https://login.salesforce.com
SF_USERNAME=sumit.gupta@datacloud.com
```

---

### Step 5: Implement the Core Application Files

#### 1. Configuration Validator (`src/config.ts`)
Validates that required Slack and Gemini tokens exist on startup, preventing runtime crashes.

#### 2. System Prompt & Persona (`src/gemini/prompt.ts`)
Defines the enterprise assistant persona, mandates Slack formatting standards (bullet points, bold highlights, code blocks), and sets guardrails against hallucinating CRM data.

#### 3. Declarative Tools & Function Calling (`src/gemini/tools.ts`)
Exposes JSON Schema parameter specifications:
- `get_current_time`: Returns timezone-aware real-time dates.
- `get_crm_account`: Queries Account Name, CSM email (`Account.CSM_Email__c`), and Contacts.
- `summarize_customer_thread`: Pulls customer email summaries and action items.
- `schedule_calendar_meeting`: Coordinates appointments with Google Meet links.

#### 4. Session Manager & Function Calling Loop (`src/gemini/agent.ts`)
- Manages an in-memory chat session cache mapping Slack thread timestamps (`thread_ts`) to `ai.chats.create(...)`.
- Executes the autonomous tool loop: detects `response.functionCalls`, executes the corresponding tool, feeds results back via `functionResponse`, and loops until the final answer is synthesized.
- Includes exponential backoff retry on transient 503/429 spikes.

#### 5. Slack Block Kit Formatter (`src/slack/formatters.ts`)
Converts standard markdown into Slack mrkdwn and wraps answers in professional Block Kit sections and divider cards.

#### 6. Slack Event Handlers (`src/slack/handlers.ts`)
- **Channel Mentions (`app_mention`)**: Cleans mention tags, reacts with `:thinking_face:`, passes prompt to Gemini, and replies in the message thread.
- **Direct Messages (`message`)**: Detects direct messages (`channel.startsWith('D')`), preserves DM session memory, and swaps reaction to `:white_check_mark:`.

#### 7. Main Startup & Health Server (`src/index.ts`)
Initializes the `@slack/bolt` App with `socketMode: true`, boots up an HTTP health server on port `8080` (`GET /health`), and connects to Slack.

---

### Step 6: Test & Verify Locally

1. **Verify AI Agent & Tools via CLI**:
   ```bash
   npm run test:agent
   ```
   Ensures prompt reasoning, tool invocation, and multi-turn memory work cleanly.

2. **Start the Bot in Development Mode**:
   ```bash
   npm run dev
   ```
3. **Verify in Slack**:
   - Send DM: *"Hi! Who are you?"* ➔ Verifies greeting & Block Kit formatting.
   - Send CRM Query: *"Look up details for Acme Corp"* ➔ Verifies autonomous tool execution.
   - Mention in Channel: *"@Gemini summarize latest email thread for Acme Corp"* ➔ Verifies channel thread reply.

---

### Step 7: Containerize for 24/7 Production Execution

Create `Dockerfile`:
```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
COPY src/ ./src/
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder /app/dist ./dist
USER node
EXPOSE 8080
CMD ["node", "dist/index.js"]
```

Create `.dockerignore`:
```
node_modules
dist
.env
.git
```

Build and launch the persistent background container:
```bash
# Build the compact 66.5 MB container
docker build -t slack-gemini-agent:latest .

# Run 24/7 with auto-restart on system reboot
docker run -d --name slack-gemini-agent-service --restart unless-stopped -p 8080:8080 --env-file .env slack-gemini-agent:latest
```

The bot will now run 24 hours a day, 7 days a week, automatically restarting after reboots!

---

## 9. Native Salesforce-Hosted MCP Integration (Model Context Protocol)

To take this integration to the next level, Salesforce now provides native **Hosted MCP Servers** configured directly in **Salesforce Setup**. This allows AI agents to interact with your org using the open **Model Context Protocol (JSON-RPC 2.0 over Server-Sent Events)** without writing custom API code.

### 1. How It Works

```mermaid
graph LR
    SlackUser["Slack User"] <-->|"Natural Language"| SlackBot["Slack Bot (Socket Mode)"]
    SlackBot <-->|"User Prompt"| GeminiAgent["Google AI Studio Gemini Agent<br/>(MCP Client)"]
    GeminiAgent <-->|"JSON-RPC 2.0 over SSE"| SFHostedMCP["Salesforce Hosted MCP Server<br/>(Setup ➔ MCP Server)"]
    SFHostedMCP <-->|"Native CRUD, FLS & Sharing"| SalesforceData["Salesforce Objects & Apex<br/>(Account, Contact, Event, Gmail_Thread_Summary__c)"]
```

1. **Salesforce Setup (MCP Server)**: You configure and activate a Custom MCP Server directly in the Salesforce UI, selecting which objects and Apex actions to expose.
2. **Dynamic Tool Reflection**: On startup, our agent queries `mcpClient.listTools()`. It dynamically registers all tools configured in Salesforce Setup into Gemini without hardcoding!
3. **Graceful Fallback**: If `SF_MCP_ENDPOINT_URL` is not yet configured, the bot seamlessly continues serving requests using its built-in CRM tools.

---

### 2. How to Create the Custom MCP Server in Salesforce Setup

1. **Log in to Salesforce (`learn_dc`)**:
   - Go to **Setup** (gear icon ⚙️).
   - In Quick Find, search for **"MCP Server"** (under *Platform Developer Tools* / *Agentforce* / *External Services*).
2. **Click "New Custom MCP Server"**:
   - **Label**: `LearnDC Agent MCP Server`
   - **API Name**: `LearnDC_Agent_MCP_Server`
   - **Description**: `Native MCP server exposing CRM data, email summaries, and calendar actions to AI agents.`
3. **Curate the Toolset ("Build the Plate")**:
   - **Objects**: Check `Account`, `Contact`, `Event`, and `Gmail_Thread_Summary__c`.
   - **Apex Actions**: Select `AccountCalendarController.createMeeting` and `AccountGmailController`.
   - **Queries**: Enable safe SOQL execution.
4. **Save & Activate**:
   - Click **Save & Activate**.
   - Copy the generated **MCP Server Endpoint URL** (e.g. `https://<your-instance>.my.salesforce.com/services/mcp/v1/...`).

---

### 3. Connect the Agent to Salesforce-Hosted MCP

1. Open `slack-gemini-agent/.env` and paste your endpoint URL:
   ```env
   SF_MCP_ENDPOINT_URL=https://<your-instance>.my.salesforce.com/services/mcp/v1/...
   SF_ORG_ALIAS=learn_dc
   ```
2. Run the diagnostic test:
   ```bash
   npm run test:mcp
   ```
   This will automatically:
   - Resolve your active `learn_dc` session and access token via Salesforce CLI.
   - Connect to the Salesforce Hosted MCP Server via Server-Sent Events (`SSEClientTransport`).
   - List and display all tools configured in Salesforce Setup.
3. Restart the background container service:
   ```bash
   npm run container:restart
   ```
   All tools declared in Salesforce Setup are now instantly active and usable directly from Slack!




---

## Enterprise Update: Autonomous OAuth 2.0 Self-Healing Session Engine

### Problem & Discovery:
In production environments (like Docker containers and Google Cloud Run), the Salesforce CLI (`sf`) is not available. Furthermore, static access tokens in `.env` expire (Salesforce standard 2-hour session limit), causing HTTP 401 `INVALID_SESSION_ID` errors during tool execution.

### Architectural Solution:
1. **Dynamic Token Refresh via OAuth 2.0**:
   Added direct OAuth 2.0 token endpoint integration (`POST https://login.salesforce.com/services/oauth2/token`) using `grant_type=refresh_token` and `client_id=PlatformCLI` in `salesforceAuth.ts`.
2. **Transparent 401 Interception**:
   In `salesforceMcpClient.ts`, the client intercepts any HTTP 401 response from an Invocable Action, immediately requests a fresh token using `getSalesforceCredentials(forceRefresh=true)`, and retries the action call transparently.
3. **Zero CLI Dependency**:
   Runs completely on native `fetch` calls, making the container fully autonomous across Docker Desktop, Cloud Run, and Kubernetes.
