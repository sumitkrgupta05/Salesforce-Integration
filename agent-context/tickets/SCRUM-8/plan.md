# Implementation Plan: SCRUM-8 - Create fields in contact object

## 1. Context & Dependencies
- **Existing Metadata Referenced from MEMORY.md:**
  - Standard `Contact` object (`force-app/main/default/objects/Contact`).
  - Baseline state confirms standard Contact fields (`FirstName`, `LastName`, `Email`, `Phone`, `Birthdate`, `Title`, `Department`) and custom fields created in SCRUM-6:
    - `Blood_Group__c` (Picklist: A+, A-, B+, B-, AB+, AB-, O+, O-)
    - `Date_of_Birth__c` (Date)
    - `Height_cm__c` (Number 5, 2)
    - `Weight_kg__c` (Number 5, 2)
    - `Emergency_Contact_Phone__c` (Phone)
  - Target Page Layout: `Contact-Contact Layout.layout-meta.xml` located at `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`.
  - Existing `Medical Information` 2-column layout section provisioned in SCRUM-7 under `Contact-Contact Layout`.
- **New Capabilities Introduced:**
  - Provision 2 new custom fields on the `Contact` object to record contact medical background and primary healthcare provider details:
    - `Allergies__c` (Long Text Area)
    - `Primary_Physician__c` (Text 255)
  - Expose both new fields within the existing `Medical Information` section on the primary `Contact-Contact Layout` page layout (addressing the minor typo 'Medical Infromation' in the ticket description to match the existing section).

## 2. Metadata Changes
- **Target Object:** `Contact` (`force-app/main/default/objects/Contact`)
- **Fields to Create/Modify:**
  - **Field 1:** `Allergies__c`
    - **Type:** `LongTextArea`
    - **Label:** `Allergies`
    - **Length:** `32768`
    - **Visible Lines:** `3`
    - **Description:** `Captures known allergies for the contact (e.g., penicillin, peanuts).`
    - **Inline Help Text:** `Enter any known allergies for this contact.`
    - **Required:** `false`
  - **Field 2:** `Primary_Physician__c`
    - **Type:** `Text`
    - **Label:** `Primary Physician`
    - **Length:** `255`
    - **Description:** `Name and title of the contact's primary physician.`
    - **Inline Help Text:** `Enter the name of the primary physician (e.g., Dr. Rajesh Sharma).`
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
    - **Right Column Layout Items:**
      - Item 1: `Height_cm__c` (Behavior: `Edit`)
      - Item 2: `Weight_kg__c` (Behavior: `Edit`)
      - Item 3: `Primary_Physician__c` (Behavior: `Edit`)
- **Validation Rules:**
  - *(None requested for this ticket)*

## 3. Deployment & Validation Strategy
- **Target Org:** `learn_dc` (`sumit.gupta@datacloud.com`)
- **SFDX Project Path:** `C:\Users\Sumit Kr Gupta\OneDrive - Teqfocus Solutions Pvt. Ltd\Desktop\Learn DC`
- **Strict Guardrails:** Strictly avoid inspecting, accessing, modifying, or deploying from `ServiceTitans`.
- **Dry Run / Verification Command:**
  ```bash
  sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Allergies__c.field-meta.xml --source-dir force-app/main/default/objects/Contact/fields/Primary_Physician__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc --dry-run
  ```
- **Deployment Command:**
  ```bash
  sf project deploy start --source-dir force-app/main/default/objects/Contact/fields/Allergies__c.field-meta.xml --source-dir force-app/main/default/objects/Contact/fields/Primary_Physician__c.field-meta.xml --source-dir "force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml" -o learn_dc
  ```

## 4. Persistent Memory Updates
- **MEMORY.md Updates:**
  - Update `## Contact Object` under `* **Custom Fields:**` by appending:
    ```markdown
      - `Allergies__c` (Long Text Area: 32768, 3 visible lines): Captures known allergies for the contact. Added in SCRUM-8.
      - `Primary_Physician__c` (Text 255): Name of the primary physician for the contact. Added in SCRUM-8.
    ```
  - Update `## Portal UI Components` under `* **FlexiPages / Record Pages:**`:
    ```markdown
      * Standard Contact Record Page layout (`Contact-Contact Layout`) updated to expose `Blood_Group__c`, `Date_of_Birth__c`, `Height_cm__c`, `Weight_kg__c`, `Emergency_Contact_Phone__c`, `Allergies__c`, and `Primary_Physician__c` under the `Medical Information` 2-column section. Added in SCRUM-7, updated in SCRUM-8.
    ```
  - Update `## Pending / Backlog Roadmap`:
    ```markdown
    * `SCRUM-8`: Create fields in contact object (Allergies__c, Primary_Physician__c) and add to Medical Information section. (Completed)
    ```
- **CHANGELOG.md Entry:**
  ```markdown
  | 2026-09-12 | SCRUM-8 | Feature | Create Allergies and Primary Physician fields on Contact and add to Medical Information section | `force-app/main/default/objects/Contact/fields/*`, `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
  ```
