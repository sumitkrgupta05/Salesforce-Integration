# Implementation Plan: SCRUM-9 - Create fields on Contact object

## 1. Context & Dependencies
- **Existing Metadata Referenced from MEMORY.md:**
  - Standard `Contact` object (`force-app/main/default/objects/Contact`).
  - Baseline state confirms standard Contact fields (`FirstName`, `LastName`, `Email`, `Phone`, `Birthdate`, `Title`, `Department`) and custom fields created in SCRUM-6 and SCRUM-8:
    - `Blood_Group__c` (Picklist: A+, A-, B+, B-, AB+, AB-, O+, O-)
    - `Date_of_Birth__c` (Date)
    - `Height_cm__c` (Number 5, 2)
    - `Weight_kg__c` (Number 5, 2)
    - `Emergency_Contact_Phone__c` (Phone)
    - `Allergies__c` (Long Text Area: 32768, 3 visible lines)
    - `Primary_Physician__c` (Text 255)
  - Target Page Layout: `Contact-Contact Layout.layout-meta.xml` located at `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`.
  - Existing `Medical Information` 2-column layout section provisioned in SCRUM-7 and updated in SCRUM-8 under `Contact-Contact Layout`.
- **New Capabilities Introduced:**
  - Provision 2 new custom fields on the `Contact` object to capture health background and current medication details:
    - `Chronic_Conditions__c` (Long Text Area)
    - `Current_Medications__c` (Long Text Area)
  - Expose both new fields within the existing `Medical Information` section on the primary `Contact-Contact Layout` page layout.

## 2. Metadata Changes
- **Target Object:** `Contact` (`force-app/main/default/objects/Contact`)
- **Fields to Create/Modify:**
  - **Field 1:** `Chronic_Conditions__c`
    - **Type:** `LongTextArea`
    - **Label:** `Chronic Conditions`
    - **Length:** `32768`
    - **Visible Lines:** `3`
    - **Description:** `Captures known chronic conditions for the contact (e.g., Diabetes, Asthma).`
    - **Inline Help Text:** `Enter any chronic conditions for this contact.`
    - **Required:** `false`
  - **Field 2:** `Current_Medications__c`
    - **Type:** `LongTextArea`
    - **Label:** `Current Medications`
    - **Length:** `32768`
    - **Visible Lines:** `3`
    - **Description:** `Captures current medications taken by the contact (e.g., Metformin 500mg, Albuterol).`
    - **Inline Help Text:** `Enter current medications for this contact.`
    - **Required:** `false`
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
    - **Right Column Layout Items:**
      - Item 1: `Height_cm__c` (Behavior: `Edit`)
      - Item 2: `Weight_kg__c` (Behavior: `Edit`)
      - Item 3: `Primary_Physician__c` (Behavior: `Edit`)
      - Item 4: `Current_Medications__c` (Behavior: `Edit`)
- **Validation Rules:**
  - *(None requested for this ticket)*

## 3. Deployment & Validation Strategy
- **Target Org:** `learn_dc` (`sumit.gupta@datacloud.com`)
- **SFDX Project Path:** `C:\Users\Sumit Kr Gupta\OneDrive - Teqfocus Solutions Pvt. Ltd\Desktop\Learn DC`
- **Strict Guardrails:** Strictly avoid inspecting, accessing, modifying, or deploying from `ServiceTitans`.
- **Dry Run / Verification Command:**
  ```bash
  sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Chronic_Conditions__c.field-meta.xml --source-dir force-app/main/default/objects/Contact/fields/Current_Medications__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc --dry-run
  ```
- **Deployment Command:**
  ```bash
  sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Chronic_Conditions__c.field-meta.xml --source-dir force-app/main/default/objects/Contact/fields/Current_Medications__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc
  ```

## 4. Persistent Memory Updates
- **MEMORY.md Updates:**
  - Update `## Contact Object` under `* **Custom Fields:**` by appending:
    ```markdown
      - `Chronic_Conditions__c` (Long Text Area: 32768, 3 visible lines): Captures known chronic conditions for the contact. Added in SCRUM-9.
      - `Current_Medications__c` (Long Text Area: 32768, 3 visible lines): Captures current medications taken by the contact. Added in SCRUM-9.
    ```
  - Update `## Portal UI Components` under `* **FlexiPages / Record Pages:**`:
    ```markdown
      * Standard Contact Record Page layout (`Contact-Contact Layout`) updated to expose `Blood_Group__c`, `Date_of_Birth__c`, `Height_cm__c`, `Weight_kg__c`, `Emergency_Contact_Phone__c`, `Allergies__c`, `Primary_Physician__c`, `Chronic_Conditions__c`, and `Current_Medications__c` under the `Medical Information` 2-column section. Added in SCRUM-7, updated in SCRUM-8 and SCRUM-9.
    ```
  - Update `## Pending / Backlog Roadmap`:
    ```markdown
    * `SCRUM-9`: Create fields on Contact object (Chronic_Conditions__c, Current_Medications__c) and add to Medical Information section. (Completed)
    ```
- **CHANGELOG.md Entry:**
  ```markdown
  | 2026-09-14 | SCRUM-9 | Feature | Create Chronic Conditions and Current Medications fields on Contact and add to Medical Information section | `force-app/main/default/objects/Contact/fields/*`, `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
  ```
