# Implementation Plan: SCRUM-12 - Create 2 fields on Contact (QA Remediation Cycle)

## QA Feedback & Remediation Scope
- **QA Feedback / Bug Report:**
  > "okay but here have you tested that these fields metadata have been deployed into the 'Medical Information' section in Contact Layout or not."
- **Root Cause & Gap Analysis:**
  - In the initial implementation of Ticket SCRUM-12, custom fields (`Last_Health_Checkup_Date__c`, `Health_Insurance_Provider__c`) and page layout (`Contact-Contact Layout.layout-meta.xml`) were deployed to org `learn_dc`.
  - However, post-deployment verification only tested the `CustomField` Tooling API entity (`SELECT Id, DeveloperName FROM CustomField`).
  - No automated validation or Tooling API test was executed to verify that the `Contact Layout` metadata in org `learn_dc` actually contains both fields within the `Medical Information` section.
- **Remediation Directives for Agent 2 (Builder):**
  1. Validate that `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml` contains `Last_Health_Checkup_Date__c` (Left Column) and `Health_Insurance_Provider__c` (Right Column) in the `Medical Information` section.
  2. Execute an automated Tooling API layout verification test against org `learn_dc` to retrieve and inspect `Contact Layout` metadata (`00hfj00000IAYXnAAP`).
  3. Verify that `Medical Information` section exists and explicitly contains `Last_Health_Checkup_Date__c` in Column 1 (Left) and `Health_Insurance_Provider__c` in Column 2 (Right).
  4. If any discrepancy is found in org `learn_dc`, redeploy `Contact-Contact Layout.layout-meta.xml` to `learn_dc`.
  5. Update `agent-context/tickets/SCRUM-12/log.md` with the layout metadata query results and explicit verification proof.

---

## 1. Context & Dependencies
- **Existing Metadata Referenced from MEMORY.md:**
  - Standard `Contact` object (`force-app/main/default/objects/Contact`).
  - Baseline Contact custom fields:
    - `Blood_Group__c` (Picklist: A+, A-, B+, B-, AB+, AB-, O+, O-)
    - `Date_of_Birth__c` (Date)
    - `Height_cm__c` (Number 5, 2)
    - `Weight_kg__c` (Number 5, 2)
    - `Emergency_Contact_Phone__c` (Phone)
    - `Allergies__c` (Long Text Area: 32768, 3 visible lines)
    - `Primary_Physician__c` (Text 255)
    - `Chronic_Conditions__c` (Long Text Area: 32768, 3 visible lines)
    - `Current_Medications__c` (Long Text Area: 32768, 3 visible lines)
  - Target Page Layout: `Contact-Contact Layout.layout-meta.xml` located at `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`.
  - Existing `Medical Information` 2-column layout section under `Contact-Contact Layout`.
- **Target Custom Fields:**
  - `Last_Health_Checkup_Date__c` (Date)
  - `Health_Insurance_Provider__c` (Text 255)
- **Target Layout Placement:**
  - Expose both fields within the `Medical Information` section on `Contact-Contact Layout`.

---

## 2. Metadata Changes & Layout Configuration
- **Target Object:** `Contact` (`force-app/main/default/objects/Contact`)
- **Fields Specification:**
  - **Field 1:** `Last_Health_Checkup_Date__c`
    - **Type:** `Date`
    - **Label:** `Last Health Checkup Date`
    - **Description:** `Timestamp of the most recent health checkup for the contact.`
    - **Inline Help Text:** `Enter the date of the contact's last health checkup (e.g., 10-Sep-2026).`
    - **Required:** `false`
  - **Field 2:** `Health_Insurance_Provider__c`
    - **Type:** `Text`
    - **Label:** `Health Insurance Provider`
    - **Length:** `255`
    - **Description:** `Name of the contact's health insurance provider (e.g., Star Health Insurance).`
    - **Inline Help Text:** `Enter the contact's health insurance provider.`
    - **Required:** `false`
- **Page Layout Target Structure (`Contact-Contact Layout`):**
  - **Section:** `Medical Information` (Style: `TwoColumnsLeftToRight`)
  - **Left Column Layout Items:**
    1. `Blood_Group__c` (Edit)
    2. `Date_of_Birth__c` (Edit)
    3. `Emergency_Contact_Phone__c` (Edit)
    4. `Allergies__c` (Edit)
    5. `Chronic_Conditions__c` (Edit)
    6. `Last_Health_Checkup_Date__c` (Edit)
  - **Right Column Layout Items:**
    1. `Height_cm__c` (Edit)
    2. `Weight_kg__c` (Edit)
    3. `Primary_Physician__c` (Edit)
    4. `Current_Medications__c` (Edit)
    5. `Health_Insurance_Provider__c` (Edit)

---

## 3. Deployment, Testing & Verification Strategy
- **Target Org:** `learn_dc` (`sumit.gupta@datacloud.com`)
- **SFDX Project Path:** `C:\Users\Sumit Kr Gupta\OneDrive - Teqfocus Solutions Pvt. Ltd\Desktop\Learn DC`
- **Strict Guardrails:** Never touch, inspect, or reference `ServiceTitans`.

### Step 1: Layout Deployment / Dry Run (if required)
```bash
sf project deploy start --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc
```

### Step 2: Custom Field Verification (Tooling API)
```bash
sf data query -q "SELECT Id, DeveloperName, TableEnumOrId FROM CustomField WHERE TableEnumOrId = 'Contact' AND DeveloperName IN ('Last_Health_Checkup_Date', 'Health_Insurance_Provider')" -t -o learn_dc
```

### Step 3: Layout Metadata Verification Test (Addressing QA Feedback)
Execute Tooling API query to retrieve the active `Contact Layout` metadata and verify field placement in the `Medical Information` section:
```bash
sf data query -q "SELECT Metadata FROM Layout WHERE EntityDefinition.DeveloperName = 'Contact' AND Name = 'Contact Layout'" -t -o learn_dc --json | node -e "const fs = require('fs'); const input = JSON.parse(fs.readFileSync(0, 'utf-8')); const layout = input.result.records[0].Metadata; const sec = layout.layoutSections.find(s => s.label === 'Medical Information'); if (!sec) { console.error('FAIL: Medical Information section not found'); process.exit(1); } const leftFields = sec.layoutColumns[0].layoutItems.map(i => i.field); const rightFields = sec.layoutColumns[1].layoutItems.map(i => i.field); console.log('Medical Information Left Column:', leftFields); console.log('Medical Information Right Column:', rightFields); const hasCheckup = leftFields.includes('Last_Health_Checkup_Date__c'); const hasInsurance = rightFields.includes('Health_Insurance_Provider__c'); if (hasCheckup && hasInsurance) { console.log('SUCCESS: Last_Health_Checkup_Date__c and Health_Insurance_Provider__c verified in Medical Information section in learn_dc.'); } else { console.error('FAIL: Fields not properly located in Medical Information section.'); process.exit(1); }"
```

### Step 4: Documentation & Log Verification
Update `agent-context/tickets/SCRUM-12/log.md` with:
- Tooling API Layout query output.
- Explicit verification results demonstrating both fields are in the `Medical Information` section in org `learn_dc`.

---

## 4. Persistent Memory Updates
- **MEMORY.md Updates:**
  - Verify `Last_Health_Checkup_Date__c` and `Health_Insurance_Provider__c` under `## Contact Object`.
  - Confirm `## Portal UI Components` records layout deployment with both fields under `Medical Information`.
  - Confirm `SCRUM-12` is marked as completed in `## Pending / Backlog Roadmap`.
- **CHANGELOG.md Entry:**
  - Retain existing `SCRUM-12` entry recording creation of the fields and page layout update.
