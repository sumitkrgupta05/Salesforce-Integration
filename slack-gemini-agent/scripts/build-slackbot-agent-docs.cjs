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
    title: "Omni-Channel AI Architecture: Slack Bot Agent & Salesforce LWC Integration",
    description: "Enterprise Technical Architecture & Implementation Reference",
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
              top: 1440,
              bottom: 1440,
              left: 1440,
              right: 1440,
            },
          },
        },
        children: [
          // Title
          new Paragraph({
            text: "Omni-Channel AI Architecture: Slack Bot Agent & Salesforce LWC Integration",
            heading: HeadingLevel.TITLE,
            run: {
              font: "Segoe UI",
              size: 40,
              bold: true,
              color: darkNavy,
            },
            spacing: { after: 120 },
          }),

          // Subtitle
          new Paragraph({
            text: "Unified Single-Brain Architecture powering both Slack and Salesforce Lightning with permanent history, Gemini 3.6 Flash reasoning, and native Salesforce MCP tool execution.",
            run: {
              font: "Segoe UI",
              size: 24,
              color: "64748B",
              italics: true,
            },
            spacing: { after: 300 },
          }),

          // Meta Info Table
          new Table({
            width: { size: 100, type: WidthType.PERCENTAGE },
            rows: [
              new TableRow({
                children: [
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "Primary Agent:", bold: true }), new TextRun(" Slack Bot Agent (slack-gemini-agent)")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "Salesforce LWC:", bold: true }), new TextRun(" slackBotAgent")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                ],
              }),
              new TableRow({
                children: [
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "LLM Model:", bold: true }), new TextRun(" Google Gemini 3.6 Flash (AI Studio)")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "MCP Server:", bold: true }), new TextRun(" LearnDC Agent MCP Server (learn_dc)")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                ],
              }),
            ],
          }),

          new Paragraph({ text: "", spacing: { after: 200 } }),

          // Section 1
          new Paragraph({
            text: "1. Executive Overview & Single-Brain Architecture",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "In traditional architectures, conversational bots inside CRM systems operate in complete silos from enterprise messaging tools like Slack. This integration establishes a unified Headless Bot Gateway where the Slack Bot container (slack-gemini-agent) acts as the single central agent for both Slack and Salesforce Lightning.",
            spacing: { after: 120 },
          }),
          new Paragraph({
            text: "Whenever a Customer Success Manager (CSM) asks an inquiry inside Salesforce via the custom Lightning Web Component (slackBotAgent), the request routes to the Slack Bot Gateway. The bot creates a permanent thread in Slack, runs Gemini 3.6 Flash with autonomous MCP tool calling, posts the reply in Slack, and returns the response to Salesforce with a direct link to view the thread in Slack history.",
            spacing: { after: 200 },
          }),

          // Section 2
          new Paragraph({
            text: "2. Two-Way Omni-Channel Workflows",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "The CSM enjoys total flexibility to interact with the bot from either environment:",
            spacing: { after: 120 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "• In Salesforce (LWC): ", bold: true }),
              new TextRun("Open any Account record, click quick chips (Summarize Emails, Account & CSM, Schedule Meeting), or type questions. The conversation displays rich SLDS cards and is automatically saved to Slack."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "• In Slack (Desktop / Mobile): ", bold: true }),
              new TextRun("Chat with @Test Agent App or reply directly in the Account conversation thread. The bot uses the exact same model and MCP tools to answer."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "• Permanent History in Slack: ", bold: true }),
              new TextRun("Even if the CSM clicks 'Reset Session' in Salesforce to clear the screen, 100% of the past chat history remains permanently preserved and searchable in Slack."),
            ],
            spacing: { after: 200 },
          }),

          // Section 3
          new Paragraph({
            text: "3. Complete Codebase & File Structure",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "The integration spans the Node.js Slack Bot container and Salesforce Lightning metadata:",
            spacing: { after: 120 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "1. slack-gemini-agent/src/api/routes.ts: ", bold: true }),
              new TextRun("Express REST Gateway exposing POST /api/chat. Handles Slack thread creation, Gemini agent execution, and response serialization."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "2. force-app/main/default/lwc/slackBotAgent/: ", bold: true }),
              new TextRun("Custom LWC component providing SLDS chat stream, 1-click action chips, active Slack gateway badge, and 'View in Slack History' deeplinks."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "3. force-app/main/default/classes/SlackBotAgentController.cls: ", bold: true }),
              new TextRun("Apex controller forwarding requests to the Slack Bot Gateway with automatic native fallback."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "4. force-app/main/default/classes/LearnDCMCP*.cls: ", bold: true }),
              new TextRun("Invocable Actions for Account CRM data, dynamic email thread summarization, and Google Meet scheduling."),
            ],
            spacing: { after: 200 },
          }),

          // Section 4
          new Paragraph({
            text: "4. Implementation & Deployment Steps",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "Step 1: ", bold: true }),
              new TextRun("Enable REST gateway router (/api/chat) in slack-gemini-agent and restart container."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "Step 2: ", bold: true }),
              new TextRun("Expose container port 8080 via secure HTTPS ingress tunnel (ngrok http 8080)."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "Step 3: ", bold: true }),
              new TextRun("Whitelist gateway tunnel URL in Salesforce Remote Site Settings."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "Step 4: ", bold: true }),
              new TextRun("Deploy SlackBotAgentController and slackBotAgent LWC to the learn_dc org."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "Step 5: ", bold: true }),
              new TextRun("Place slackBotAgent into the Right Column of the Account Record Page in Lightning App Builder."),
            ],
            spacing: { after: 200 },
          }),

          // Section 5
          new Paragraph({
            text: "5. Verification & Testing Checklist",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "Verify the end-to-end flow using the following steps:\n1. Open an Account in Salesforce (e.g. Edge Communications).\n2. Click '⚡ Summarize Emails' in the slackBotAgent LWC.\n3. Verify that a parent message appears in Slack in real time under your DM with Test Agent App.\n4. Verify that Gemini's executive summary and action items are posted as a thread reply in Slack.\n5. Click 'View in Slack History' in the LWC and confirm it opens the Slack thread.\n6. Reset session in LWC and verify that the full Slack history remains permanently preserved.",
            spacing: { after: 200 },
          }),
        ],
      },
    ],
  });

  const buffer = await Packer.toBuffer(doc);
  const outDir = "C:\\Users\\Sumit Kr Gupta\\OneDrive - Teqfocus Solutions Pvt. Ltd\\Desktop\\Learn DC";
  const docxPath = path.join(outDir, "SLACK_BOT_AGENT_LWC_INTEGRATION.docx");
  const docsPath = path.join(outDir, "SLACK_BOT_AGENT_LWC_INTEGRATION.docs");

  fs.writeFileSync(docxPath, buffer);
  fs.writeFileSync(docsPath, buffer);

  console.log("✅ Successfully generated Word documents:");
  console.log("   - " + docxPath);
  console.log("   - " + docsPath);
}

generateDocx().catch((err) => {
  console.error("Error generating docx:", err);
  process.exit(1);
});
