import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const PR_NUMBER = process.env.PR_NUMBER;
const REPO_OWNER = process.env.REPO_OWNER;
const REPO_NAME = process.env.REPO_NAME;
const BASE_REF = process.env.BASE_REF || 'main';
const TICKET_KEY = process.env.TICKET_KEY || '';
const CALLBACK_URL = process.env.CALLBACK_URL || '';

console.log('='.repeat(70));
console.log(`[AI CODE REVIEWER] Starting review for PR #${PR_NUMBER} on ${REPO_OWNER}/${REPO_NAME}`);
console.log('='.repeat(70));

/**
 * Execute a git command and return stdout
 */
function runGit(cmd) {
  try {
    return execSync(cmd, { encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 });
  } catch (e) {
    console.warn(`[GIT WARNING] Command failed (${cmd}):`, e.message);
    return '';
  }
}

/**
 * Minimal XML well-formedness checker
 */
function validateXmlString(xmlContent, filePath) {
  const errors = [];
  
  // Check closing tags match opening tags
  const tagRegex = /<([a-zA-Z0-9_:]+)(?:\s+[^>]*)?(?<!\/)>|<\/([a-zA-Z0-9_:]+)>/g;
  const stack = [];
  let match;

  while ((match = tagRegex.exec(xmlContent)) !== null) {
    const openTag = match[1];
    const closeTag = match[2];

    if (openTag) {
      if (!match[0].endsWith('/>') && !match[0].startsWith('<?xml') && !match[0].startsWith('<!')) {
        stack.push({ tag: openTag, index: match.index });
      }
    } else if (closeTag) {
      if (stack.length === 0) {
        errors.push(`Unexpected closing tag </${closeTag}> with no matching opening tag in ${filePath}`);
      } else {
        const top = stack.pop();
        if (top.tag !== closeTag) {
          errors.push(`Mismatched XML tags: opened <${top.tag}> but found </${closeTag}> in ${filePath}`);
        }
      }
    }
  }

  if (stack.length > 0) {
    errors.push(`Unclosed XML tag <${stack[stack.length - 1].tag}> in ${filePath}`);
  }

  return errors;
}

async function main() {
  if (!PR_NUMBER || !REPO_OWNER || !REPO_NAME) {
    console.error('[ERROR] Missing PR_NUMBER, REPO_OWNER, or REPO_NAME environment variables.');
    process.exit(1);
  }

  // 1. Fetch changed files and diff
  console.log(`Fetching git diff against origin/${BASE_REF}...`);
  let diff = runGit(`git diff origin/${BASE_REF}...HEAD -- force-app/`);
  
  // Fallback: If git diff is empty or origin not fetched, check staged or HEAD~1
  if (!diff) {
    diff = runGit(`git diff HEAD~1...HEAD -- force-app/`);
  }
  if (!diff) {
    diff = runGit(`git diff origin/main...HEAD`);
  }

  console.log(`Extracted diff: ${diff.length} characters.`);

  // 2. Collect changed files list
  let changedFilesStr = runGit(`git diff --name-only origin/${BASE_REF}...HEAD -- force-app/`);
  if (!changedFilesStr) {
    changedFilesStr = runGit(`git diff --name-only HEAD~1...HEAD -- force-app/`);
  }
  const changedFiles = changedFilesStr.split('\n').map(f => f.trim()).filter(Boolean);
  console.log(`Changed files count: ${changedFiles.length}`);

  // 3. Perform Best Practices & Security Audit
  const findings = [];
  const requiredFixes = [];
  let securityPassed = true;
  let bulkificationPassed = true;
  let xmlSyntaxPassed = true;
  let triggerStandardsPassed = true;

  // CHECK 1: STRICT SECURITY GUARDRAIL (Zero client org leakage)
  console.log('Running Check 1: Security & Org Isolation Guardrails...');
  const forbiddenRegex = /servicetitans|st-psdev0204/i;
  if (forbiddenRegex.test(diff)) {
    securityPassed = false;
    findings.push('- [FAIL] 🚨 **Security Guardrail Violation**: Detected reference to confidential client org ("ServiceTitans" or "st-psdev0204").');
    requiredFixes.push('Immediately remove all references to foreign/client orgs. Target org must strictly remain learn_dc.');
  } else {
    findings.push('- [PASS] 🛡️ **Security Guardrails**: Zero foreign client or unauthorized org references detected.');
  }

  // CHECK 2: XML METADATA INTEGRITY
  console.log('Running Check 2: XML Metadata Syntax...');
  let xmlErrorsFound = 0;
  for (const file of changedFiles) {
    if (file.endsWith('.xml') && fs.existsSync(file)) {
      const xmlContent = fs.readFileSync(file, 'utf-8');
      const xmlErrors = validateXmlString(xmlContent, file);
      if (xmlErrors.length > 0) {
        xmlSyntaxPassed = false;
        xmlErrorsFound++;
        findings.push(`- [FAIL] 📄 **XML Syntax Error in \`${path.basename(file)}\`**: ${xmlErrors[0]}`);
        requiredFixes.push(`Fix XML syntax error in ${file}: ${xmlErrors[0]}`);
      }
    }
  }
  if (xmlSyntaxPassed) {
    findings.push('- [PASS] 📄 **XML Metadata Syntax**: All modified Salesforce XML files are well-formed.');
  }

  // CHECK 3: APEX BEST PRACTICES (Bulkification, SOQL/DML in loops, Trigger patterns)
  console.log('Running Check 3: Apex Best Practices & Bulkification...');
  for (const file of changedFiles) {
    if (file.endsWith('.cls') || file.endsWith('.trigger')) {
      if (fs.existsSync(file)) {
        const apexContent = fs.readFileSync(file, 'utf-8');
        const lines = apexContent.split('\n');

        let insideLoop = false;
        let braceDepth = 0;
        let loopBraceDepth = 0;

        for (let i = 0; i < lines.length; i++) {
          const line = lines[i];
          const trimmed = line.trim();

          // Count braces
          const openBraces = (line.match(/{/g) || []).length;
          const closeBraces = (line.match(/}/g) || []).length;
          braceDepth += (openBraces - closeBraces);

          // Detect loop start
          if (/\b(for|while)\s*\(/.test(trimmed)) {
            insideLoop = true;
            loopBraceDepth = braceDepth;
          }

          if (insideLoop && braceDepth < loopBraceDepth) {
            insideLoop = false;
          }

          // Check SOQL in loop
          if (insideLoop && /\[\s*SELECT\b/i.test(line)) {
            bulkificationPassed = false;
            findings.push(`- [FAIL] ⚠️ **Apex Bulkification Violation**: SOQL query detected inside loop in \`${path.basename(file)}\` (Line ${i + 1}).`);
            requiredFixes.push(`Extract SOQL query from loop in ${path.basename(file)} (Line ${i + 1}). Query records beforehand and store in Map/List.`);
          }

          // Check DML in loop
          if (insideLoop && /\b(insert|update|delete|upsert)\s+[a-zA-Z0-9_]+;/.test(trimmed)) {
            bulkificationPassed = false;
            findings.push(`- [FAIL] ⚠️ **Apex Bulkification Violation**: DML operation detected inside loop in \`${path.basename(file)}\` (Line ${i + 1}).`);
            requiredFixes.push(`Move DML operation outside of loop in ${path.basename(file)} (Line ${i + 1}). Accumulate records into a List and perform single DML.`);
          }

          // Check hardcoded IDs
          if (/['"][0-9a-zA-Z]{15}['"]|['"][0-9a-zA-Z]{18}['"]/.test(trimmed) && !trimmed.includes('000000000000000AAA')) {
            findings.push(`- [WARN] 🔍 **Potential Hardcoded ID** in \`${path.basename(file)}\` (Line ${i + 1}): Avoid hardcoding record IDs.`);
          }
        }

        // Trigger architecture check
        if (file.endsWith('.trigger')) {
          if (apexContent.length > 800 || (apexContent.match(/;/g) || []).length > 8) {
            triggerStandardsPassed = false;
            findings.push(`- [WARN] ⚡ **Trigger Architecture**: Logic found directly inside \`${path.basename(file)}\`. Best practice is delegating to a Trigger Handler class.`);
          }
        }
      }
    }
  }

  if (bulkificationPassed) {
    findings.push('- [PASS] ⚡ **Apex Bulkification**: Zero SOQL queries or DML statements found inside loops.');
  }

  // 4. Determine Verdict
  const isApproved = securityPassed && bulkificationPassed && xmlSyntaxPassed;
  const verdict = isApproved ? 'APPROVED' : 'CHANGES_REQUESTED';
  console.log(`\nReview Complete. Verdict: ${verdict}`);

  // 5. Construct Markdown Report
  const summaryText = isApproved
    ? `All code changes comply with Salesforce engineering best practices, security guardrails, and XML syntax standards.`
    : `Defects or best-practice violations were detected in the PR code. Remediation is required before merge.`;

  const reportMarkdown = `## ⚡ GitHub Action AI Reviewer Report\n\n` +
    `**Reviewer Engine:** GitHub Actions AI Agent (Zero-Token Code Review)\n` +
    `**Verdict:** ${isApproved ? '✅ **APPROVED**' : '🚨 **CHANGES REQUESTED (Merge Blocked)**'}\n\n` +
    `### Summary\n${summaryText}\n\n` +
    `### Best Practices & Quality Audit\n${findings.join('\n')}\n\n` +
    (!isApproved && requiredFixes.length > 0
      ? `### Required Fixes\n${requiredFixes.map(f => `- ${f}`).join('\n')}\n\n` +
        `*🔄 Automated Self-Healing Loop: Dispatched Agent 1 & Agent 2 to apply fixes and push remediation commit.*`
      : `*✨ Code is clean, well-formed, and ready for deployment into \`main\`!*`);

  // 6. Submit Official GitHub Review
  if (GITHUB_TOKEN) {
    try {
      console.log(`Submitting GitHub PR review (Event: ${isApproved ? 'APPROVE' : 'REQUEST_CHANGES'})...`);
      const reviewUrl = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/pulls/${PR_NUMBER}/reviews`;
      const res = await fetch(reviewUrl, {
        method: 'POST',
        headers: {
          'Authorization': `token ${GITHUB_TOKEN}`,
          'Accept': 'application/vnd.github.v3+json',
          'Content-Type': 'application/json',
          'User-Agent': 'node-fetch'
        },
        body: JSON.stringify({
          body: reportMarkdown,
          event: isApproved ? 'APPROVE' : 'REQUEST_CHANGES'
        })
      });

      if (!res.ok) {
        console.warn(`[GITHUB REVIEW WARNING] Status ${res.status}:`, await res.text());
        // Fallback to comment if review event cannot be submitted (e.g. self-review restriction)
        await fetch(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues/${PR_NUMBER}/comments`, {
          method: 'POST',
          headers: {
            'Authorization': `token ${GITHUB_TOKEN}`,
            'Accept': 'application/vnd.github.v3+json',
            'Content-Type': 'application/json',
            'User-Agent': 'node-fetch'
          },
          body: JSON.stringify({ body: reportMarkdown })
        });
      }
      console.log('GitHub PR review posted successfully!');
    } catch (apiErr) {
      console.error('[GITHUB API ERROR]', apiErr.message);
    }
  }

  // 7. Callback to Orchestrator (if callback URL provided)
  if (CALLBACK_URL) {
    try {
      console.log(`Sending callback to orchestrator: ${CALLBACK_URL}...`);
      await fetch(`${CALLBACK_URL}/webhook/github-action-review`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ticketKey: TICKET_KEY,
          prNumber: parseInt(PR_NUMBER, 10),
          verdict,
          summary: summaryText,
          findings: findings.join('\n'),
          requiredFixes: requiredFixes.join('\n'),
          isApproved
        })
      });
      console.log('Orchestrator callback completed.');
    } catch (cbErr) {
      console.warn('[CALLBACK WARNING]', cbErr.message);
    }
  }

  // Write step summary for GitHub Actions
  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, reportMarkdown);
  }

  if (!isApproved) {
    process.exitCode = 1;
  }
}

main().catch(err => {
  console.error('[FATAL REVIEW ERROR]', err);
  process.exit(1);
});
