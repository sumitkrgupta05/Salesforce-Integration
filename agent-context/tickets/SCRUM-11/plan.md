# Implementation Plan: SCRUM-11 - Create Alternate Emergency Phone field on Contact object

## 1. Context & Dependencies
- **Existing Metadata Referenced from MEMORY.md:**
  - Standard `Contact` object (`force-app/main/default/objects/Contact`).
  - Baseline state confirms standard Contact fields (`FirstName`, `LastName`, `Email`, `Phone`, `Birthdate`, `Title`, `Department`) and custom fields created in SCRUM-6, SCRUM-8, and SCRUM-9:
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
  - Existing `Medical Information` 2-column layout section provisioned in SCRUM-7 and updated in SCRUM-8 and SCRUM-9 under `Contact-Contact Layout`.
- **Clarification Incorporated:**
  - `Emergency_Contact_Phone__c` already exists and is placed in `Medical Information`. Developer clarified to create an alternate emergency phone field named `Alternate_Emergency_Phone__c` instead and add it into the `Medical Information` section.
- **New Capabilities Introduced:**
  - Provision new custom field `Alternate_Emergency_Phone__c` (Phone) on the `Contact` object to capture secondary/alternate emergency contact telephone details.
  - Expose `Alternate_Emergency_Phone__c` within the existing `Medical Information` section on the primary `Contact-Contact Layout` page layout.

## 2. Metadata Changes
- **Target Object:** `Contact` (`force-app/main/default/objects/Contact`)
- **Fields to Create/Modify:**
  - **Field 1:** `Alternate_Emergency_Phone__c`
    - **Type:** `Phone`
    - **Label:** `Alternate Emergency Phone`
    - **Description:** `Secondary or alternate emergency contact phone number for the contact.`
    - **Inline Help Text:** `Enter alternate emergency contact phone number including country/area code.`
    - **Required:** `false`
    - **TrackFeedHistory:** `false`
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
      - Item 3: `Alternate_Emergency_Phone__c` (Behavior: `Edit`)
      - Item 4: `Primary_Physician__c` (Behavior: `Edit`)
      - Item 5: `Current_Medications__c` (Behavior: `Edit`)
- **Validation Rules:**
  - *(None requested for this ticket)*

## 3. Deployment & Validation Strategy
- **Target Org:** `learn_dc` (`sumit.gupta@datacloud.com`)
- **SFDX Project Path:** `C:\Users\Sumit Kr Gupta\OneDrive - Teqfocus Solutions Pvt. Ltd\Desktop\Learn DC`
- **Strict Guardrails:** Strictly avoid inspecting, accessing, modifying, or deploying from `ServiceTitans`.
- **Dry Run / Verification Command:**
  ```bash
  sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Alternate_Emergency_Phone__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc --dry-run
  ```
- **Deployment Command:**
  ```bash
  sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Alternate_Emergency_Phone__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc
  ```

## 4. Persistent Memory Updates
- **MEMORY.md Updates:**
  - Update `## Contact Object` under `* **Custom Fields:**` by appending:
    ```markdown
      - `Alternate_Emergency_Phone__c` (Phone): Secondary or alternate emergency contact phone number. Added in SCRUM-11.
    ```
  - Update `## Portal UI Components` under `* **FlexiPages / Record Pages:**`:
    ```markdown
      * Standard Contact Record Page layout (`Contact-Contact Layout`) updated to expose `Blood_Group__c`, `Date_of_Birth__c`, `Height_cm__c`, `Weight_kg__c`, `Emergency_Contact_Phone__c`, `Alternate_Emergency_Phone__c`, `Allergies__c`, `Primary_Physician__c`, `Chronic_Conditions__c`, and `Current_Medications__c` under the `Medical Information` 2-column section. Added in SCRUM-7, updated in SCRUM-8, SCRUM-9, and SCRUM-11.
    ```
  - Update `## Pending / Backlog Roadmap`:
    ```markdown
    * `SCRUM-11`: Create Alternate Emergency Phone field on Contact object (Alternate_Emergency_Phone__c) and add to Medical Information section. (Completed)
    ```
- **CHANGELOG.md Entry:**
  ```markdown
  | 2026-09-14 | SCRUM-11 | Feature | Create Alternate Emergency Phone field on Contact and add to Medical Information section | `force-app/main/default/objects/Contact/fields/Alternate_Emergency_Phone__c.field-meta.xml`, `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
  ```
