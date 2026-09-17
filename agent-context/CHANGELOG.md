# Project Memory Changelog

> [!NOTE]
> **Append-Only Ledger:** This file records the chronological history of completed tickets.
> Historical entries must NEVER be modified. Each completed ticket appends a single new entry below.

| Date | Ticket Key | Type | Summary | Artifacts Touched | PR Link |
|---|---|---|---|---|---|
| 2026-09-11 | INIT-000 | Config | Initialized project memory scaffold and agent instructions | `/agent-context/*` | N/A |
| 2026-09-11 | PORTAL-101 | Feature | Account Health & Renewal Risk Custom Fields and Validation Rule | `force-app/main/default/objects/Account/*`, `/agent-context/*` | Pending PR |
| 2026-09-11 | PORTAL-102 | Feature | Expose Renewal Risk, Health Check, and Industry Segment on Account Layout | `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
| 2026-09-12 | PORTAL-103 | Feature | Customer Support Tier and Escalation SLA fields on Account | `force-app/main/default/objects/Account/*`, `/agent-context/*` | [PR #1](https://github.com/sumitkrgupta05/Salesforce-Integration/pull/1) |
| 2026-09-12 | SCRUM-6 | Feature | Create fields on Contact object | `force-app/main/default/objects/Contact/*`, `/agent-context/*` | Pending PR |
| 2026-09-12 | SCRUM-7 | Feature | Add Medical Information 2-column section to Contact Layout | `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
| 2026-09-12 | SCRUM-8 | Feature | Create Allergies and Primary Physician fields on Contact and add to Medical Information section | `force-app/main/default/objects/Contact/fields/*`, `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
| 2026-09-14 | SCRUM-9 | Feature | Create Chronic Conditions and Current Medications fields on Contact and add to Medical Information section | `force-app/main/default/objects/Contact/fields/*`, `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
| 2026-09-14 | SCRUM-11 | Feature | Create Emergency Contact Phone field on Contact and add to Medical Information section | `force-app/main/default/objects/Contact/fields/Emergency_Contact_Phone__c.field-meta.xml`, `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | [PR #5](https://github.com/sumitkrgupta05/Salesforce-Integration/pull/5) |
| 2026-09-15 | SCRUM-12 | Feature | Create Last Health Checkup Date and Health Insurance Provider fields on Contact and add to Medical Information section | `force-app/main/default/objects/Contact/fields/*`, `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`, `/agent-context/*` | Pending PR |
| 2026-09-17 | SCRUM-13 | Feature | Create Contact Health Summary LWC (contactHealthSummary) with 2-column layout and blank value fallbacks | `force-app/main/default/lwc/contactHealthSummary/*`, `/agent-context/*` | Pending PR |

