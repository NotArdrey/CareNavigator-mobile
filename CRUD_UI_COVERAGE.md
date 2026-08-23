# CareNavigator PH — Live Flutter UI CRUD Coverage

Audit date: 2026-08-15 (Asia/Manila)  
Runtime: `flutter run --release -d web-server` at `http://127.0.0.1:7357`, exercised in Brave with Playwright accessibility automation.  
Status: **IN PROGRESS — do not treat this matrix as final while any row is PENDING.**

Evidence artifacts are under `.codex-runtime/ui-audit/`. `discovery.json` contains the full four-role page/control/API inventory; `discovery-hospitalAdmin.json` is the post-fix hospital-scope rerun; `forms.json` records opened forms; `detail-*.json` records the doctor/patient detail and staged action dialogs; `read-interactions-*.json` records filters, searches, tabs, details, and pagination observations; `safe-mutations.json` records notification UI/API/reload evidence. Direct SQL snapshots were also taken for resource counts, the four audit identities, and mutation state.

| Role | Page | Resource | Create | Read | Update | Delete/Cancel | UI tested | API verified | DB verified | Reload verified | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Public/guest | Home / Find care | hospitals, departments, services, doctors, facility availability | N/A — directory is read-only | PASS — live rows rendered | N/A — no control | N/A — no control | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Public/guest | Hospital detail | hospitals, departments, services, doctors, facility/ER availability | N/A — read-only | PASS — detail opened from UI | N/A — no control | N/A — no control | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Public/guest | Find care filters | hospitals | N/A | PASS — text, availability, and location filters | N/A | N/A | Yes | Yes | Yes | N/A — read-only | PASS |
| Public/guest | Find care pagination | hospitals | N/A | N/A — current seven-row result exposes no pagination control | N/A | N/A | Yes | N/A | Yes | N/A | N/A (reason recorded) |
| Public/guest | Clinician directory | doctors, schedules, hospitals | N/A — directory is read-only | PASS — direct deep link and visible Clinicians navigation render one verified clinician | N/A — no control | N/A — no control | Yes — query and no-match states exercised | Yes | Yes | N/A — read-only | PASS (read/filter) |
| Public/guest | Register | auth users, users, patients | PENDING | PENDING | N/A — registration only | N/A — no control | Partial — actual form opened | PENDING | PENDING | PENDING | PENDING |
| Public/guest | Guest consultation request | guest consultation requests | PENDING | PENDING — reference/verification flow | N/A — no edit control | PENDING — reject handled by reviewer | Partial — actual form opened | PENDING | PENDING | PENDING | PENDING |
| Public/guest | Care assistant | transient AI assessment | N/A — no durable CRUD resource exposed | PASS — UI entry controls inventoried | N/A | N/A | Yes | PENDING — external AI invocation not yet exercised | N/A — transient | N/A | PENDING |
| Patient | Home | dashboard aggregates, hospitals | N/A — no create control | PASS — live directory/aggregates rendered | N/A | N/A | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Patient | Appointments / Consultations | consultations | PENDING | PASS — authoritative empty state matches audit patient | PENDING — reschedule requires created row | PENDING — cancel requires created row | Yes; booking form opened | Yes (read) | Yes | PENDING | PENDING |
| Patient | Medical Overview | medical records | N/A — patient has no create control | PASS — authoritative empty state | N/A — no edit control | N/A — no delete control | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Patient | Lab Results | laboratory results, medical documents/storage | PENDING — upload | PASS — authoritative empty state | N/A — no edit control | N/A — no delete control | Yes; upload control inventoried | Yes (read) | Yes | PENDING | PENDING |
| Patient | Prescriptions | prescriptions, medical documents/storage | PENDING — upload document | PASS — authoritative empty state | N/A — no edit control | N/A — no delete control | Yes; upload control inventoried | Yes (read) | Yes | PENDING | PENDING |
| Patient | Messages inbox/detail | chat conversations, messages, attachments/storage | PENDING — conversation/message/attachment | PASS — empty inbox and search/clear verified | PENDING — read receipt where applicable | N/A — no delete control | Yes; start flow navigates to consultations | Yes (read) | Yes | PENDING | PENDING |
| Patient | Notifications | notifications | N/A — system-created only | PASS | PASS — Mark read | N/A — no delete control | Yes | Yes — RPC 204 | Yes — `is_read=true` | Yes | PASS |
| Patient | Profile | users, patients, profile image/storage | N/A — profile already exists | PASS — live values rendered | PENDING | N/A — no delete control | Yes; actual edit form opened | Yes (read) | Yes | PENDING | PENDING |
| Doctor | Workspace | consultation/assignment/schedule/lab aggregates | N/A — dashboard is read-only | PASS — live metrics rendered | N/A | N/A | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Doctor | Scheduling / Availability | doctor schedules | PENDING | PASS — empty list matches audit doctor | PENDING — publish/unpublish | PENDING — delete availability | Yes; actual slot form opened | Yes (read) | Yes | PENDING | PENDING |
| Doctor | Scheduling / Appointments | consultations | PENDING — via patient detail/booking | PASS — tab exercised | PENDING — lifecycle | N/A — doctor has no hard-delete control | Yes | Yes (read) | Yes | PENDING | PENDING |
| Doctor | Patients list/detail | doctor-patient assignments | PENDING — register/link | PASS — assigned audit patient rendered | N/A — no assignment edit control | N/A — no end/delete control exposed | Yes; registration form opened | Yes (read) | Yes | PENDING | PENDING |
| Doctor | Patients list/detail | users, patients | PENDING — register patient/account | PASS — actual linked patient data rendered | PENDING — account status is admin-only | N/A — no delete control | Yes | Yes (read) | Yes | PENDING | PENDING |
| Doctor | Patient detail | medical records/documents | PENDING — follow-up checkup + optional attachment | PASS — current patient detail | N/A — no edit control | N/A — no delete control | Yes — actual checkup dialog and all clinical fields opened without submission | Yes (read) | Yes (current count 0) | PENDING | PENDING |
| Doctor | Consultations | consultations | PENDING — book appointment from patient | PASS — authoritative empty state for audit doctor | PENDING — approve/start/complete | N/A — no doctor cancel/delete control | Yes — actual appointment dialog opened without submission | Yes (read) | Yes | PENDING | PENDING |
| Doctor | Patient detail | prescriptions/documents | PENDING | PASS — relationship precondition inspected | N/A — no edit control | N/A — no delete control | Partial — action requires consultation | PENDING | Yes (current count 0) | PENDING | PENDING |
| Doctor | Laboratory / Orders | laboratory requests/documents | PENDING | PASS — authoritative empty state | N/A — no edit control | PENDING — audit-preserving cancel | Yes; tab/action inventoried | Yes (read) | Yes (current count 0) | PENDING | PENDING |
| Doctor | Laboratory / Results Review | laboratory results, medical records | N/A — patient uploads result | PASS — tab exercised and empty state matches DB | PENDING — analyze/confirm/reject | N/A — no delete control | Yes | Yes (read) | Yes | PENDING | PENDING |
| Doctor | Messages inbox/detail | chat conversations, messages, attachments/storage | PENDING — message/attachment | PASS — empty inbox and search/clear verified | PENDING — read receipt | N/A — no delete control | Yes; start flow navigates to Patients | Yes (read) | Yes | PENDING | PENDING |
| Doctor | Notifications | notifications | N/A — system-created only | PASS | PASS — Mark read | N/A — no delete control | Yes | Yes — RPC 204 | Yes — `is_read=true` | Yes | PASS |
| Doctor | Profile | users, doctors, profile image/storage | N/A — already exists | PASS — live profile rendered | PENDING | N/A — no delete control | Yes; actual form opened | Yes (read) | Yes | PENDING | PENDING |
| Hospital administrator | Overview | assigned-hospital aggregates | N/A — dashboard is read-only | PASS after scope fix | N/A | N/A | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Hospital administrator | Appointments | consultations, guest consultation requests | N/A — no create control | PASS — exactly two assigned-hospital consultations | PENDING — guest approve/reject when fixture exists | N/A — no delete control | Yes | Yes | Yes | N/A/PENDING | PENDING |
| Hospital administrator | Facility / Capacity | hospital beds | N/A — no create control | PASS — DB has no assigned-hospital bed row | PENDING when a row exists | N/A — no delete control | Yes | Yes | Yes | PENDING/N/A | PENDING |
| Hospital administrator | Facility / Rooms | hospital rooms | N/A — no create control | PASS — exactly one assigned-hospital room | PENDING — edit capacity | N/A — no delete control | Yes; Rooms tab exercised | Yes | Yes | PENDING | PENDING |
| Hospital administrator | Emergency room | emergency room status | N/A — no create control | PASS — exactly one assigned-hospital row | PENDING — availability status | N/A — no delete control | Yes | Yes | Yes | PENDING | PENDING |
| Hospital administrator | Facility availability | hospital facility status | N/A — no user-accessible create control | N/A — no administrator navigation/control exposes this table directly; public directory read is covered above | N/A — no exposed control | N/A — no exposed control | Yes — absence verified in navigation/control inventory | N/A | Yes — 37 backend rows exist globally | N/A | N/A (reason recorded) |
| Hospital administrator | Services & Depts / Services | hospital services | PENDING | PASS — exactly eight assigned-hospital rows after scope fix | PENDING — availability | PENDING — hard delete with FK check | Yes; form/search/actions inventoried | Yes (read) | Yes | PENDING | PENDING |
| Hospital administrator | Services & Depts / Departments | hospital departments | PENDING | PASS — exactly eight assigned-hospital rows after scope fix | PENDING — availability | PENDING — hard delete with FK check | Yes; form/tab/actions inventoried | Yes (read) | Yes | PENDING | PENDING |
| Hospital administrator | Staff | users, doctors | PENDING — doctor account | PASS — exactly four assigned-hospital staff | PENDING — account status | N/A — no delete control | Yes; actual doctor form opened | Yes (read) | Yes | PENDING | PENDING |
| Hospital administrator | Audit & Reports / Audit | audit logs | N/A — system-created | PASS — live rows/search rendered | N/A — immutable | N/A — immutable | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Hospital administrator | Audit & Reports / Reports | hospital analytics RPC | N/A — computed | PASS — report tab and live aggregates rendered | N/A — computed | N/A — computed | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Hospital administrator | Notifications | notifications | N/A — system-created only | PASS | PASS — Mark read | N/A — no delete control | Yes | Yes — RPC 204 | Yes — `is_read=true` | Yes | PASS |
| Hospital administrator | Profile | users, profile image/storage | N/A — already exists | PASS — live profile rendered | PENDING | N/A — no delete control | Yes; actual form opened | Yes (read) | Yes | PENDING | PENDING |
| Super administrator | Governance | platform aggregates | N/A — dashboard is read-only | PASS — live metrics rendered | N/A | N/A | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Super administrator | Approvals | hospitals | N/A — no create control | PASS — eight DB hospitals rendered | PENDING — approve/reject needs pending fixture | N/A — no delete control | Yes | Yes | Yes | PENDING/N/A | PENDING |
| Super administrator | Accounts | users/governance accounts | N/A — no create control | PASS — live rows and search verified | PENDING — active/inactive/suspended | N/A — no delete control | Yes | Yes | Yes | PENDING | PENDING |
| Super administrator | System / Permissions | role permissions | N/A — seeded governance rows | PASS — 26 rows rendered | PENDING — allow/deny | N/A — no delete control | Yes | Yes | Yes | PENDING | PENDING |
| Super administrator | System / Settings | system settings | N/A — seeded keys only | PASS — five rows rendered | PENDING — text/bool edit | N/A — no delete control | Yes; actual edit form opened | Yes | Yes | PENDING | PENDING |
| Super administrator | System / Security | security logs | N/A — system-created | PASS — 16 live rows rendered | N/A — immutable | N/A — immutable | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Super administrator | System / Maintenance | maintenance windows | PENDING | PASS — authoritative empty state | PENDING — activate/deactivate | PENDING — hard delete | Yes; actual form opened | Yes (read) | Yes (current count 0) | PENDING | PENDING |
| Super administrator | System / Audit | audit logs | N/A — system-created | PASS — live rows rendered | N/A — immutable | N/A — immutable | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Super administrator | Analytics | platform analytics RPC | N/A — computed | PASS — live response rendered | N/A — computed | N/A — computed | Yes | Yes | Yes | N/A — read-only | PASS (read) |
| Super administrator | Notifications | notifications | N/A — system-created only | PASS | PASS — Mark read | N/A — no delete control | Yes | Yes — RPC 204 | Yes — `is_read=true` | Yes | PASS |
| Super administrator | Profile | users, profile image/storage | N/A — already exists | PASS — live profile rendered | PENDING | N/A — no delete control | Yes; actual form opened | Yes (read) | Yes | PENDING | PENDING |

## Confirmed defect and retest

- **Fixed:** hospital-administrator workspace reads previously relied only on broad public SELECT policies and therefore rendered every hospital's consultations/facilities/services/departments with management controls. `SupabaseWorkspaceRepository` now applies the signed-in administrator's `hospital_id` to hospital-scoped list/dashboard queries and to guest-request intake rows.
- **Retest:** Flutter analysis passed; 50 affected widget/action tests passed (four live tests skipped without their separate demo credentials); the rebuilt Brave UI matched direct SQL counts for the assigned hospital and reported no failed requests or console errors.
- **Fixed:** browser deep links such as `/doctors` rendered the public home screen and subsequent navigation produced mixed path/hash URLs. The web entry point now uses Flutter's path URL strategy and the router no longer forces `/` as its initial location.
- **Retest:** analysis and 10 navigation/shell tests passed; a fresh Brave tab opened `/doctors` directly, rendered the clinician directory at the clean path, and its query/no-match states behaved correctly.

## Actionable control inventory

Repeated shell controls were exercised for every authenticated role: role navigation destinations, Messages, Notifications, Profile, Care assistant, Refresh where shown, and Sign out. Public shell controls inventoried were CareNavigator home, Find care, Clinicians, Book consultation, Sign in, Care assistant, and the global care search.

| Role / surface | Actionable controls inventoried |
| --- | --- |
| Public home / hospitals | Search care, Find a hospital, See all, hospital detail cards, Map view, View map, Request care, location selector, care-level selector, Available only, directory query, clear filters |
| Public clinicians | clinician query/clear, specialty selector, location selector, Online care, Available facility, sort, clinician Hospital, Request care, Hospital directory |
| Public auth / request | Register, sign-in, forgot/reset/OTP navigation; guest consultation step controls and verification/reference flow (submission pending confirmation) |
| Patient appointments / consultations | Book consultation; clinician, care mode, schedule, concern, Cancel, Choose schedule (submission and row lifecycle pending) |
| Patient records / labs / prescriptions | Upload diagnostic result, Upload Prescription, attachment picker controls (uploads pending) |
| Patient messages | Search conversations, clear search, Start a conversation; conversation/message/attachment controls remain conditional on a created consultation |
| Patient notifications | notification record and Mark read (mutation, API, DB, and reload passed) |
| Patient profile | Choose photo, Save changes, sex, first/last name, birth date, mobile, address, blood type, emergency contact, allergies, conditions; email confirmed disabled |
| Doctor scheduling | Availability/Appointments tabs, Add slot; day, care mode, start/end time, duration, Cancel, Publish slot (submission and row lifecycle pending) |
| Doctor patients | patient row/detail, Register patient, New/Existing mode, identity/contact/account fields, Follow-up checkup, Message Patient, Add Record, Issue Prescription, Upload diagnostic result |
| Doctor checkup dialog | attachments and Groq AI auto-fill, reason, vitals, symptoms, conditions, allergies, medications, history/surgeries, smoking/alcohol/pregnancy selectors, notes and observations, Cancel, Save follow-up |
| Doctor consultations / laboratory | consultation lifecycle actions when a row exists; Orders/Results Review tabs, Request test, result analyze/confirm/reject and order cancel when fixtures exist |
| Doctor messages / notifications / profile | conversation search/clear/start; Mark read (passed); profile fields/actions (update pending) |
| Hospital admin appointments | consultation rows; guest approve/reject controls conditional on a pending request |
| Hospital admin facility / ER | Capacity/Rooms tabs, room edit capacity, ER Search visible records, Update availability (row mutations pending) |
| Hospital admin services/departments | Services/Departments tabs, Search visible records, Add service, Add department, optional department selector, name/description, Update availability, Delete record, Cancel/add controls |
| Hospital admin staff | Add doctor, doctor/account fields, temporary password/confirmation, license/specialization, Change account status |
| Hospital admin audit/reports | Audit/Reports tabs and Search visible records; report data is computed/read-only |
| Hospital admin notifications/profile | Mark read (passed); Choose photo, Save changes, sex and identity/contact fields (profile update pending) |
| Super admin approvals/accounts | Search visible records, hospital approve/reject when pending, Change account status and status choices/confirmation |
| Super admin system | Permissions/Settings/Security/Maintenance/Audit tabs, permission Allow/Deny, setting Edit/Save, maintenance title/message/schedule/create plus row activate/deactivate/delete when created |
| Super admin analytics/notifications/profile | computed analytics read; Mark read (passed); Choose photo, Save changes, sex and identity/contact fields (profile update pending) |
