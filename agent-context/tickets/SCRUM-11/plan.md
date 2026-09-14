# Implementation Plan: SCRUM-11 - Create Emergency Contact Phone field on Contact object (Remediation Cycle 2)

## 1. Context & Dependencies
- **Ticket Summary & Specification (JIRA SCRUM-11):**
  - **Summary:** Create Emergency Contact Phone field on Contact object
  - **Deliverable:** Custom Phone field `Emergency_Contact_Phone__c` on `Contact` object and expose it within the `Medical Information` section on `Contact-Contact Layout`.
  - **Target Org:** `learn_dc` (`sumit.gupta@datacloud.com`).
- **PR Reviewer Findings & Root Cause Analysis (Cycle 1):**
  - PR Reviewer (Agent 3) requested changes on PR #5:
    - The initial PR introduced an unauthorized phantom custom field `Alternate_Emergency_Phone__c` instead of delivering the requested `Emergency_Contact_Phone__c`.
    - It modified `Contact-Contact Layout.layout-meta.xml` to place `Alternate_Emergency_Phone__c` into the `Medical Information` section, deviating from ticket specifications.
- **Remediation Directives for Agent 2 (Builder):**
  1. Remove `Alternate_Emergency_Phone__c` from `Medical Information` in `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`.
  2. Deploy layout to org `learn_dc` to unlink `Alternate_Emergency_Phone__c`.
  3. Delete the unauthorized custom field `Alternate_Emergency_Phone__c` from target org `learn_dc`.
  4. Delete the local metadata file `force-app/main/default/objects/Contact/fields/Alternate_Emergency_Phone__c.field-meta.xml`.
  5. Delete `Alternate_Emergency_Phone__c.field-meta.xml` from the remote GitHub branch `jira-agy-integration`.
  6. Verify and validate `force-app/main/default/objects/Contact/fields/Emergency_Contact_Phone__c.field-meta.xml` as the official deliverable for SCRUM-11.
  7. Confirm `Emergency_Contact_Phone__c` is properly placed in the `Medical Information` section of `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`.
  8. Deploy `Emergency_Contact_Phone__c` and `Contact-Contact Layout` to `learn_dc` and verify via Tooling API query.
  9. Update `agent-context/MEMORY.md`, `agent-context/CHANGELOG.md`, and `agent-context/tickets/SCRUM-11/log.md` to remove all references to `Alternate_Emergency_Phone__c`.

---

## 2. Metadata Changes

### A. Cleanup & Deletion of Unauthorized Metadata
1. **Remove Layout Reference (`force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`):**
   - Remove `<layoutItems><behavior>Edit</behavior><field>Alternate_Emergency_Phone__c</field></layoutItems>` from the right column of `Medical Information`.
2. **Delete Custom Field from Org `learn_dc`:**
   - Execute deletion via Tooling API or Salesforce CLI:
     ```bash
     sf data query -q "SELECT Id, DeveloperName FROM CustomField WHERE TableEnumOrId = 'Contact' AND DeveloperName = 'Alternate_Emergency_Phone'" -t -o learn_dc
     sf data delete record -s CustomField -i <CUSTOM_FIELD_ID> -t -o learn_dc
     ```
3. **Delete Local File:**
   - Delete `force-app/main/default/objects/Contact/fields/Alternate_Emergency_Phone__c.field-meta.xml`.

### B. Approved Deliverables for SCRUM-11
1. **Custom Field Specification:**
   - **Target Object:** `Contact` (`force-app/main/default/objects/Contact`)
   - **Target File:** `force-app/main/default/objects/Contact/fields/Emergency_Contact_Phone__c.field-meta.xml`
   - **Type:** `Phone`
   - **API Name:** `Emergency_Contact_Phone__c`
   - **Label:** `Emergency Contact Phone`
   - **Description:** `Primary emergency contact phone number for the contact.`
   - **Inline Help Text:** `Enter emergency contact phone number including country/area code.`
   - **Required:** `false`
   - **TrackFeedHistory:** `false`

2. **Page Layout Specification:**
   - **Target Layout File:** `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`
   - **Target Section:** `Medical Information` (Style: `TwoColumnsLeftToRight`)
   - **Column Configuration:**
     - **Left Column Layout Items:**
       - Item 1: `Blood_Group__c` (Behavior: `Edit`)
       - Item 2: `Date_of_Birth__c` (Behavior: `Edit`)
       - Item 3: `Emergency_Contact_Phone__c` (Behavior: `Edit`)  <-- Verified SCRUM-11 deliverable
       - Item 4: `Allergies__c` (Behavior: `Edit`)
       - Item 5: `Chronic_Conditions__c` (Behavior: `Edit`)
     - **Right Column Layout Items:**
       - Item 1: `Height_cm__c` (Behavior: `Edit`)
       - Item 2: `Weight_kg__c` (Behavior: `Edit`)
       - Item 3: `Primary_Physician__c` (Behavior: `Edit`)
       - Item 4: `Current_Medications__c` (Behavior: `Edit`)

---

## 3. Deployment & Validation Strategy
- **Target Org:** `learn_dc` (`sumit.gupta@datacloud.com`)
- **SFDX Project Path:** `C:\Users\Sumit Kr Gupta\OneDrive - Teqfocus Solutions Pvt. Ltd\Desktop\Learn DC`
- **Strict Guardrail:** Strictly avoid inspecting, accessing, modifying, or deploying from `ServiceTitans`.

### Step-by-Step Execution Sequence:
1. **Deploy Layout First (Unlink Field in Org):**
   ```bash
   sf project deploy start --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc
   ```
2. **Delete `Alternate_Emergency_Phone__c` from `learn_dc`:**
   ```bash
   sf data query -q "SELECT Id, DeveloperName FROM CustomField WHERE TableEnumOrId = 'Contact' AND DeveloperName = 'Alternate_Emergency_Phone'" -t -o learn_dc
   sf data delete record -s CustomField -i <ID> -t -o learn_dc
   ```
3. **Delete Local File:**
   Remove `force-app/main/default/objects/Contact/fields/Alternate_Emergency_Phone__c.field-meta.xml`.
4. **Dry Run Validation for SCRUM-11 Deliverable:**
   ```bash
   sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Emergency_Contact_Phone__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc --dry-run
   ```
5. **Deploy SCRUM-11 Deliverables:**
   ```bash
   sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Emergency_Contact_Phone__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc
   ```
6. **Tooling API Verification:**
   - Verify `Alternate_Emergency_Phone` is completely deleted:
     ```bash
     sf data query -q "SELECT Id, DeveloperName FROM CustomField WHERE TableEnumOrId = 'Contact' AND DeveloperName = 'Alternate_Emergency_Phone'" -t -o learn_dc
     ```
     *Expected Output:* 0 records retrieved.
   - Verify `Emergency_Contact_Phone` is active in `learn_dc`:
     ```bash
     sf data query -q "SELECT Id, DeveloperName, TableEnumOrId FROM CustomField WHERE TableEnumOrId = 'Contact' AND DeveloperName = 'Emergency_Contact_Phone'" -t -o learn_dc
     ```
     *Expected Output:* 1 record retrieved.

---

## 4. Persistent Memory Updates
- **MEMORY.md Updates:**
  - `## Contact Object` under `* **Custom Fields:**`:
    ```markdown
      - `Emergency_Contact_Phone__c` (Phone): Primary emergency contact phone number. Delivered in SCRUM-11.
    ```
    (Ensure no entry exists for `Alternate_Emergency_Phone__c`).
  - `## Portal UI Components` under `* **FlexiPages / Record Pages:**`:
    ```markdown
      * Standard Contact Record Page layout (`Contact-Contact Layout`) updated to expose `Blood_Group__c`, `Date_of_Birth__c`, `Height_cm__c`, `Weight_kg__c`, `Emergency_Contact_Phone__c`, `Allergies__c`, `Primary_Physician__c`, `Chronic_Conditions__c`, and `Current_Medications__c` under the `Medical Information` 2-column section. Added in SCRUM-7, updated in SCRUM-8, SCRUM-9, and SCRUM-11.
    ```
  - `## Pending / Backlog Roadmap`:
    ```markdown
    * `SCRUM-11`: Create Emergency Contact Phone field on Contact object (Emergency_Contact_Phone__c) and add to Medical Information section. (Completed)
    ```
- **CHANGELOG.md Entry:**
  ```markdown
  | 2026-09-14 | SCRUM-11 | Feature | Create Emergency Contact Phone field on Contact and add to Medical Information section | `force-app/main/default/objects/Contact/fields/Emergency_Contact_Phone__c.field-meta.xml`, `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
  ```
- **`log.md` Remediation Section:**
  Document the remediation actions taken in Cycle 2, including deletion of `Alternate_Emergency_Phone__c` from org `learn_dc` and disk, layout update, deployment of `Emergency_Contact_Phone__c`, and Tooling API verification outputs.
