# Google AI Studio Custom Gemini Agent for Slack

This module contains the custom Google AI Studio / Gemini Agent and its Slack integration service. It is completely isolated from the Salesforce `force-app` metadata.

---

## 1. Google AI Studio Agent Configuration (Phase 1)

### Option A: Testing via Google AI Studio Web UI
1. Navigate to [Google AI Studio](https://aistudio.google.com/).
2. Click **Create New Prompt** ➔ **Chat Prompt**.
3. Set the **Model** to `gemini-2.0-flash`.
4. In **System Instructions**, paste the contents of `src/gemini/prompt.ts`.
5. Under **Tools**, add the declared function schemas from `src/gemini/tools.ts`:
   - `get_current_time`
   - `get_crm_account`
   - `summarize_customer_thread`
   - `schedule_calendar_meeting`
6. Click **Get API key** and copy your API key.

---

### Option B: Direct Testing via Code & CLI (Fastest)
1. Open `.env` in `slack-gemini-agent/` and set:
   ```env
   GEMINI_API_KEY=AIzaSy...
   ```
2. Run the Phase 1 test suite:
   ```bash
   npm run test:agent
   ```
   This will verify:
   - ✅ Persona & System Prompt responses.
   - ✅ Autonomous tool calling execution (`get_current_time` and `get_crm_account`).
   - ✅ Multi-turn conversation memory across conversational turns.

---

## 2. 24/7 Background Container Service (Alternative B)

The bot runs inside a lightweight, production-grade Docker container (`slack-gemini-agent-service`) with an auto-restart policy:

```bash
# View live logs
npm run container:logs

# Check status
npm run container:status

# Restart container
npm run container:restart

# Stop container
npm run container:stop

# Start container
npm run container:start
```

* **Auto-Restart Policy**: Configured with `--restart unless-stopped`, so it automatically resumes after computer reboots or Docker Desktop restarts.
* **Zero Cost**: Runs entirely on your machine via outbound Slack Socket Mode (`wss://`). Requires no public IP, no domain, and no cloud billing.
* **HTTP Health Check**: Responds at `http://localhost:8080/health` with `{"status":"healthy"}`.

---

## 3. Salesforce OAuth Handshake & Slack Consent Gateway

The service provides automated OAuth 2.0 endpoints for connecting Salesforce CSM users:

* **`GET /auth/login`**:
  Receives `sfUserId`, `sfOrgId`, and `email`. If `SLACK_CLIENT_ID` is set, redirects 302 to Slack authorize endpoint; otherwise renders the Slack Workspace Consent Screen with requested permissions and the mandatory **"Allow" (Accept)** button.
* **`POST /auth/slack/confirm`**:
  Triggered when the user clicks "Allow" on the Slack consent screen. Provisions the private 1-on-1 DM channel (`conversations.open`), updates the Salesforce `User` record via REST API, renders self-closing HTML, and dispatches `SLACK_AUTH_SUCCESS` to `window.opener`.
* **`GET /auth/slack/callback`**:
  Standard OAuth 2.0 callback for production deployments exchanging authorization `code` with Slack Web API.

