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
    title: "Complete Guide & Blueprint: Implementing Slack Slash Commands",
    description: "Technical Guide for /account-brief and /summarize-thread Slack Commands",
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
            text: "Complete Blueprint: Implementing Slack Slash Commands",
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
            text: "Step-by-step technical architecture, Socket Mode execution, and Block Kit rendering for /account-brief and /summarize-thread commands connected to Salesforce MCP and Gemini.",
            run: {
              font: "Segoe UI",
              size: 24,
              color: "64748B",
              italics: true,
            },
            spacing: { after: 300 },
          }),

          // Meta Table
          new Table({
            width: { size: 100, type: WidthType.PERCENTAGE },
            rows: [
              new TableRow({
                children: [
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "Commands:", bold: true }), new TextRun(" /account-brief & /summarize-thread")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "App Mode:", bold: true }), new TextRun(" Slack Bolt (Socket Mode WebSocket)")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                ],
              }),
              new TableRow({
                children: [
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "AI Model:", bold: true }), new TextRun(" Google AI Studio (Gemini 3.6 Flash)")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "CRM Tools:", bold: true }), new TextRun(" LearnDC Agent MCP Server")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                ],
              }),
            ],
          }),

          new Paragraph({ text: "", spacing: { after: 200 } }),

          // Section 1
          new Paragraph({
            text: "1. Overview & Capabilities of the Slash Commands",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "• /account-brief [Account Name]: ", bold: true }),
              new TextRun("Provides an instant 1-shot executive dossier for any account before customer calls. In a single command, it fetches live CRM vitals (Industry, CSM Email, Primary Contact & Title) and the latest customer email intelligence summary with pending action items."),
            ],
            spacing: { after: 120 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "• /summarize-thread [Thread ID]: ", bold: true }),
              new TextRun("Performs dynamic Gemini AI summarization on any customer email thread. It parses the complete chronological message exchange and synthesizes Executive Summary, Key Discussion Points, and Action Items."),
            ],
            spacing: { after: 200 },
          }),

          // Section 2
          new Paragraph({
            text: "2. Socket Mode Advantage (Zero Webhooks Needed)",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "Because the Slack App is operating in Socket Mode, slash commands are delivered directly through the established secure WebSocket connection. Developers do not need to configure public Request URLs, manage webhooks, or open incoming firewall ports.",
            spacing: { after: 200 },
          }),

          // Section 3
          new Paragraph({
            text: "3. Step-by-Step Configuration in Slack Dashboard",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "1. Go to https://api.slack.com/apps and select 'Test Agent App'.\n2. Navigate to 'Slash Commands' in the left sidebar.\n3. Click 'Create New Command' and enter /account-brief with hint [Account Name].\n4. Click 'Create New Command' again and enter /summarize-thread with hint [Thread ID].\n5. Navigate to 'Install App' and click 'Reinstall to Workspace' to authorize the 'commands' scope.",
            spacing: { after: 200 },
          }),

          // Section 4
          new Paragraph({
            text: "4. Implementation Architecture & The 3-Second Rule",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "Slack enforces a strict 3000ms acknowledgment window for slash commands. In your handler code, you must immediately call 'await ack()'. Once acknowledged, the handler invokes the LearnDC Agent MCP Server tools and responds with rich Block Kit formatting using 'await respond(...)'.",
            spacing: { after: 200 },
          }),

          // Section 5
          new Paragraph({
            text: "5. Future Extensibility Blueprint",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "Whenever future slash commands are required, use the 3-step boilerplate pattern:\n1. Register command in Slack App Dashboard.\n2. Add app.command('/name', ...) handler with await ack() and MCP action invocation.\n3. Rebuild and restart the container.",
            spacing: { after: 200 },
          }),
        ],
      },
    ],
  });

  const buffer = await Packer.toBuffer(doc);
  const outDir = "C:\\Users\\Sumit Kr Gupta\\OneDrive - Teqfocus Solutions Pvt. Ltd\\Desktop\\Learn DC";
  const docxPath = path.join(outDir, "SLACK_SLASH_COMMANDS_GUIDE.docx");
  const docsPath = path.join(outDir, "SLACK_SLASH_COMMANDS_GUIDE.docs");

  fs.writeFileSync(docxPath, buffer);
  fs.writeFileSync(docsPath, buffer);

  console.log("✅ Successfully generated Slash Commands Word documents:");
  console.log("   - " + docxPath);
  console.log("   - " + docsPath);
}

generateDocx().catch((err) => {
  console.error("Error generating docx:", err);
  process.exit(1);
});
