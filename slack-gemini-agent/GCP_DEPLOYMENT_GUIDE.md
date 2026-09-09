# Google Cloud Run Deployment Guide: Managed Gemini Agent for Slack

This guide provides the exact steps to deploy the **Slack Gemini Agent** as a fully managed, 24/7 serverless service on **Google Cloud Run** in your GCP project `exalted-justice-507211-v9`.

---

## 1. Architecture on GCP

* **Container Runtime**: Google Cloud Run (Serverless, fully managed container platform).
* **Communication**: Outbound WebSocket (`wss://`) over Slack Socket Mode — **zero public IP or webhook domain setup required**.
* **Health Probes**: Built-in HTTP server listening on `0.0.0.0:8080` (`GET /health`), automatically satisfying Cloud Run container readiness checks.
* **Continuous Streaming**: Configured with `--min-instances 1` and `--no-cpu-throttling` to keep the WebSocket active 24/7.

---

## 2. Option A: 1-Click Deployment via Google Cloud Shell (Recommended)

Google Cloud Shell has `gcloud`, `docker`, and permissions pre-installed and authenticated to your project.

### Step 1: Open Cloud Shell
1. Go to [console.cloud.google.com](https://console.cloud.google.com/) and select project:
   `exalted-justice-507211-v9`
2. Click the **Activate Cloud Shell** icon (top-right `>_` icon).

### Step 2: Upload or Clone the `slack-gemini-agent` Folder
In Cloud Shell, upload the `slack-gemini-agent` directory (or clone your repo), then navigate to it:
```bash
cd slack-gemini-agent
```

### Step 3: Run the Cloud Run Build & Deploy Command
Run the following single command in Cloud Shell:

```bash
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
  --set-env-vars "GEMINI_API_KEY=YOUR_GEMINI_API_KEY,GEMINI_MODEL=gemini-3.6-flash,SLACK_BOT_TOKEN=YOUR_SLACK_BOT_TOKEN,SLACK_APP_TOKEN=YOUR_SLACK_APP_TOKEN,SLACK_SIGNING_SECRET=YOUR_SLACK_SIGNING_SECRET"
```

Cloud Run will automatically:
1. Build the multi-stage Docker container using Google Cloud Build.
2. Store the image in Google Artifact Registry.
3. Deploy and launch the service with health checks passing.
4. Establish the 24/7 Socket Mode connection to Slack.

---

## 3. Option B: Deployment via GCP Console (Web UI)

If you prefer using the Google Cloud web interface:

1. Open **Cloud Run** in the GCP Console:
   `https://console.cloud.google.com/run?project=exalted-justice-507211-v9`
2. Click **Create Service**.
3. **Service name**: `slack-gemini-agent`
4. **Region**: `us-central1` (or your preferred region)
5. Under **Deployment type**:
   - Select **Continuously deploy from a repository** (e.g. GitHub), or build the container image.
6. Under **Scaling**:
   - **Minimum instances**: `1` *(Critical: keeps the WebSocket listener connected 24/7)*.
   - **Maximum instances**: `2`
7. Under **Container(s) ➔ Variables & Secrets**:
   - Add environment variables:
     - `GEMINI_API_KEY`
     - `GEMINI_MODEL` = `gemini-3.6-flash`
     - `SLACK_BOT_TOKEN`
     - `SLACK_APP_TOKEN`
     - `SLACK_SIGNING_SECRET`
8. Under **Container(s) ➔ Resources**:
   - Check: **CPU is always allocated**
   - Memory: `512 MiB`
9. Click **Create**!

---

## 4. Verification & Health Monitoring

Once deployed on Cloud Run:
* View live logs in **Cloud Logging** directly in GCP Console. You will see:
  ```
  ⚡️ Slack Gemini Agent is connected and running in Socket Mode!
  🤖 Using LLM Model: gemini-3.6-flash
  🏥 Health check server listening on 0.0.0.0:8080 (Google Cloud Run compatible)
  [INFO] socket-mode:SocketModeClient:0 Now connected to Slack
  ```
* Test sending messages in Slack: the bot responds 24/7 from Google Cloud without requiring any local computer or process running!
