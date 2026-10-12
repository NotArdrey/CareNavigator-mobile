# CareNavigator PH workflow and completeness audit

Reviewed on **11 October 2026, Asia/Manila**, against the current working tree and the live Supabase project.

**Verdict: the system is not complete. It has confirmed logic defects, user-facing dead ends, and mismatches between its interface, database rules, and deployed services.** Passing compilation and ordinary widget tests does not resolve these failures.

This is a system-wide review of role navigation, repositories, booking and review states, patient identity, clinical uploads, prescribing, notifications, permissions, deployment artifacts, and the defense diagrams. It includes live database acceptance tests and focused rollback-only probes. It is not a claim that every screen was exercised through a real authenticated browser session.

## Verification performed in this review

| Check | Result |
| --- | --- |
| `flutter analyze` | Pass; no issues |
| Behavioral suite, excluding `golden` | 236 passed; 11 live tests skipped |
| Golden suite | 8 passed; 8 failed |
| Existing live database acceptance scripts | 5 passed; 1 failed |
| Patient rescheduling probe | Failed with SQLSTATE `42703` |
| Patient prescription and diagnostic metadata inserts under `authenticated` role | Both rejected by the doctor-only upload trigger |
| Guest approval handoff probe | Consultation created; patient remains temporary and unlinked to an account |
| Online no-show probe | Request becomes `no_show`; official appointment remains `scheduled`; 7 relationship grants remain active |
| Email action authorization probe | Public client key passes application authentication and reaches medication validation, returning HTTP 400 |
| Invalid JWT probe | Gateway rejects it with HTTP 401; this does not prevent the public-key authorization issue |
| Live schema check | All 61 public tables have RLS enabled |
| Deployed function inspection | All 6 functions retrieved; the chat function contains the email authorization and credential issues below |
| ERD column comparison | 14 diagrammed column names do not exist in the live schema |

Passing database scripts: `face_to_face_booking_acceptance.sql`, `email_consultation_channel_acceptance.sql`, `guest_review_tracking_acceptance.sql`, `multi_hospital_authorization_acceptance.sql`, and `direct_rls_boundary_acceptance.sql`.

Failing script: `reviewed_online_lifecycle_acceptance.sql`. It stops at a consultation appointment-date update because of finding 3. Therefore its later video, cancellation, and auditing assertions were not reached in this run.

All database fixtures were rolled back. Final checks found zero `GST-TEST-*` guest requests and zero audit-upload document rows, and the online-request state aggregate returned to its original value. No email was sent, no account password was changed, and no application or deployed backend repair was applied.

## Findings, in repair priority

### 1. Critical: SMTP credentials are embedded in source and deployment

**Evidence:** `supabase/functions/care-navigator-chat/index.ts:1716`, `:2049`, and `:2172`. Fresh deployed-source inspection confirms a literal SMTP password fallback there too. The credential value is intentionally excluded from this report. The existing health report also records a successful authentication check for the exposed credential.

**Effect:** possession of the source gives access to a server credential. Environment secrets do not protect a working literal fallback left in tracked or deployed code.

**Repair:** remove the literals, rotate the exposed app password, configure a server-only replacement, and deploy the corrected source.

### 2. Critical: public client credentials authorize privileged email actions

**Evidence:** `supabase/functions/care-navigator-chat/index.ts:1622` and `:1874` treat `token === publishableKey` as a system identity. The handlers accept caller-supplied `patient_id` and `recipient_email`, then perform service-role patient/prescription queries. They do not establish that the caller is the patient, an authorized treating doctor, or an authorized scheduler. `handleTestEmailDelivery` at `:2159` checks only for an Authorization header and accepts a caller-selected recipient.

**Reproduction:** a request with the application's public key and an empty medication list reaches the prescription handler's HTTP 400 medication validation, rather than being rejected for lacking a user identity. This payload stops before delivery. A malformed JWT is rejected by the gateway, so the finding is specifically an accepted public credential being treated as privileged authority.

**Effect:** the code permits email abuse and, for the reminder action, forwarding service-role prescription data to a supplied recipient. No such forwarding was attempted during this review.

**Repair:** validate a real user identity and its active role/relationship; derive the patient and recipient from authorized records. Keep scheduler authority separate from public client keys. Remove or restrict the diagnostic email action.

### 3. High: normal patient rescheduling fails in the live database

**Evidence:** `supabase/migrations/20260823320000_enforce_reservation_lead_time.sql:82–90`; the deployed function has the same implementation. The shared trigger combines a table-name condition with field references that do not exist on every participating row type.

**Reproduction:** book a valid face-to-face slot, approve the consultation, and call `reschedule_consultation` as its patient with another available slot. The call fails with `record "new" has no field "preferred_schedule"`, SQLSTATE `42703`. The existing online lifecycle acceptance test fails at the same trigger.

**Effect:** the visible Reschedule control cannot complete an otherwise valid appointment change.

**Repair:** branch on the table before referencing its fields, retain the 24-hour rule, and retest updates for all three trigger tables and the patient RPC.

### 4. High: patient upload controls conflict with the live upload rules

**Evidence:** patient upload actions in `lib/src/features/workspaces/live_workspace_view.dart`, the insertion in `lib/src/repositories/care_repository.dart:2069`, and `private.set_medical_document_ai_state` in `supabase/migrations/20260823320000_structured_diagnostic_results.sql:57`.

**Reproduction:** both a prescription document and a diagnostic-result document inserted under an authenticated patient role fail with `Only an authorized treating doctor may upload diagnostic results or prescriptions`.

**Effect:** the interface offers actions that the backend consistently rejects. The upload repository attempts to remove the already-uploaded storage object when the metadata insert fails.

**Repair:** decide whether these are patient-supplied documents or doctor-only official records. Align the UI, provenance, storage policy, AI state, and database insert rule around that distinction, then test both roles.

### 5. High: approved guests have no complete account or video handoff

**Evidence:** approval creates a patient with `profile_status='temporary'`, `account_activation_status='pending'`, and no `user_id` in `supabase/migrations/20260823170000_multi_hospital_access_foundation.sql:4220`. The deployed `care-workflows` function supports `create_patient_account`, but the Flutter repository only invokes `create_direct_patient_account` (`lib/src/repositories/care_repository.dart:1254`). The tracked confirmation view (`lib/src/features/guest_consultation/guest_verification_screen.dart:242`) offers Refresh and Return to directory, without conversion or video Join controls.

**Reproduction:** guest approval successfully creates an official consultation, while the submitting account remains role `guest` and the temporary patient has no linked account.

**Effect:** the database review succeeds, but the promised transition into authenticated longitudinal care is missing. A guest online appointment also lacks an exposed way to join its room from tracking, even though the backend supports guest participant authorization.

**Repair:** expose a secure conversion/activation flow for the existing temporary identity and a scheduled guest Join action. Verify that activation preserves the same patient, appointment, and clinical history.

### 6. High: online-request transitions do not finalize the official consultation

**Evidence:** `transition_online_consultation_request` at `supabase/migrations/20260823170000_multi_hospital_access_foundation.sql:1731` updates only the request. Synchronization runs from consultation changes toward the request, not the reverse.

**Reproduction:** after confirming an online request, transition it to `no_show`. The request says `no_show`, its consultation remains `scheduled`, and 7 associated grants remain active. The function also accepts this transition while the appointment is still in the future.

**Effect:** request tracking, appointment status, slot occupancy, and access lifecycle disagree. Other terminal request transitions need the same review.

**Repair:** define valid predecessor states and timing, then update the official consultation, room, relationship, and grants atomically when the request reaches a terminal outcome.

### 7. High: prescription issuance can partially save an order

**Evidence:** the multi-medication loop in `lib/src/features/workspaces/live_workspace_view.dart:1818` commits one medication at a time. `createPrescription` inserts its row before uploading an optional attachment (`lib/src/repositories/care_repository.dart:1854`).

**Failure path identified in code:** if a later medication or the first attachment fails, earlier prescriptions remain saved, the overall action reports an error, and the usual refresh is not reached. Retrying can create additional rows. This failure path was not exercised with live clinical writes.

**Repair:** create an explicit prescription order/batch with transactional medication persistence and idempotent submission. Report attachment failures as partial success when the clinical order has already committed.

### 8. High: direct email and medication reminders bypass the preference workflow

**Evidence:** prescription issuance calls the direct email action automatically (`live_workspace_view.dart:1841`). Neither direct email handler checks `notification_preferences`. The reminder query (`care-navigator-chat/index.ts:1966`) loads all prescriptions for a patient without start/end-date filtering, despite calling them active prescriptions. `sendPrescriptionNotificationEmail` swallows failures (`care_repository.dart:2000`), while the UI still says an email was sent (`live_workspace_view.dart:1868`).

The direct handlers also insert notification fields named `body` and `type` (`index.ts:1833`, `:2132`); the live table uses `message` and `notification_type`. Those insertion errors are caught and suppressed. The generic notification dispatcher uses the correct contract.

**Effect:** automatic prescription email can disregard opt-in preferences; failed delivery can be presented as success; direct in-app notification inserts can fail silently. Future or expired prescriptions would be included in a reminder. The current database has zero dated expired/future prescriptions, so the last issue is a code-confirmed failure condition rather than an observed incorrect reminder.

**Repair:** use the authorized, preference-aware outbox for automatic delivery; filter medication eligibility by prescribed dates; use the live notification schema; distinguish queued, sent, and failed outcomes.

### 9. Medium: several backend workflow states have no usable client process

**Evidence:** the online UI provides hospital Confirm/Reject and patient Cancel (`live_workspace_view.dart:1311–1348`), while the repository/backend supports additional review outcomes. There is no client call to `transition_online_consultation_request` or `revoke_patient_access_grant` anywhere in `lib`.

**Effect:** additional-information requests have no patient response action; schedule proposals have no patient acceptance action; no-show/contact/follow-up recommendations have no complete operator flow. Patients select sharing categories when booking but cannot subsequently revoke an active grant through the product.

**Repair:** either implement these states with an actor, visible next action, notification, and terminal outcome, or remove unsupported states from the advertised process. Add patient sharing management and scoped revocation.

### 10. Medium: rescheduling would leave online confirmation timestamps stale

**Evidence:** `reschedule_consultation` updates only `consultations.appointment_date`. The care-access synchronization trigger listens to `status` and `doctor_id`, not appointment date (`multi_hospital_access_foundation.sql:2414`). The online request retains its `confirmed_schedule`; its transition function uses that timestamp for its appointment window.

**Effect:** after finding 3 is repaired, appointment and request tracking can still disagree about the confirmed time and contact window. This is a separate latent defect identified from the live definitions; the broken trigger prevents an ordinary live reschedule from reaching it today.

**Repair:** synchronize the request timestamp and relevant access/room validity on rescheduling, with tests for both earlier and later moves.

### 11. Medium: deployed schema and source do not match client expectations

Fresh catalog checks confirm that `care_assistant_conversations` is missing, although the history repository loads, saves, pins, renames, and deletes it (`lib/src/repositories/care_assistant_history_repository.dart:44`). History cannot persist across sessions in this deployment.

The live `notification_preferences.medication_reminders` column is also missing. Independently, `NotificationPreferenceUpdate.toJson()` omits `medicationReminders` (`lib/src/repositories/profile_repository.dart:152`), although the profile UI supplies it. Deploying the column alone will not make the separate switch persist. The deployed dispatcher produces appointment reminders; this review found no scheduled medication-reminder producer.

Fresh deployed chat-source inspection also confirms that it lacks the local vision-model fallback handling recorded in the existing health report. Provider model viability was not rechecked by sending an extraction request during this review.

**Repair:** reconcile deployed objects and function source against required client contracts, fix the serializer, and clarify whether medication reminders are manual or scheduled.

### 12. Medium: booking messages and eligibility apply inconsistent processes

**Evidence:** only 1 of 7 published hospitals enables the reviewed-online workflow; 6 do not. Seven doctors at non-enabled hospitals publish online schedules. `book_consultation` therefore has two actual online paths, but the UI always tells the patient the request awaits hospital review and the slot is not reserved (`live_workspace_view.dart:2070`). The non-enabled path creates an immediate pending consultation and reserves the slot instead.

Separately, `hospital_repository.dart:223` folds ER `full`/`temporarily_closed` status into the hospital's general availability. The reservation dialog disables that hospital and its clinicians for all modes, including online care. The booking RPC does not impose that ER-capacity rule.

**Repair:** return a typed booking outcome and display its actual status/reservation semantics. Define separate eligibility for ER, outpatient, and online services. If an ER closure is intentionally meant to stop all care, document and enforce that rule consistently on the server.

### 13. Medium: prescription display grouping can combine distinct orders

**Evidence:** `workspace_repository.dart:865–869` groups rows whenever they share a consultation, regardless of issuance time, or share patient/doctor and occur within five minutes. Attachments are matched by a time heuristic rather than their explicit prescription reference (`:908`). A missing prescription detail can fall back to the first available group (`:269`).

**Effect:** separate orders can appear as one prescription, an attachment can be associated with the wrong order, and an unavailable requested record can display another group instead of a not-found state.

**Repair:** use an explicit order/batch identifier and reference-based attachment matching. Preserve distinct orders and show a missing-record state for unmatched details.

### 14. Medium: the repository cannot reproduce the whole deployed backend

Only `care-navigator-chat` exists in the tracked `supabase/functions` source tree, although six functions are deployed and required. The other five were inspected from the live deployment in this audit.

The migration history in this repository starts by altering existing `hospitals`/`users` objects and relies on existing enums/private helpers. It does not contain the base definitions for core tables such as hospitals, users, roles, consultations, or doctor schedules. A clean empty project cannot be reconstructed from the committed migrations alone.

**Repair:** version the baseline schema and all required Edge Functions, document server configuration, and verify a clean test-project installation before calling the deliverable complete.

### 15. Medium: verification and the defense ERD are not aligned

Eight golden comparisons fail for guest, patient, doctor, and doctor-prescription views at mobile/web sizes. These require design review; a screenshot difference alone is not proof of a business-logic defect.

The ERD has 14 physical column mismatches: `roles.name`, `role_permissions.permission_key`, `users.status`, `hospital_classifications.name`, `hospitals.name`, `hospital_departments.name`, `hospital_departments.is_active`, `healthcare_service_categories.name`, `healthcare_service_categories.slug`, both online-history `old_status`/`new_status` fields, `patient_consents.status`, `prescriptions.status`, and `laboratory_results.review_status`.

**Repair:** align the diagram with the physical schema or clearly label it as conceptual. Review intentional UI changes before replacing visual baselines.

## Remaining validation questions

- **Password recovery:** the repository sends recovery email without an explicit redirect destination, and the app does not handle a password-recovery event by routing to `/reset-password`. The external Auth URL/template configuration might supply the destination; the complete email-link-to-password-change path still needs verification.
- **Guest retry:** verification consumes the OTP before request insertion, but a failed insertion leaves the controller in `awaitingVerification` (`guest_consultation_provider.dart:197`). A retry re-verifies the same code. Verify insertion failure, code resend, and recovery without duplicate requests or lost intake.
- **Schedule deletion:** the repository's deletion guard parses only `HH:mm`, while database time fields can contain seconds; the visible schedule annotation uses a different parser. It also checks reservations outside a server transaction. Verify deletion against a newly booked slot and with a client outside Manila time, then enforce protection on the server.
- **Actual integrations:** authenticated browser flows, Realtime account switching, uploads/downloads, AI extraction, Jitsi media, and delivered email were not verified end to end here. The existing health report records stale saved test credentials; this audit did not reset them or create replacement accounts.

## Recommended repair sequence

1. Remove/rotate the exposed credential and close public-key email authority.
2. Fix the live rescheduling trigger and reconcile patient upload ownership rules.
3. Complete guest activation/video handoff and terminal online-state synchronization.
4. Make prescription issuance atomic/idempotent and align delivery with patient preferences.
5. Connect the remaining review/consent actions; synchronize reschedule timestamps and booking outcomes.
6. Reconcile deployment objects, version the full backend, and correct the ERD/baselines.
7. Run complete guest, patient, doctor, hospital-admin, and super-admin journeys using dedicated working test accounts, including rejection, cancellation, expired sessions, failed uploads, unavailable slots, and failed delivery.

The main architecture and several important boundaries are present: face-to-face booking, reviewed online confirmation, guest review, and the tested cross-hospital/RLS restrictions passed their database checks. These strengths do not close the failures above.

Detailed evidence is saved in the gitignored `.codex-runtime/` directory: `workflow-metadata.json`, `workflow-acceptance.json`, `workflow-probes.json`, `workflow-auth-probes.json`, `workflow-extra.json`, `workflow-goldens.log`, and the retrieved `workflow-edge-*.json` source snapshots. Deployed source snapshots can contain secrets and should remain local.
