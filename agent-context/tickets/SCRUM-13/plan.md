# Implementation Plan: SCRUM-13 - Contact Health Summary Component

## 1. Context & Dependencies
- **Existing Metadata Referenced from MEMORY.md:**
  - Standard `Contact` object (`force-app/main/default/objects/Contact`).
  - Baseline Contact health custom fields already present in schema and deployed to `learn_dc`:
    1. `Blood_Group__c` (Picklist: A+, A-, B+, B-, AB+, AB-, O+, O-) - added in SCRUM-6
    2. `Date_of_Birth__c` (Date) - added in SCRUM-6
    3. `Height_cm__c` (Number 5, 2) - added in SCRUM-6
    4. `Weight_kg__c` (Number 5, 2) - added in SCRUM-6
    5. `Allergies__c` (Long Text Area: 32768, 3 visible lines) - added in SCRUM-8
    6. `Chronic_Conditions__c` (Long Text Area: 32768, 3 visible lines) - added in SCRUM-9
    7. `Current_Medications__c` (Long Text Area: 32768, 3 visible lines) - added in SCRUM-9
    8. `Last_Health_Checkup_Date__c` (Date) - added in SCRUM-12
    9. `Health_Insurance_Provider__c` (Text 255) - added in SCRUM-12
- **New Capabilities Introduced:**
  - Create a new Lightning Web Component (LWC) named `contactHealthSummary` in `force-app/main/default/lwc/contactHealthSummary/`.
  - Expose the LWC for `lightning__RecordPage` on the `Contact` object.
  - Render a clean, responsive 2-column SLDS layout displaying all 9 required health fields.
  - Card Header: "Health Summary" with standard health icon (`standard:health_and_safety` or `standard:contact`).
  - Dynamic record context via `@api recordId` using Lightning Data Service (`lightning/uiRecordApi` with `getRecord`).
  - Read-only presentation (no input fields or edit actions).
  - Empty/blank field handling: displays `"Not Available"` if value is null, undefined, or empty string.
  - Responsive layout (single column on mobile, two columns on desktop/tablets).
  - Graceful loading (spinner) and error handling states.

---

## 2. Metadata Changes & Component Architecture

### Component Target Details
- **Component Directory:** `force-app/main/default/lwc/contactHealthSummary/`
- **Target Object:** `Contact`
- **Target Page Type:** `lightning__RecordPage`
- **Files to Create:**
  1. `contactHealthSummary.html`
  2. `contactHealthSummary.js`
  3. `contactHealthSummary.js-meta.xml`
  4. `contactHealthSummary.css` (optional/scoped styling for spacing and badge formatting)

### Technical Specifications by File

#### A. `contactHealthSummary.js-meta.xml`
- **API Version:** `61.0` (compatible with project sourceApiVersion)
- **isExposed:** `true`
- **masterLabel:** `Contact Health Summary`
- **description:** `Read-only 2-column health summary component for Contact record page.`
- **targets:**
  - `<target>lightning__RecordPage</target>`
- **targetConfigs:**
  - `<targetConfig targets="lightning__RecordPage">`
    - `<objects>`
      - `<object>Contact</object>`
    - `</objects>`
  - `</targetConfig>`

#### B. `contactHealthSummary.js`
- Imports:
  - `LightningElement, api, wire` from `'lwc'`
  - `getRecord, getFieldValue` from `'lightning/uiRecordApi'`
  - Schema tokens:
    - `BLOOD_GROUP_FIELD` from `'@salesforce/schema/Contact.Blood_Group__c'`
    - `DOB_FIELD` from `'@salesforce/schema/Contact.Date_of_Birth__c'`
    - `HEIGHT_FIELD` from `'@salesforce/schema/Contact.Height_cm__c'`
    - `WEIGHT_FIELD` from `'@salesforce/schema/Contact.Weight_kg__c'`
    - `ALLERGIES_FIELD` from `'@salesforce/schema/Contact.Allergies__c'`
    - `CHRONIC_CONDITIONS_FIELD` from `'@salesforce/schema/Contact.Chronic_Conditions__c'`
    - `CURRENT_MEDICATIONS_FIELD` from `'@salesforce/schema/Contact.Current_Medications__c'`
    - `LAST_CHECKUP_DATE_FIELD` from `'@salesforce/schema/Contact.Last_Health_Checkup_Date__c'`
    - `HEALTH_INSURANCE_FIELD` from `'@salesforce/schema/Contact.Health_Insurance_Provider__c'`
- Properties:
  - `@api recordId`: Contact record ID passed from the Lightning record page.
  - Wire service:
    ```javascript
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    contactRecord({ error, data }) { ... }
    ```
- Value transformation & Fallback logic:
  - Helper method `formatValue(val)`: returns `val` if present and non-empty (trimmed string check); otherwise returns `"Not Available"`.
  - Getter returning structured list or object containing the 9 fields with label, formatted value, and empty fallback status.
  - Error and loading state properties: `isLoading` and `errorMessage`.

#### C. `contactHealthSummary.html`
- Header: `<lightning-card title="Health Summary" icon-name="standard:health_and_safety">`
- Loading State:
  - `<template lwc:if={isLoading}>` with `<lightning-spinner alternative-text="Loading Health Summary" size="medium"></lightning-spinner>`
- Error State:
  - `<template lwc:elseif={errorMessage}>` with SLDS scoped notification or error banner displaying error details cleanly without breaking the page.
- Content State:
  - `<template lwc:else>`
  - Container with `slds-p-around_medium`
  - 2-Column Responsive Grid (`slds-grid slds-wrap slds-gutters`):
    - Each field rendered as:
      `<div class="slds-col slds-size_1-of-1 slds-medium-size_6-of-12 slds-p-bottom_small">`
      - Label: `<div class="slds-text-title slds-text-color_weak slds-m-bottom_xx-small">{item.label}</div>`
      - Value: `<div class="slds-text-body_regular slds-truncate">{item.value}</div>`
    - Ordered logically across the two columns:
      - Column 1: Blood Group, Date of Birth, Height (cm), Allergies, Chronic Conditions
      - Column 2: Weight (kg), Last Health Checkup Date, Health Insurance Provider, Current Medications
  - Strict read-only presentation (no inputs or edit icons).

#### D. `contactHealthSummary.css`
- Subtle styling enhancements using SLDS tokens, e.g. empty-state italicized styling for "Not Available" (`slds-text-color_weak`) if desired, ensuring full compliance with SLDS design tokens.

---

## 3. Deployment & Validation Strategy
- **Target Org:** `learn_dc` (`sumit.gupta@datacloud.com`)
- **SFDX Project Path:** `C:\Users\Sumit Kr Gupta\OneDrive - Teqfocus Solutions Pvt. Ltd\Desktop\Learn DC`
- **Strict Guardrail Reminder:** NEVER touch, scan, or deploy from `C:\Users\Sumit Kr Gupta\OneDrive - Teqfocus Solutions Pvt. Ltd\Desktop\Learn DC\ServiceTitans`.

### Step 1: Deploy Component Bundle to `learn_dc`
```bash
sf project deploy start --source-dir "force-app/main/default/lwc/contactHealthSummary" -o learn_dc
```

### Step 2: Tooling API Verification
Verify that the `contactHealthSummary` Lightning Component Bundle exists and is deployed to `learn_dc`:
```bash
sf data query -q "SELECT Id, DeveloperName, ApiVersion, MasterLabel FROM LightningComponentBundle WHERE DeveloperName = 'contactHealthSummary'" -t -o learn_dc
```

### Step 3: Verify Bundle Resources
Verify that HTML, JS, and JS-META resources are compiled and present in the deployed bundle:
```bash
sf data query -q "SELECT Id, FilePath, Format FROM LightningComponentResource WHERE LightningComponentBundle.DeveloperName = 'contactHealthSummary'" -t -o learn_dc
```

### Step 4: ESLint / Code Verification
Run local lint checks to ensure code quality and prevent runtime wire or template syntax errors:
```bash
npx eslint force-app/main/default/lwc/contactHealthSummary
```

---

## 4. Persistent Memory Updates

### `agent-context/MEMORY.md` Updates:
- Under `## Portal UI Components` -> `* **Lightning Web Components:**`:
  - Add:
    ```markdown
    * `contactHealthSummary`: Read-only 2-column health summary card component exposed for Contact Record Page (`lightning__RecordPage`). Surfaces 9 health fields (`Blood_Group__c`, `Date_of_Birth__c`, `Height_cm__c`, `Weight_kg__c`, `Allergies__c`, `Chronic_Conditions__c`, `Current_Medications__c`, `Last_Health_Checkup_Date__c`, `Health_Insurance_Provider__c`) using `lightning/uiRecordApi` LDS wire service with automatic `"Not Available"` fallback for blank values. Built in SCRUM-13.
    ```
- Under `## Pending / Backlog Roadmap`:
  - Add:
    ```markdown
    * `SCRUM-13`: Create Contact Health Summary LWC (contactHealthSummary) on Contact Record Page. (Completed)
    ```

### `agent-context/CHANGELOG.md` Entry:
Append the following ledger line to the table:
```markdown
| 2026-09-17 | SCRUM-13 | Feature | Create Contact Health Summary LWC (contactHealthSummary) with 2-column layout and blank value fallbacks | `force-app/main/default/lwc/contactHealthSummary/*`, `/agent-context/*` | Pending PR |
```
