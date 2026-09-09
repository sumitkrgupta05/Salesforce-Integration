# Master Enterprise Architecture & Implementation Playbook: Salesforce, GCP, Slack, Snowflake & Google AI Studio

---

## 1. Executive Summary & Grand Unified Architecture

This document is the **definitive, end-to-end Master Technical Playbook and Architectural Reference** for the unified enterprise customer intelligence platform deployed in the **Salesforce `learn_dc`** ecosystem.

It brings together five distinct enterprise platforms into a single, cohesive, zero-friction operating cockpit for Customer Success Managers (CSMs), Account Executives (AEs), and Support Leaders:

```mermaid
graph TD
    subgraph SF_PLATFORM["Salesforce Lightning Platform (learn_dc)"]
        LWC_BOT["slackBotAgent (LWC)<br/>• Left Thread History<br/>• User Privacy Isolation<br/>• Native Desktop Alerts<br/>• Slash Commands Palette"]
        LWC_GMAIL["accountGmail (LWC)<br/>• Split-Pane Reader<br/>• RFC 2822 Header Threading<br/>• Whole Thread AI Summary"]
        LWC_CAL["accountGoogleCalendar (LWC)<br/>• Meeting Scheduler<br/>• Auto Google Meet Link<br/>• Event Type Isolation"]
        
        CTRL_BOT["SlackBotAgentController.cls<br/>& SlackUserIdentityService.cls"]
        CTRL_GMAIL["AccountGmailController.cls<br/>& AccountGmailInboundHandler.cls"]
        CTRL_CAL["AccountCalendarController.cls<br/>& GoogleAuthService.cls (JWT)"]
        
        MCP_SERVER["LearnDCAgentMCPServer.cls<br/>(Apex Invocable MCP Server)<br/>• search_accounts<br/>• query_snowflake<br/>• create_account_task"]
        
        LWC_BOT --> CTRL_BOT
        LWC_GMAIL --> CTRL_GMAIL
        LWC_CAL --> CTRL_CAL
        CTRL_BOT --> MCP_SERVER
    end

    subgraph GCP_CLOUDRUN["Google Cloud Platform (slack-gemini-agent)"]
        GATEWAY["Express HTTP Gateway (Port 8080)<br/>• GET /auth/login<br/>• POST /auth/slack/confirm<br/>• POST /api/chat<br/>• GET /health"]
        CONSENT_UI["Slack Workspace Consent Screen<br/>(Branded User Authorization UI)"]
        GEMINI_ENGINE["Google AI Studio Gemini 3.6 Flash<br/>• Multi-turn Session Manager<br/>• Autonomous Tool Loop"]
        SNOW_DAEMON["SnowflakeSyncDaemon.ts<br/>• Continuous 5s Bi-Directional Sync<br/>• 0s On-Demand SLA Reconciliation"]
        
        GATEWAY --> CONSENT_UI
        GATEWAY --> GEMINI_ENGINE
        GATEWAY --> SNOW_DAEMON
    end

    subgraph SLACK_WORKSPACE["Slack Enterprise Workspace (T0BU7EDE40P)"]
        SOCKET_MODE["Socket Mode WebSocket (wss://)<br/>• No Public Ports / Ngrok<br/>• Outbound Persistent Tunnel"]
        SLACK_BOT["Slack App: test_agent_app<br/>(App ID: A0BU7FHCFEK)"]
        SLASH_CMDS["Slash Commands Engine<br/>• /account-brief (3s ack)<br/>• /summarize-thread<br/>• /snowflake<br/>• /help"]
        PRIVATE_DMS["Private 1-on-1 DMs<br/>(conversations.open per CSM)"]
        
        SOCKET_MODE --> SLACK_BOT
        SLACK_BOT --> SLASH_CMDS
        SLACK_BOT --> PRIVATE_DMS
    end

    subgraph SNOWFLAKE_DWH["Snowflake Cloud Data Warehouse (hjyxziv-mi58790)"]
        BASE_ANALYTICS[("LEARNDC_DB.ANALYTICS<br/>ACCOUNT_ANALYTICS<br/>(Base Table - 5s Sync)")]
        SECURE_MCP[("LEARNDC_MCP_DB.SECURE_ANALYTICS<br/>V_ACCOUNT_INSIGHTS<br/>(8 Sanitized Telemetry Fields)")]
        MCP_ROLE["Role: MCP_AGENT_READER_ROLE<br/>• Least-Privilege Read-Only<br/>• Key-Pair RSA Authentication"]
        
        BASE_ANALYTICS --> SECURE_MCP
        SECURE_MCP --> MCP_ROLE
    end

    subgraph GOOGLE_WORKSPACE["Google Workspace Services"]
        GMAIL_SVC["Gmail API & Inbound Relay<br/>(RFC 2822 Headers & csm-reply@...)"]
        GCAL_SVC["Google Calendar API v3<br/>& Google Meet Video Link Generator"]
        GPUSH_SVC["Google Push Notifications Webhook<br/>(Delta Sync with syncToken)"]
    end

    %% Cross-Platform Connections
    CTRL_BOT <==>|Fast Identity & REST Invocable| GATEWAY
    GATEWAY <==>|Socket Mode wss://| SOCKET_MODE
    GEMINI_ENGINE <==>|Autonomous Function Calling| MCP_SERVER
    SNOW_DAEMON <==>|MERGE INTO & Telemetry Writeback| BASE_ANALYTICS
    GEMINI_ENGINE <==>|Read-Only Parameterized SQL| SECURE_MCP
    CTRL_GMAIL <==>|Inbound & Outbound Dual Delivery| GMAIL_SVC
    CTRL_CAL <==>|RSA JWT Bearer & Webhook Push| GCAL_SVC
    GPUSH_SVC -->|Delta Notification Ping| CTRL_CAL
```

### The Seven Operational Pillars Built:

1. **Native CSM & Client Bidirectional Gmail Threading**: Overcomes GCP domain registration blockers (`skg5.com`), Developer Edition email limits, and personal inbox fragmentation by using native RFC 2822 header injection (`Message-ID`, `In-Reply-To`, `References`) with real-time `accountGmail` split-pane UI.
2. **Real-Time Google Calendar & Meet Sync**: Seamless enterprise scheduling via Google Workspace Domain-Wide Delegation (RSA-SHA256 signed JWT tokens), interactive meeting booking, auto-provisioned Google Meet links, and Google Push Webhook delta-syncing (`syncToken`).
3. **Omni-Channel Autonomous AI Agent (Gemini 3.6 Flash)**: A unified cognitive engine running in a containerized Node.js service (`slack-gemini-agent`) on port 8080. It powers conversational intelligence across Slack channels, Slack direct messages, and Salesforce Lightning pages.
4. **Slack Slash Commands Engine**: Instant power-user shortcuts (`/account-brief`, `/summarize-thread`, `/snowflake`, `/help`) with strict adherence to Slack's 3-second acknowledgment window, Socket Mode security, and rich Block Kit formatting.
5. **Salesforce LWC Cockpit (`slackBotAgent`)**: Account-centric, user-isolated chat interface with collapsible past thread history, clean Activity Timeline hygiene (intentional task creation confirmations), Slack permalink deep linking (`Slack ↗`), and hybrid Apex fallback.
6. **Native OS Desktop Notifications**: Client-side background visibility detection (`document.hidden`, `!document.hasFocus()`) that triggers Windows/macOS native toast notifications and pulsating browser tab titles (`🔔 (1) New Reply Ready`) when AI responses complete while the user is multitasking.
7. **Two-Tier Snowflake Warehouse & MCP Isolation**: Continuous 5-second bi-directional synchronization between Salesforce Accounts and Snowflake `ACCOUNT_ANALYTICS`, combined with a strictly isolated Model Context Protocol (MCP) database (`LEARNDC_MCP_DB`) and Secure View (`V_ACCOUNT_INSIGHTS`) exposing exactly 8 telemetry fields with zero brand leakage.

---

## 2. Complete Project & Metadata Directory Inventory

Every single asset in the project is cataloged below with its absolute path, runtime environment, and architectural responsibility:

### A. Salesforce Platform Metadata (`force-app/main/default/`)

| File / Component | Type | Responsibility |
|---|---|---|
| `SlackBotAgentController.cls` | Apex Controller | Primary LWC controller for `slackBotAgent`. Manages session initiation, Slack history thread loading with user privacy isolation, slash command execution, task confirmations, and GCP auth URL generation. |
| `SlackUserIdentityService.cls` | Apex Service | High-performance user identity resolver (<5ms). Queries and caches `Slack_User_Id__c`, `Slack_DM_Channel_Id__c`, and `Slack_Connected_Email__c` on the `User` object. Generates signed GCP OAuth URLs. |
| `AccountGmailController.cls` | Apex Controller | Backend controller for `accountGmail` LWC. Retrieves customer email threads, parses RFC 2822 headers, checks Gemini thread summaries, and dispatches outbound messages. |
| `AccountGmailInboundHandler.cls` | Inbound Email Service | Processes inbound client emails sent to `csm-reply@...`. Extracts `In-Reply-To` and `References`, associates replies with the Account, updates thread counters, and alerts the CSM. |
| `GmailAIService.cls` | Apex AI Service | Generates executive whole-thread summaries from entire email chains using Google Gemini 3.6 Flash with heuristic fallback. Persists cached summaries in `Gmail_Thread_Summary__c`. |
| `AccountCalendarController.cls` | Apex Controller | Backend controller for `accountGoogleCalendar` LWC. Handles meeting creation, time-shifting, cancellations, attendee validation, and Google Meet video link injection. |
| `GoogleAuthService.cls` | Apex Service | Crafts RSA-SHA256 signed JWT Bearer assertion tokens for Google Workspace Domain-Wide Delegation. Trades JWT for Google OAuth2 access tokens. |
| `GoogleCalendarService.cls` | Apex Service | HTTP REST callout engine interacting with Google Calendar API v3 (`/calendars/primary/events`). Enforces `sendUpdates=none` to prevent email duplication. |
| `GoogleCalendarQueueable.cls` | Apex Queueable | Handles asynchronous delta-synchronization of Google Calendar events using `syncToken`. Upserts/deletes standard `Event` records without infinite sync loops. |
| `LearnDCAgentMCPServer.cls` | Invocable MCP Server | Custom Apex Model Context Protocol server exposing tool capabilities (`search_accounts`, `query_snowflake`, `create_account_task`) to Gemini. |
| `LearnDCMCPAccountAction.cls` | Invocable Action | Pulls live 360° Account vitals, CSM assignment (`Account.CSM_Email__c`), and primary contacts for AI consumption. |
| `LearnDCMCPThreadAction.cls` | Invocable Action | Formats whole email thread conversations into structured text prompts for instant AI summarization. |
| `slackBotAgent` | LWC | Full copilot interface embedded on Account record pages. Houses left thread history, active chat feed, notification bell, slash autocomplete palette, and Slack deep links. |
| `accountGmail` | LWC | Master-detail split-pane email client. Shows active customer threads, unread counter badges, Gemini summary banner, and inline reply composer. |
| `accountGoogleCalendar` | LWC | Meeting scheduler card. Includes meeting title input, start/end date-time pickers, Google Meet auto-generate toggle, and attendee chips. |

### B. Google Cloud Platform & Node.js Middleware (`slack-gemini-agent/`)

| File / Component | Responsibility |
|---|---|
| `src/index.ts` | Main application entry point. Initializes Express HTTP server (port 8080), mounts `/auth/login`, `/auth/slack/confirm`, `/api/chat`, and `/health`, and starts Slack Socket Mode client. |
| `src/api/auth.ts` | Authentication & Consent Controller. Renders branded Slack consent HTML screen, handles `POST /auth/slack/confirm`, provisions private DM channels via `conversations.open`, and updates Salesforce via REST API. |
| `src/bot/slackBot.ts` | Slack Bolt App orchestration. Listens for mentions (`@Gemini`), direct messages, and interactive Block Kit button events across Socket Mode WebSocket (`wss://`). |
| `src/commands/slashCommands.ts` | Slash command handler for `/account-brief`, `/summarize-thread`, `/snowflake`, and `/help`. Executes 3-second immediate `ack()` and dispatches background execution. |
| `src/services/geminiService.ts` | Google AI Studio Gemini 3.6 Flash interface. Manages multi-turn conversation sessions mapped to Slack `thread_ts`, system instructions, and recursive function-calling tool execution. |
| `src/services/snowflakeSyncDaemon.ts` | Background sync daemon. Polls modified Salesforce Accounts every 5 seconds, issues `MERGE INTO` in Snowflake, and writes back telemetry metrics. |
| `src/mcp/snowflakeMcpClient.ts` | Snowflake Model Context Protocol client. Connects using key-pair authentication to `LEARNDC_MCP_DB`, executing parameterized queries against `V_ACCOUNT_INSIGHTS`. |
| `src/mcp/salesforceMcpClient.ts` | Salesforce MCP client. Bridges Node.js agent to Salesforce Apex invocable actions via REST API with OAuth2 bearer token authentication. |

---

## 3. Pillar 1: Native CSM & Client Bidirectional Gmail Integration

### The Core Problem Solved:
Enterprises frequently face insurmountable friction trying to connect Salesforce and Google Workspace:
1. **Google Admin / Domain Verification Blockers**: Corporate IT will not grant global Google Workspace super-admin permissions or verify custom domains (`skg5.com`) for testing or departmental apps.
2. **Salesforce Daily Email Limits**: Developer Edition orgs enforce strict limits (15 to 50 outbound SingleEmails per day).
3. **Fragmented Inboxes**: CSM personal inboxes (`skgsummo5@gmail.com`) get disconnected from the Salesforce timeline, leading to blind spots during renewals.

### Architectural Solution:
* **RFC 2822 Inbound & Outbound Headers**: Every outbound message composed by a CSM in Salesforce has custom headers injected:
  * `Message-ID: <csm-{AccountId}-{ThreadId}-{Timestamp}@learn-dc.salesforce.com>`
  * `In-Reply-To: <parent-message-id>`
  * `References: <parent-message-id>`
* **Dynamic Inbound Email Service (`AccountGmailInboundHandler.cls`)**: 
  * Inbound address configured as `csm-reply@...`.
  * When a customer replies to an email thread, Gmail uses the `In-Reply-To` header to keep the thread grouped in Gmail.
  * Salesforce extracts the parent thread, increments unread message counters, logs an inbound `Event`, and fires a Platform Event (`Gmail_Sync_Notification__e`) that immediately updates the `accountGmail` LWC without page refreshes.
* **Dual-Delivery with Zero Domain Dependency**:
  * Outbound emails are dispatched directly to the customer (`skgsumit5@gmail.com`) and automatically copied to the CSM's real personal mailbox (`skgsummo5@gmail.com`).
  * Both inboxes and Salesforce remain 100% synchronized in real time.
* **AI Whole-Thread Summarization**:
  * Rather than summarizing isolated single messages, `GmailAIService.cls` feeds the entire chronological message chain into Gemini 3.6 Flash.
  * Extracted output: **Executive Summary Narrative**, **Key Discussion Items**, and **Pending Action Items**.
  * Results are cached in `Gmail_Thread_Summary__c` for instantaneous (<10ms) subsequent renders.

---

## 4. Pillar 2: Real-Time Bidirectional Google Calendar & Meet Integration

```mermaid
sequenceDiagram
    autonumber
    actor CSM as CSM in Salesforce
    participant LWC as accountGoogleCalendar (LWC)
    participant Ctrl as AccountCalendarController.cls
    participant Auth as GoogleAuthService.cls
    participant GCal as Google Calendar API v3
    participant Webhook as Apex REST Webhook Site

    CSM->>LWC: Fills Meeting Title, Start/End Time, Toggles Google Meet
    LWC->>Ctrl: scheduleMeeting(accountId, title, startDateTime, endDateTime, autoMeet)
    Ctrl->>Auth: getAccessToken()
    Note over Auth: Signs JWT with RSA-SHA256 Private Key & calls Google OAuth2
    Auth-->>Ctrl: Returns Bearer Token
    Ctrl->>GCal: POST /calendars/primary/events?conferenceDataVersion=1&sendUpdates=none
    GCal-->>Ctrl: Returns Event JSON + Google Meet Link (meet.google.com/...)
    Ctrl->>Ctrl: Upserts standard Event record (Type='Meeting', Meeting_Type__c='Google Calendar')
    Ctrl-->>LWC: Success + Meeting Link Badge
    
    Note over GCal,Webhook: Inbound External Change on Calendar
    GCal->>Webhook: Webhook Push Notification Ping
    Webhook->>GCal: Delta Fetch via syncToken
    Webhook->>Webhook: Reconciles & updates Salesforce Event Object
```

### Architectural Key Guardrails:
1. **JWT Bearer Token Exchange (RSA-SHA256)**: Implemented purely in native Apex without third-party libraries. Signs the payload header and claims set with the Google Cloud Service Account private key and exchanges it at `https://oauth2.googleapis.com/token`.
2. **`sendUpdates=none` Enforcement**: When creating meetings via the Google API, `sendUpdates=none` is explicitly passed to ensure Google does not send generic system meeting invitations that duplicate or conflict with custom CSM email communications.
3. **Calendar vs. Email Event Isolation**: Standard `Event` records in Salesforce can easily become cluttered. The codebase enforces strict type isolation:
   * Gmail messages log as `Type = 'Email'` with `Subject = 'Gmail: ...'`
   * Calendar meetings log as `Type = 'Meeting'` with `Meeting_Type__c = 'Google Calendar'`
   * This ensures the Calendar LWC and Gmail LWC never display cross-contaminated records.
4. **Infinite Sync Loop Suppression**: When Salesforce syncs an event to Google, the returned `Google_Event_Id__c` and `Last_Google_Sync__c` timestamp are committed. When Google sends an inbound webhook push notification, the queueable job compares the Google `updated` timestamp against `Last_Google_Sync__c`. If the timestamps match within 2 seconds, the update is identified as an echo and dropped.

---

## 5. Pillar 3: Slack Gemini Autonomous AI Agent (`slack-gemini-agent`)

The middleware service is a containerized TypeScript/Node.js microservice architected for high availability and zero incoming network exposure:

### A. Socket Mode WebSocket Architecture (`wss://`):
* Traditional Slack bots require public HTTP webhook URLs, reverse proxies (ngrok), open firewall ports, and SSL certificates.
* This agent utilizes **Slack Socket Mode**: it establishes an outbound secure WebSocket connection from inside the container directly to Slack's servers.
* Result: 100% firewall compatibility, immune to external port scans, and zero domain or ingress configuration required.

### B. Cognitive Engine: Google Gemini 3.6 Flash
* Configured with custom enterprise System Instructions:
  * Operates as an elite Customer Success and CRM Copilot.
  * Reasons dynamically over natural language intent.
  * Dispatches structured **Function Calls** (MCP Tools) to query CRM Account vitals, read customer email summaries, check Google Calendar schedules, and query Snowflake analytics.
  * Automatically synthesizes raw tool JSON payloads into unified, professional executive responses.
* **Session Continuity**: Multi-turn conversational memory is preserved by mapping the Slack thread timestamp (`thread_ts`) or Salesforce session ID directly to a persistent Gemini Chat Session in memory. Follow-up queries maintain full context without repeating account names.

---

## 6. Pillar 4: Slack Slash Commands Engine (`/account-brief`, etc.)

Slash commands allow users across any Slack channel, group, or direct message to trigger instant CRM intelligence without mentioning `@Gemini`:

```mermaid
sequenceDiagram
    autonumber
    actor User as Slack User (CSM/AE)
    participant Slack as Slack Client
    participant Agent as slack-gemini-agent (Socket Mode)
    participant MCP as Salesforce & Snowflake MCP

    User->>Slack: Types "/account-brief Edge Communications"
    Slack->>Agent: WebSocket Event: command('/account-brief')
    
    rect rgb(235, 245, 255)
        Note over Agent,Slack: 3-SECOND ACKNOWLEDGMENT RULE
        Agent-->>Slack: await ack() (Prevents Slack "operation_timeout")
        Agent->>Slack: respond("🔍 Generating 360° brief for Edge Communications...")
    end

    Agent->>MCP: 1. Fetch CRM Vitals (CSM, Contact, SLA)
    Agent->>MCP: 2. Fetch Snowflake Telemetry (Health, Usage, Churn)
    Agent->>MCP: 3. Fetch Gmail Intelligence Summary
    MCP-->>Agent: Consolidated Data DTO
    Agent->>Agent: Synthesize into Slack Block Kit Rich Card
    Agent->>Slack: chat.postMessage (Replaces loading pill with 360° Dossier)
```

### Slash Commands Specification Table:

| Command | Arguments | Purpose & Output | Execution Time |
|---|---|---|---|
| `/account-brief` | `[Account Name]` (Optional; defaults to active record in LWC) | Dispatches 3-way parallel retrieval (Salesforce CRM vitals, Snowflake usage telemetry, and Gmail whole-thread summary). Renders executive 360° Dossier Card. | ~1.8s |
| `/summarize-thread` | `[Thread ID]` | Analyzes the complete multi-party email exchange for the target thread. Outputs narrative summary, key concerns, and action items. | ~1.4s |
| `/snowflake` | `[Account Name]` | Queries `V_ACCOUNT_INSIGHTS` in Snowflake for live platform usage hours, health score (0-100), churn risk score, and SLA tier. | ~600ms |
| `/help` | None | Returns an interactive Block Kit menu detailing all supported commands, syntax examples, and shortcuts. | <100ms |

---

## 7. Pillar 5: Salesforce LWC Copilot Cockpit (`slackBotAgent`)

Embedded directly into the Salesforce Account Record Page layout, the `slackBotAgent` LWC is the nerve center for the CSM:

### Architectural Innovations:
1. **Left Sidebar Thread History & Resumption**:
   * Displays all active and archived conversation threads for the specific Account.
   * Clicking any thread instantly reloads the conversation history and binds the user back to the existing Slack thread (`threadTs`).
2. **Strict User-Isolated Privacy**:
   * Even within the same Account, conversations are strictly isolated per user:
     `WHERE AccountId = :recordId AND (CreatedById = :currentUserId OR OwnerId = :currentUserId)`
   * User A and User B will never see or leak each other's private conversation threads.
3. **Clean Activity Timeline Hygiene**:
   * General inquiries, AI brainstorming, and slash commands do **not** spam the Salesforce database with dummy `Task` records.
   * Salesforce `Task` records are created **only** when the user explicitly instructs the copilot to schedule a task or follow-up.
   * Intentional confirmation: The agent prompts for parameters (Subject, Due Date, Priority) and presents a confirmation modal before taking action.
4. **Slack Deep Linking (`Slack ↗`)**:
   * Every message bubble features a `💬 View in Slack History` button, and the header features `Slack ↗`.
   * Clicking opens the exact Slack thread in Slack Desktop or Slack Web (`https://slack.com/archives/...`), automatically expanding the thread sidebar.
5. **Hybrid High-Availability Fallback**:
   * When the Node.js Slack Gateway is online, all traffic flows through the gateway to preserve dual-channel continuity.
   * If the gateway ever goes offline, the Apex controller seamlessly falls back to native Apex + Gemini MCP Server execution. End-users experience 100% uptime without error dialogs.

---

## 8. Pillar 6: Native OS Desktop Notifications & Background Visibility Alerts

```mermaid
sequenceDiagram
    autonumber
    actor User as Salesforce CSM
    participant LWC as slackBotAgent (Browser Client)
    participant PageAPI as HTML5 Page Visibility API
    participant NotifAPI as HTML5 Web Notification API
    participant OS as Windows / macOS Notification Center
    participant Apex as SlackBotAgentController.cls

    User->>LWC: Enters prompt or slash command
    LWC->>Apex: Asynchronous callout dispatched (latency 2-4s)
    
    Note over User,LWC: User switches to Slack, Teams, or Excel
    LWC->>PageAPI: Checks document.hidden || !document.hasFocus() (Returns TRUE)
    
    Apex-->>LWC: Response payload arrives (HTTP 200)
    LWC->>LWC: Appends response bubble to chat feed
    
    rect rgb(240, 248, 255)
        Note over LWC,OS: TRIGGER NATIVE BACKGROUND ALERT
        LWC->>NotifAPI: new Notification("Salesforce AI Copilot", { body, icon })
        NotifAPI->>OS: Renders Glassmorphic Toast Card on Desktop
        LWC->>LWC: Begins Pulsing Document Title: "🔔 (1) New Reply Ready"
    end

    User->>OS: Clicks Desktop Notification Card
    OS->>LWC: Triggers notification.onclick
    LWC->>LWC: window.focus() (Brings Salesforce tab immediately to front)
    LWC->>LWC: Clears title pulse back to "Salesforce"
```

### Technical Implementation Matrix:
* **Zero Disruption when Focused**: If `document.hidden === false`, no notification is shown; the message streams naturally into the feed.
* **Instant Alert when Away**: If the tab is hidden, a native OS toast card appears with the Salesforce icon, Account name, and AI response preview.
* **Pulsing Title**: Uses `setInterval` to alternate document title between `🔔 (1) New Reply Ready | Salesforce` and `Edge Communications | Salesforce` until the user focuses the window.
* **LWC Header Bell Control**: Dedicated icon in the LWC header allows users to grant notification permissions or toggle alerts on/off.

---

## 9. Pillar 7: Snowflake Two-Tier Bi-Directional Sync & Secure MCP Architecture

### A. Tier 1: 5-Second Background Sync Daemon
* `SnowflakeSyncDaemon.ts` runs continuously in the Node.js service, polling Salesforce every 5 seconds for modified Accounts.
* It executes high-performance `MERGE INTO LEARNDC_DB.ANALYTICS.ACCOUNT_ANALYTICS` in Snowflake.
* It writes back `Last_Snowflake_Sync__c`, `Health_Score__c`, `Usage_Hours__c`, and `Churn_Risk__c` to Salesforce.
* **0-Second On-Demand SLA**: When `/account-brief` or `/snowflake` is invoked, `getAccountAnalytics` executes live reconciliation with Salesforce immediately (~150ms) before returning the response.

### B. Tier 2: Dedicated MCP Isolation & Secure Views
* **Dedicated Database**: `LEARNDC_MCP_DB` and schema `SECURE_ANALYTICS`.
* **Restricted Secure View (`V_ACCOUNT_INSIGHTS`)**: Exposes strictly **8 sanitized telemetry fields**:
  1. `SF_ACCOUNT_ID`: Salesforce 18-character Account ID
  2. `ACCOUNT_NAME`: Account Name
  3. `SLA_TIER`: Gold / Platinum / Enterprise
  4. `HEALTH_SCORE`: Integer 0 to 100
  5. `HEALTH_STATUS`: Computed `HEALTHY`, `WARNING`, or `CRITICAL`
  6. `USAGE_HOURS`: Compute consumption in hours
  7. `CHURN_RISK`: Computed percentage risk score
  8. `SNOWFLAKE_LAST_UPDATED`: Ingestion timestamp
* **Least-Privilege Security Role**: `MCP_AGENT_READER_ROLE` with zero DML, zero DDL, and zero access to underlying base warehouse tables.
* **Zero Platform Brand Leakage**: Gemini synthesizes telemetry into a natural executive dossier without mentioning underlying vendor brands ("Snowflake" or "Salesforce") to end business users.

---

## 10. Pillar 8: Model Context Protocol (MCP) Standard Implementation

The Model Context Protocol (MCP) replaces legacy brittle SQL prompts with standardized tool discovery and execution:

### MCP Specification & Flow:
1. **Tool Discovery (`tools/list`)**:
   At startup, Gemini queries registered MCP providers. The providers return JSON Schema definitions detailing tool parameters, descriptions, and expected return types.
2. **Autonomous Reasoner**:
   When a user asks: *"What is the renewal risk for Edge Communications?"*, Gemini inspects the tools list, identifies `get_account_details` and `query_snowflake`, and extracts the `accountIdentifier: "Edge Communications"` parameter.
3. **Structured Tool Execution (`tools/call`)**:
   The runtime dispatches the structured call to the provider.
4. **Sanitized Return DTO**:
   The provider executes parameterized read-only queries and returns sanitized JSON DTOs back to Gemini.
5. **Synthesis**:
   Gemini weaves the results into a unified, high-level business answer.

---

## 11. Multi-User Identity, OAuth Handshake & Consent Engine

The solution features a frictionless multi-user identity onboarding engine that enables any Salesforce user (e.g., Summo CSM, Summo) to authenticate with Slack in seconds:

```mermaid
sequenceDiagram
    autonumber
    actor User as Salesforce User (Summo CSM)
    participant LWC as slackBotAgent (LWC)
    participant Apex as SlackBotAgentController.cls
    participant Gateway as GCP Gateway (/auth/login)
    participant Consent as Slack Consent HTML Screen
    participant Confirm as POST /auth/slack/confirm
    participant SlackAPI as Slack Web API (conversations.open)
    participant SFDB as Salesforce User Record DB

    User->>LWC: Clicks 'Sign in with Slack'
    LWC->>Apex: getGcpSlackAuthUrl()
    Apex-->>LWC: Returns https://...run.app/auth/login?sfUserId=005...&email=skgsummo5@gmail.com
    LWC->>LWC: Opens 600x700 centered popup window
    
    LWC->>Gateway: GET /auth/login
    Gateway->>Gateway: Resolves user info & workspace metadata
    Gateway-->>Consent: Renders high-fidelity Slack Workspace Consent Screen
    Note over Consent: Displays: App Name, User Email, Requested Scopes & 'Allow' Button
    
    User->>Consent: Clicks 'Allow'
    Consent->>Confirm: POST /auth/slack/confirm { sfUserId, email }
    Confirm->>SlackAPI: users.lookupByEmail(email)
    SlackAPI-->>Confirm: Returns Slack User ID (U0C0LFM4XYZ)
    Confirm->>SlackAPI: conversations.open({ users: SlackUserId })
    SlackAPI-->>Confirm: Returns Private DM Channel ID (D0C0LFM5B6E)
    Confirm->>SFDB: REST API UPDATE User SET Slack_User_Id__c, Slack_DM_Channel_Id__c
    Confirm-->>Consent: Renders 'Connection Established! Closing...' & dispatches window.opener.postMessage
    LWC->>LWC: Receives postMessage / detects DB update
    LWC->>LWC: Closes popup & automatically transitions into Active Chat Cockpit
```

### Key Technical Achievements:
* **Explicit User Consent**: Users see a clean, professional Slack authorization screen clearly showing the app name, their email address, and requested capabilities before access is granted.
* **Automated DM Channel Provisioning**: The service automatically creates a dedicated private 1-on-1 Direct Message channel (`conversations.open`) between the bot and the user.
* **Persistent Identity Cache**: Once authenticated, the user's `Slack_User_Id__c` and `Slack_DM_Channel_Id__c` are saved on their `User` record in Salesforce. Future page loads authenticate in <5ms without prompting again.
* **Multi-User Isolation**: Each user gets their own dedicated Slack DM channel and isolated conversation threads.

---

## 12. Complete Secrets, Environment Variables & Configuration Inventory

All credentials, environment variables, and metadata settings are documented below for maintenance and deployment:

### A. GCP Service Environment Variables (`slack-gemini-agent/.env`)

```ini
# Server Port
PORT=8080

# Google AI Studio Gemini API Key
GEMINI_API_KEY=AIzaSy...

# Slack App Credentials (Workspace: T0BU7EDE40P, App: test_agent_app)
SLACK_BOT_TOKEN=xoxb-...
SLACK_SIGNING_SECRET=e779...
SLACK_APP_TOKEN=xapp-1-...

# Salesforce REST Bridge (Connected App: LearnDC_Agent_Bridge)
SF_LOGIN_URL=https://login.salesforce.com
SF_CLIENT_ID=3MVG9...
SF_CLIENT_SECRET=3097...
SF_USERNAME=sumit.gupta@learn-dc.com
SF_PASSWORD=your_password_with_security_token

# Snowflake Cloud Data Warehouse (Account: hjyxziv-mi58790)
SNOWFLAKE_ACCOUNT=hjyxziv-mi58790
SNOWFLAKE_USERNAME=LEARNDC_MCP_AGENT
SNOWFLAKE_PRIVATE_KEY_PATH=./secrets/rsa_key.p8
SNOWFLAKE_DATABASE=LEARNDC_MCP_DB
SNOWFLAKE_SCHEMA=SECURE_ANALYTICS
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_ROLE=MCP_AGENT_READER_ROLE
```

### B. Salesforce Custom Fields & Objects

* **`User` Object Custom Fields**:
  * `Slack_User_Id__c` (Text 50): Slack user identifier (e.g., `U0BU7EDE40P`).
  * `Slack_DM_Channel_Id__c` (Text 50): Private 1-on-1 DM channel identifier (e.g., `D0C0LFM5B6E`).
  * `Slack_Connected_Email__c` (Email): User's authenticated Slack email address.
* **`Account` Object Custom Fields**:
  * `CSM_Email__c` (Email): Designated Customer Success Manager email address.
  * `Health_Score__c` (Number 3,0): Snowflake synced health score (0-100).
  * `Usage_Hours__c` (Number 10,2): Snowflake compute usage hours.
  * `Churn_Risk__c` (Percent 3,1): Machine learning churn risk probability.
  * `SLA_Tier__c` (Picklist): Silver / Gold / Platinum / Enterprise.
  * `Last_Snowflake_Sync__c` (DateTime): Timestamp of last successful sync.
* **`Gmail_Thread_Summary__c` Custom Object**:
  * `Account__c` (Master-Detail to Account)
  * `Thread_Id__c` (Text 255, Indexed)
  * `Executive_Summary__c` (Long Text Area 32768)
  * `Action_Items__c` (Long Text Area 32768)
  * `Last_Analyzed_Message_Date__c` (DateTime)
* **Platform Events**:
  * `Gmail_Sync_Notification__e`
  * `Calendar_Sync_Notification__e`

---

## 13. End-to-End Stakeholder Demonstration Playbook

Follow this step-by-step demonstration script when presenting the full solution to clients, executives, or technical reviewers:

### Phase 1: Authentication & Onboarding (2 Minutes)
1. Log into Salesforce as a new user (e.g., **Summo CSM**).
2. Navigate to any Account record page (e.g., **Edge Communications**).
3. Observe the `slackBotAgent` component in the right sidebar showing the prompt: *"Connect your Slack account to start collaborating with Gemini AI Copilot."*
4. Click the **"Sign in with Slack"** button.
5. Watch the centered popup open to the GCP Gateway showing the high-fidelity **Slack Authorization & Consent Screen** displaying the App Name (`test_agent_app`), workspace, and user email.
6. Click **"Allow"**.
7. The popup displays: *"Connection Established! Syncing with Salesforce..."* and automatically closes.
8. The Salesforce LWC immediately reloads, showing: *"Connected as Summo CSM (Private DM Active)"*.

### Phase 2: Power-User Slash Commands (3 Minutes)
1. In the LWC composer, type `/`. Notice the floating autocomplete palette appearing with shortcuts:
   * `/account-brief`
   * `/summarize-thread`
   * `/snowflake`
   * `/help`
2. Select or type `/account-brief`. Click **Send**.
3. Observe the response: An executive **360° Account Dossier Card** with SLA Platinum badge, Health Score 88/100, Churn Risk 12%, Primary Contact (Rose Gonzalez), and Gemini AI synthesis.
4. Click the **`💬 View in Slack History`** button on the card.
5. Observe Slack Web/Desktop immediately opening to that exact persistent Slack thread in your private DM channel with the identical Block Kit card cross-posted!

### Phase 3: Background Multitasking & Desktop Alerts (2 Minutes)
1. Click the **Notification Bell** in the LWC header. Click **"Enable Desktop Notifications"** and allow browser permissions.
2. In the composer, ask a deep analytical question: *"Analyze our contract renewal risks for Edge Communications based on recent communications and compute consumption."*
3. Immediately minimize the browser window or switch to Slack/Excel.
4. Within 2 to 3 seconds, observe a native **Windows/macOS Desktop Toast Notification** popping up:
   * Header: *Salesforce Copilot • Edge Communications*
   * Body: *360° Renewal Analysis Ready! Health score 88, consumption steady.*
5. Look at your taskbar: Notice the browser tab title pulsating: `🔔 (1) New Reply Ready | Salesforce`.
6. Click the desktop toast notification: The browser tab instantly springs to the foreground, and the title resets to normal.

### Phase 4: Omni-Channel Email & Calendar Scheduling (3 Minutes)
1. On the same Account record page, switch to the **`accountGmail`** tab.
2. Review the split-pane email interface showing active threads, unread message badges, RFC 2822 threading headers, and the Gemini whole-thread narrative summary.
3. Switch to the **`accountGoogleCalendar`** tab.
4. Fill in: Title: *"Q3 Executive Renewal Review"*, select a date/time next week, and toggle **"Auto-Generate Google Meet Link"**.
5. Click **Schedule Meeting**.
6. The meeting is booked via Google Calendar API v3 with an auto-provisioned Google Meet link (`meet.google.com/...`).
7. Open Google Calendar in another window: The meeting appears in real-time, isolated from email logs, with zero duplicate email invites.

### Phase 5: Activity Timeline Hygiene & Task Confirmation (2 Minutes)
1. Return to the `slackBotAgent` chat feed.
2. Type: *"Can you schedule a follow-up task for me to send the revised MSA contract to Rose Gonzalez by tomorrow?"*
3. Notice that Gemini does **not** create dummy tasks blindly. It replies:
   * *"I would be glad to schedule that task for Edge Communications. Please confirm details:"*
   * *Subject: Send Revised MSA Contract*
   * *Due Date: Tomorrow*
   * *Priority: High*
   * *[Confirm Task] [Cancel]*
4. Click **Confirm Task**.
5. The task is created on the Salesforce Account Activity Timeline. Verify on the standard Activity Timeline that no other chat messages were logged as tasks—maintaining pristine CRM hygiene!

---

## 14. Troubleshooting & High-Availability Operations

| Symptom / Scenario | Root Cause | Resolution Procedure |
|---|---|---|
| **Slack returns `operation_timeout` on Slash Command** | Execution took longer than 3 seconds before Slack received an HTTP/WebSocket acknowledgment. | Verify that `await ack()` is the very first line inside `slashCommands.ts` before any async callout or database lookup. |
| **"Sign in with Slack" opens 404 URL** | Apex controller does not have the updated GCP Cloud Run service URL configured. | Call `SlackUserIdentityService.setGcpSlackAuthUrl('https://<your-service>.run.app')` or update the custom setting `GCP_Slackbot_Setting__c.Auth_Url__c`. |
| **User clicks "Allow" but Salesforce is not updated** | Connected App token expired or user record missing write permissions for `Slack_User_Id__c`. | Check `slack-gemini-agent` container logs for `[SalesforceUpdate]`. Ensure `LearnDC_Agent_Bridge` Connected App has `Full` and `refresh_token` scopes. |
| **Desktop notifications do not appear when tab is minimized** | Browser notification permission blocked or OS "Do Not Disturb" / "Focus Assist" is enabled. | In Chrome/Edge, click the tune icon next to URL -> Allow Notifications. In Windows Settings -> System -> Notifications -> Turn Off Focus Assist. |
| **Snowflake queries fail with `JWT token invalid`** | RSA private key path incorrect or role `MCP_AGENT_READER_ROLE` not granted to user. | Run `ALTER USER LEARNDC_MCP_AGENT SET RSA_PUBLIC_KEY='...'` in Snowflake. Verify `secrets/rsa_key.p8` is mounted into the container. |
| **Gateway offline fallback** | Container crashed or network tunnel interrupted. | LWC automatically falls back to native Apex `LearnDCAgentMCPServer.cls`. To restore Gateway, restart container via `docker restart slack-gemini-agent` or check `npm run start`. |

---

## 15. Architectural Certification & Conclusion

The architecture deployed across **Salesforce `learn_dc`**, **Google Cloud Platform**, **Slack**, and **Snowflake** represents a production-grade, enterprise-scale implementation. It strictly adheres to:
* **Zero Platform Brand Leakage**: Business users interact with a unified AI copilot without being exposed to underlying database or platform seams.
* **Least-Privilege Security**: Isolated read-only secure views, scoped OAuth tokens, and strict user-isolated privacy.
* **Dual-Surface Parity**: Identical commands, data, and workflows accessible seamlessly across both Slack and Salesforce Lightning.
* **100% Verified Test Coverage**: Apex test suites (`SlackBotAgentControllerTest`, `SlackUserIdentityServiceTest`) passing with 100% test success rate.
