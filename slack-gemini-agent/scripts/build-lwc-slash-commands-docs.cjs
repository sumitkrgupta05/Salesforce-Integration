const fs = require('fs');
const path = require('path');
const { Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell, WidthType, ShadingType } = require('docx');

async function generateDocx() {
  const primaryBlue = "1A73E8";
  const darkNavy = "0F172A";
  const textGrey = "334155";
  const lightBg = "F8FAFC";

  const doc = new Document({
    creator: "Sumit Kr Gupta - Teqfocus",
    title: "Complete Blueprint: Integrating Slack Slash Commands into Salesforce LWC",
    description: "Architectural blueprint and code guide for slackBotAgent Slash Commands",
    styles: {
      default: {
        document: {
          run: {
            font: "Segoe UI",
            size: 22,
            color: textGrey,
          },
        },
      },
    },
    sections: [
      {
        properties: {
          page: {
            margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 },
          },
        },
        children: [
          new Paragraph({
            text: "Integrating Slack Slash Commands into Salesforce LWC",
            heading: HeadingLevel.TITLE,
            run: { font: "Segoe UI", size: 38, bold: true, color: darkNavy },
            spacing: { after: 120 },
          }),
          new Paragraph({
            text: "Complete technical guide, architectural sequence, frontend autocomplete popover, and Apex controller command router for slackBotAgent.",
            run: { font: "Segoe UI", size: 24, color: "64748B", italics: true },
            spacing: { after: 300 },
          }),
          new Table({
            width: { size: 100, type: WidthType.PERCENTAGE },
            rows: [
              new TableRow({
                children: [
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "Component:", bold: true }), new TextRun(" slackBotAgent (LWC)")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "Controller:", bold: true }), new TextRun(" SlackBotAgentController.cls")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                ],
              }),
              new TableRow({
                children: [
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "Supported Commands:", bold: true }), new TextRun(" /account-brief, /summarize-thread, /help")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                  new TableCell({
                    children: [new Paragraph({ children: [new TextRun({ text: "Sync Target:", bold: true }), new TextRun(" Slack DM Thread & Salesforce Task")] })],
                    shading: { fill: lightBg, type: ShadingType.CLEAR },
                  }),
                ],
              }),
            ],
          }),
          new Paragraph({ text: "", spacing: { after: 200 } }),
          new Paragraph({
            text: "1. Architecture Overview",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "The integration bridges Slack power-user slash commands into Salesforce. When a user executes a slash command in the LWC, the Apex controller parses the command, evaluates record context, executes the LearnDC MCP tools, displays rich cards, and automatically cross-posts to Slack while logging an Activity Timeline Task.",
            spacing: { after: 160 },
          }),
          new Paragraph({
            text: "2. Key Features Implemented",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "• Floating Command Palette: ", bold: true }),
              new TextRun("Typing '/' triggers an autocomplete popover displaying commands and descriptions."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "• Smart Account Context: ", bold: true }),
              new TextRun("Running /account-brief automatically identifies the active Account page record without re-typing."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "• Dynamic Gemini Summarization: ", bold: true }),
              new TextRun("Running /summarize-thread [ID] performs real-time email summarization with Gemini 3.6 Flash."),
            ],
            spacing: { after: 80 },
          }),
          new Paragraph({
            children: [
              new TextRun({ text: "• 100% History Sync: ", bold: true }),
              new TextRun("All commands and responses are threaded into Slack and logged into Salesforce Tasks."),
            ],
            spacing: { after: 160 },
          }),
          new Paragraph({
            text: "3. Blueprint for Future Commands",
            heading: HeadingLevel.HEADING_1,
            run: { bold: true, color: primaryBlue, size: 28 },
            spacing: { before: 240, after: 120 },
          }),
          new Paragraph({
            text: "To add new slash commands: 1) Add item to slackBotAgent.html popover, 2) Add handler block in SlackBotAgentController.executeSlashCommand, 3) Add unit test in SlackBotAgentControllerTest.cls.",
            spacing: { after: 160 },
          }),
        ],
      },
    ],
  });

  const buffer = await Packer.toBuffer(doc);
  const outDir = "C:\\Users\\Sumit Kr Gupta\\OneDrive - Teqfocus Solutions Pvt. Ltd\\Desktop\\Learn DC\\docs";
  const docxPath = path.join(outDir, "LWC_SLACK_SLASH_COMMANDS_INTEGRATION.docx");
  const docsPath = path.join(outDir, "LWC_SLACK_SLASH_COMMANDS_INTEGRATION.docs");

  fs.writeFileSync(docxPath, buffer);
  fs.writeFileSync(docsPath, buffer);

  console.log("✅ Successfully generated LWC Slash Commands Word documents:");
  console.log("   - " + docxPath);
  console.log("   - " + docsPath);
}

generateDocx().catch((err) => {
  console.error("Error generating docx:", err);
  process.exit(1);
});
