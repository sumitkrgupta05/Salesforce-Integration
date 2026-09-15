# Implementation Plan: SCRUM-12 - Create 2 fields on Contact

## 1. Context & Dependencies
- **Existing Metadata Referenced from MEMORY.md:**
  - Standard `Contact` object (`force-app/main/default/objects/Contact`).
  - Baseline state confirms standard Contact fields (`FirstName`, `LastName`, `Email`, `Phone`, `Birthdate`, `Title`, `Department`) and custom fields created in previous tickets (SCRUM-6, SCRUM-8, SCRUM-9, SCRUM-11):
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
  - Existing `Medical Information` 2-column layout section provisioned in SCRUM-7 and updated in SCRUM-8, SCRUM-9, and SCRUM-11 under `Contact-Contact Layout`.
- **New Capabilities Introduced:**
  - Provision 2 new custom fields on the `Contact` object to capture health checkup recency and insurance provider details:
    - `Last_Health_Checkup_Date__c` (Date)
    - `Health_Insurance_Provider__c` (Text 255)
  - Expose both new fields within the existing `Medical Information` section on the primary `Contact-Contact Layout` page layout (addressing the minor typo 'Medical Informtion' in the ticket description to match the existing section).

## 2. Metadata Changes
- **Target Object:** `Contact` (`force-app/main/default/objects/Contact`)
- **Fields to Create/Modify:**
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
    - **Unique:** `false`
    - **External ID:** `false`
- **Page Layout Modifications:**
  - **Target Layout File:** `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`
  - **Target Section:** `Medical Information` (Style: `TwoColumnsLeftToRight`)
  - **Updated Column Configuration:**
    - **Left Column Layout Items:**
      - Item 1: `Blood_Group__c` (Behavior: `Edit`)
      - Item 2: `Date_of_Birth__c` (Behavior: `Edit`)
      - Item 3: `Emergency_Contact_Phone__c` (Behavior: `Edit`)
      - Item 4: `Allergies__c` (Behavior: `Edit`)
      - Item 5: `Chronic_Conditions__c` (Behavior: `Edit`)
      - Item 6: `Last_Health_Checkup_Date__c` (Behavior: `Edit`)
    - **Right Column Layout Items:**
      - Item 1: `Height_cm__c` (Behavior: `Edit`)
      - Item 2: `Weight_kg__c` (Behavior: `Edit`)
      - Item 3: `Primary_Physician__c` (Behavior: `Edit`)
      - Item 4: `Current_Medications__c` (Behavior: `Edit`)
      - Item 5: `Health_Insurance_Provider__c` (Behavior: `Edit`)
- **Validation Rules:**
  - *(None requested for this ticket)*

## 3. Deployment & Validation Strategy
- **Target Org:** `learn_dc` (`sumit.gupta@datacloud.com`)
- **SFDX Project Path:** `C:\Users\Sumit Kr Gupta\OneDrive - Teqfocus Solutions Pvt. Ltd\Desktop\Learn DC`
- **Strict Guardrails:** Strictly avoid inspecting, accessing, modifying, or deploying from `ServiceTitans`.
- **Dry Run / Verification Command:**
  ```bash
  sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Last_Health_Checkup_Date__c.field-meta.xml --source-dir force-app/main/default/objects/Contact/fields/Health_Insurance_Provider__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc --dry-run
  ```
- **Deployment Command:**
  ```bash
  sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Last_Health_Checkup_Date__c.field-meta.xml --source-dir force-app/main/default/objects/Contact/fields/Health_Insurance_Provider__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc
  ```
- **Post-Deployment Verification Command (Tooling API):**
  ```bash
  sf data query -q "SELECT Id, DeveloperName, TableEnumOrId FROM CustomField WHERE TableEnumOrId = 'Contact' AND DeveloperName IN ('Last_Health_Checkup_Date', 'Health_Insurance_Provider')" -t -o learn_dc
  ```

## 4. Persistent Memory Updates
- **MEMORY.md Updates:**
  - Update `## Contact Object` under `* **Custom Fields:**` by appending:
    ```markdown
      - `Last_Health_Checkup_Date__c` (Date): Timestamp of the contact's most recent health checkup. Added in SCRUM-12.
      - `Health_Insurance_Provider__c` (Text 255): Name of the contact's health insurance provider. Added in SCRUM-12.
    ```
  - Update `## Portal UI Components` under `* **FlexiPages / Record Pages:**`:
    ```markdown
      * Standard Contact Record Page layout (`Contact-Contact Layout`) updated to expose `Blood_Group__c`, `Date_of_Birth__c`, `Height_cm__c`, `Weight_kg__c`, `Emergency_Contact_Phone__c`, `Allergies__c`, `Primary_Physician__c`, `Chronic_Conditions__c`, `Current_Medications__c`, `Last_Health_Checkup_Date__c`, and `Health_Insurance_Provider__c` under the `Medical Information` 2-column section. Added in SCRUM-7, updated in SCRUM-8, SCRUM-9, SCRUM-11, and SCRUM-12.
    ```
  - Update `## Pending / Backlog Roadmap`:
    ```markdown
    * `SCRUM-12`: Create 2 fields on Contact (Last_Health_Checkup_Date__c, Health_Insurance_Provider__c) and add to Medical Information section. (Completed)
    ```
- **CHANGELOG.md Entry:**
  ```markdown
  | 2026-09-15 | SCRUM-12 | Feature | Create Last Health Checkup Date and Health Insurance Provider fields on Contact and add to Medical Information section | `force-app/main/default/objects/Contact/fields/*`, `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
  ```
