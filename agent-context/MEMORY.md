# Living Project Memory

> [!NOTE]
> **Agent Reading Notice:** Agent 1 (Planner) MUST read this file FIRST before planning any new ticket.
> This document represents the distilled, living state of all Salesforce metadata, architecture decisions, and components created to date.
> Agent 2 (Builder) MUST update this file upon completing any ticket.

---

## Architecture & Framework
* **Target Org:** `learn_dc` (`sumit.gupta@datacloud.com`)
* **Core Application:** Experience Cloud Customer Portal
* **Memory Protocol:** Persistent Git-tracked documentation in `/agent-context/`

---

## Account Object
* **Standard Fields in Use:** `Name`, `Type`, `BillingAddress`, `Phone`, `Website`
* **Custom Fields:**
  - `Industry_Segment__c` (Picklist: A, B, C): Industry tiering for portal segmentation. Added in PORTAL-101.
  - `Renewal_Risk_Score__c` (Number 3, 0): Churn risk score (0-100) for renewal forecasting. Added in PORTAL-101.
  - `Last_Health_Check__c` (Date): Timestamp of the latest customer success health audit. Added in PORTAL-101.
  - `Primary_Competitor__c` (Text 80): Primary competitive threat for renewal defense. Added in PORTAL-101.
  - `Contract_Value__c` (Currency 18, 2): Contract value for revenue retention monitoring. Added in PORTAL-101.
  - `Auto_Renew__c` (Checkbox, default false): Indicates whether agreement auto-renews. Added in PORTAL-101.
  - `Customer_Support_Tier__c` (Picklist: Premium, Standard, Basic): Customer support tier classification for service entitlement. Added in PORTAL-103.
  - `Escalation_SLA_Hours__c` (Number 4, 0): Escalation turnaround time SLA in hours. Added in PORTAL-103.
* **Validation Rules:**
  - `VR_Primary_Competitor_Required`: Enforces Primary_Competitor__c is not blank when Renewal_Risk_Score__c > 80. Added in PORTAL-101.
  - `VR_Premium_SLA_Limit`: Enforces Escalation_SLA_Hours__c <= 24 when Customer_Support_Tier__c is Premium. Added in PORTAL-103.


---

## Contact Object
* **Standard Fields in Use:** `FirstName`, `LastName`, `Name`, `Email`, `Phone`, `Title`, `Department`, `Birthdate`
* **Custom Fields:**
  - `Blood_Group__c` (Picklist: A+, A-, B+, B-, AB+, AB-, O+, O-): Captures contact blood group. Added in SCRUM-6.
  - `Date_of_Birth__c` (Date): Contact date of birth. Added in SCRUM-6.
  - `Height_cm__c` (Number 5, 2): Contact height in centimeters. Added in SCRUM-6.
  - `Weight_kg__c` (Number 5, 2): Contact weight in kilograms. Added in SCRUM-6.
  - `Emergency_Contact_Phone__c` (Phone): Primary emergency contact phone number. Delivered in SCRUM-11.
  - `Allergies__c` (Long Text Area: 32768, 3 visible lines): Captures known allergies for the contact. Added in SCRUM-8.
  - `Primary_Physician__c` (Text 255): Name of the primary physician for the contact. Added in SCRUM-8.
  - `Chronic_Conditions__c` (Long Text Area: 32768, 3 visible lines): Captures known chronic conditions for the contact. Added in SCRUM-9.
  - `Current_Medications__c` (Long Text Area: 32768, 3 visible lines): Captures current medications taken by the contact. Added in SCRUM-9.
  - `Last_Health_Checkup_Date__c` (Date): Timestamp of the contact's most recent health checkup. Added in SCRUM-12.
  - `Health_Insurance_Provider__c` (Text 255): Name of the contact's health insurance provider. Added in SCRUM-12.

---

## Portal UI Components
* **Lightning Web Components:**
  * `contactHealthSummary`: Read-only 2-column health summary card component exposed for Contact Record Page (`lightning__RecordPage`). Surfaces 9 health fields (`Blood_Group__c`, `Date_of_Birth__c`, `Height_cm__c`, `Weight_kg__c`, `Allergies__c`, `Chronic_Conditions__c`, `Current_Medications__c`, `Last_Health_Checkup_Date__c`, `Health_Insurance_Provider__c`) using `lightning/uiRecordApi` LDS wire service with automatic `"Not Available"` fallback for blank values. Built in SCRUM-13.
* **FlexiPages / Record Pages:**
  * Standard Account Record Page layout (`Account-Account Layout`) updated to expose `Renewal_Risk_Score__c`, `Last_Health_Check__c`, and `Industry_Segment__c` under the `Renewal & Health Assessment` section. Added in PORTAL-102.
  * Standard Contact Record Page layout (`Contact-Contact Layout`) updated to expose `Blood_Group__c`, `Date_of_Birth__c`, `Height_cm__c`, `Weight_kg__c`, `Emergency_Contact_Phone__c`, `Allergies__c`, `Primary_Physician__c`, `Chronic_Conditions__c`, `Current_Medications__c`, `Last_Health_Checkup_Date__c`, and `Health_Insurance_Provider__c` under the `Medical Information` 2-column section. Added in SCRUM-7, updated in SCRUM-8, SCRUM-9, SCRUM-11, and SCRUM-12.

---

## Pending / Backlog Roadmap
* `PORTAL-101`: Account Health & Renewal Risk custom fields + validation rule. (Completed)
* `PORTAL-102`: Surface Account Renewal Risk Score & Health Check on Portal Account Record Layout. (Completed)
* `PORTAL-103`: Customer Support Tier and Escalation SLA fields on Account. (Completed)
* `SCRUM-6`: Create fields on Contact object. (Completed)
* `SCRUM-7`: Add 'Medical Information' section to Contact page layout. (Completed)
* `SCRUM-8`: Create fields in contact object (Allergies__c, Primary_Physician__c) and add to Medical Information section. (Completed)
* `SCRUM-9`: Create fields on Contact object (Chronic_Conditions__c, Current_Medications__c) and add to Medical Information section. (Completed)
* `SCRUM-11`: Create Emergency Contact Phone field on Contact object (Emergency_Contact_Phone__c) and add to Medical Information section. (Completed)
* `SCRUM-12`: Create 2 fields on Contact (Last_Health_Checkup_Date__c, Health_Insurance_Provider__c) and add to Medical Information section. (Completed)
* `SCRUM-13`: Create Contact Health Summary LWC (contactHealthSummary) on Contact Record Page. (Completed)
