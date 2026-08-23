# Multi-hospital schema and authorization audit

Audit date: 2026-08-23 (Asia/Manila)

Scope: the connected live Supabase project, plus the current local Flutter and
`supabase/migrations` workspace. Live catalog queries were used for tables,
columns, constraints, indexes, functions, RLS policies, triggers, grants,
Realtime publication membership, Storage buckets/policies, migration history,
and advisory findings.

## Pre-migration executive findings

- The live database has 48 `public` tables and every one has RLS enabled.
- The current multi-hospital authorization is patient-wide. Clinical policies
  call `private.can_access_patient(patient_id)`, which accepts an active doctor
  assignment or any approved/scheduled/in-progress/completed consultation. It
  does not check originating hospital, receiving hospital, consent scope,
  permitted action, record selection, employment state, revocation, or expiry.
- Only `patient_consents` exists from the requested access-foundation set. It
  currently stores a type/version and grant/revoke flag, but no source/receiving
  hospital, care relationship, categories, record selections, actions, purpose,
  or expiry.
- `guest_consultation_requests` is already a reviewed request path. It creates no
  official consultation until `review_guest_consultation` accepts a request and
  rechecks the selected doctor slot under a transaction-level advisory lock.
- Authenticated patient online booking still calls `book_consultation`, which
  inserts a `consultations` row immediately. Online patient booking therefore
  needs to move to a reviewed request without changing face-to-face booking.
- Clinical provenance was mostly present. The one row with a null
  `medical_documents.hospital_id` was verified as doctor-authored, so its
  hospital was safely derivable from the immutable author relationship.
  `medical_documents` had no direct doctor provenance field; its author was
  only `uploaded_by`.
- The live migration history does not include the local
  `20260823120000_assign_doctors_to_departments.sql` or
  `20260823160000_search_and_link_existing_patients.sql` files. The latter is a
  name/email directory and conflicts with the restricted-discovery decision, so
  it must not be deployed unchanged.
- The Supabase security advisor currently reports 67 findings: one table with
  RLS but no policy, one extension in `public`, 14 authenticated-callable
  security-definer RPC notices, 50 anonymous-sign-in policy notices, and leaked
  password protection disabled. These are recorded as rollout risks; this
  feature's migrations must not add equivalent exposure.

## Live clinical data contract

`!` means non-null in the live database; `?` means nullable.

| Category | Live table/field source | Provenance contract | Gap or action |
|---|---|---|---|
| Consultations | `consultations` | `patient_id?`, `doctor_id!`, `hospital_id!`, `appointment_date!`, `created_at!`, `updated_at!` | `patient_id` is nullable for legacy guest creation, although all five live rows are now linked. Add request/care relationship links and keep identity linkage atomic. |
| Medical records / clinical notes | `medical_records` | `patient_id!`, `doctor_id!`, `hospital_id!`, `consultation_id?`, `record_date!`, `created_at!`, `updated_at!`, `confirmed_by?` | Notes are embedded in records/consultations, not a separate table. Add immutable provenance and addenda/version support. |
| Diagnoses | `diagnoses` | `patient_id!`, `consultation_id!`, `doctor_id!`, `hospital_id!`, `confirmed_at!`, `created_at!`, `updated_at!` | Scope reads by category and source hospital; prevent cross-hospital updates. |
| Prescriptions | `prescriptions` | `patient_id!`, `doctor_id!`, `consultation_id!`, `hospital_id?`, `created_at!`, `updated_at!` | Live row is populated, but the nullable column permits provenance loss. Backfill/quarantine then enforce creation provenance. |
| Laboratory requests | `laboratory_requests` | `patient_id!`, `consultation_id?`, `doctor_id!`, `hospital_id!`, `requested_at!`, `created_at!`, `updated_at!` | Scope reads and writes; require an active assigned consultation for creation. |
| Laboratory results | `laboratory_results` | `patient_id!`, `doctor_id!`, `hospital_id!`, `consultation_id?`, `uploaded_at!`, `updated_at!`, `confirmed_by?`, `reviewed_by?` | No separate `created_at`; `uploaded_at` is the origin timestamp. Add category-aware access and immutable origin. |
| Medical documents | `medical_documents` | `patient_id!`, `hospital_id?`, `uploaded_by!`, `consultation_id?`, `created_at!` | The live null hospital was verified through its doctor author and backfilled. Unresolvable future/legacy rows enter quarantine. Add source labels and a protected download path. |
| Allergies / medications | `patients`, `consultations`, `medical_records`, plus prescriptions | Patient arrays and sourced consultation/record snapshots | Treat new cross-hospital observations as source-labelled observations; do not silently overwrite the global profile arrays. |
| Treatment plans | `treatment_plans` | `patient_id!`, `consultation_id!`, `doctor_id!`, `hospital_id!`, `created_at!`, `updated_at!` | Treat as a clinical category even though it was not separately named in the original list. |

### Existing live rows and provenance gaps

| Table | Rows | Missing patient | Missing hospital | Missing doctor/author |
|---|---:|---:|---:|---:|
| `consultations` | 5 | 0 | 0 | 0 |
| `diagnoses` | 1 | 0 | 0 | 0 |
| `laboratory_requests` | 2 | 0 | 0 | 0 |
| `laboratory_results` | 0 | 0 | 0 | 0 |
| `medical_documents` | 1 | 0 | 1 | 0 (`uploaded_by`) |
| `medical_records` | 6 | 0 | 0 | 0 |
| `prescriptions` | 1 | 0 | 0 | 0 |
| `treatment_plans` | 1 | 0 | 0 | 0 |

The null-hospital document was not inferred from a user's current hospital or a
later consultation: its doctor author provided a stable hospital source. The
migration backfilled that source and would quarantine any row for which author,
consultation, or reference provenance cannot be verified.

## Post-implementation live verification

The foundation and policy-execution migrations were applied transactionally to
the connected project. The post-migration live checks reported:

- 8 patient-hospital identifiers, 9 verified active employments, 6 care
  relationships, and 2 currently active grants.
- Zero unresolved quarantine rows, zero unresolved doctor-authored document
  provenance gaps, zero consultation hospital gaps, zero prescription hospital
  gaps, and zero active assignment provenance gaps.
- The reviewed-online feature flag is enabled only for the designated synthetic
  pilot hospital; all seven other live hospitals remain disabled.
- RLS impersonation shows the demo patient can see exactly one patient identity,
  the assigned demo doctor can see exactly one granted patient identity, and the
  hospital administrator can see operational consultations but zero patients,
  medical records, diagnoses, or grants.
- Private RLS predicate functions are executable only as policy dependencies in
  the non-exposed `private` schema. Public workflow RPCs remain unavailable to
  `anon` and validate actor, relationship, consent, assignment, hospital,
  employment, purpose, category/action, expiry, and revocation internally.

## Current workflow states

### Official consultations

Live enum: `pending`, `approved`, `rejected`, `scheduled`, `in_progress`,
`completed`, `cancelled`.

Current live rows: one `cancelled`, three `completed`, one `scheduled`.

### Guest consultation requests

Live enum: `pending_verification`, `otp_verified`, `pending_doctor_review`,
`approved`, `rejected`, `temporary_patient_created`,
`account_activation_pending`, `consultation_scheduled`,
`consultation_completed`, `cancelled`.

There are currently no live guest requests. The Flutter flow verifies email
before inserting the request, while the database default still uses
`otp_verified`. The current approval RPC atomically rechecks doctor availability,
creates/links the temporary patient, assigns the doctor, and creates the official
scheduled consultation.

### Face-to-face scheduling

Authenticated patient face-to-face booking retains the original immediate slot
reservation path. When the pilot-hospital feature flag is enabled, only the online
branch of `book_consultation` creates a reviewed request; it does not create an
official consultation or reserve a slot until hospital confirmation.

## Existing authorization matrix

| Actor / action | Live rule | Risk relative to target model |
|---|---|---|
| Patient reads own clinical data | `private.can_access_patient` matches `current_patient_id()` | Correct ownership base; retain. |
| Doctor reads any clinical category | Any active `doctor_patient_assignments` row, or any approved/scheduled/in-progress/completed consultation | Too broad; no hospital, purpose, category, action, consent, expiry, or record selection. Completed consultations can confer indefinite access. |
| Doctor creates clinical data | Current doctor plus patient-wide access | Does not prove active employment at the row hospital, active consultation assignment, relationship, consent scope, or same-hospital origin. |
| Doctor updates clinical data | Usually `row.doctor_id = current_doctor_id()` | Prevents many edits, but does not centrally enforce origin hospital or active employment; no addendum-only correction model. |
| Hospital administrator | Has operational consultation/request access and can be a consultation participant | Clinical tables do not directly grant admin reads, but participant helpers and operational/clinical boundaries need to be explicit. |
| External hospital | No first-class source/receiving distinction | Cannot express read-only, scoped, expiring, non-transitive access. |
| Storage read | Patient-folder path plus patient-wide access | Inherits the overly broad patient-wide function and cannot enforce a selected category/action. |
| Audit | Mutation triggers plus `record_clinical_access` / `medical_record_access_logs` | Good base, but list/direct reads are not universally audited and grant/consent decisions need immutable audit events. |

## Required target authorization matrix

Every non-patient clinical read must satisfy all applicable rows below. Failure
of any row is a deny.

| Condition | Enforced by |
|---|---|
| Active authenticated application user | private identity helpers |
| Verified doctor | doctor profile plus verification/employment state |
| Active doctor-hospital employment | `doctor_hospital_employments` and helper |
| Active consultation assignment | consultation/care relationship and assigned doctor |
| Valid care relationship | `patient_care_relationships` status and time window |
| Patient-approved consent | versioned `patient_consents` with purpose, categories/actions, grant/revoke and expiry |
| Active access grant | `patient_access_grants` status, activation, expiry, revocation |
| Permitted category/action | `patient_access_scopes` |
| Selected record, when selection mode is used | `patient_access_record_selections` |
| Correct source/receiving hospitals | grant source and receiver plus record `hospital_id` |
| Non-transitive access | receiving hospital/doctor must match current actor; grants cannot be delegated |
| External records read-only | helper denies create/update/delete when record source differs from current employment hospital |
| Successful/failed sensitive access audit | protected RPCs/triggers and immutable access log |

Patients retain access to their own records. A doctor may create a new record only
for their active employing hospital and active assigned consultation; a grant to
view another hospital's record never authorizes an update or a new record under
the source hospital.

## Storage and Realtime

Private clinical buckets are present for consultation attachments, guest
documents, laboratory results, medical documents, prescriptions, and scanned
results. Their read policies ultimately use the same patient-wide access helper.
They must be replaced with category-aware object checks and a protected,
short-lived download authorization path. Public hospital/profile image buckets
are outside this clinical scope.

Realtime currently publishes consultations, doctor assignments, guest requests,
laboratory results, medical records, prescriptions, video sessions, and several
operational tables. New request-status tracking can be published, but the new
consent/grant tables should not be broadcast broadly; clients should fetch them
through scoped RLS/RPCs.

## Migration and rollout gates

1. Add the foundation tables and category/action helpers without switching old
   clinical policies.
2. Backfill doctor employments, patient-hospital identifiers, care relationships,
   consents, grants, and scopes for existing confirmed consultations.
3. Quarantine unresolved provenance, including the current null-hospital
   document, before applying stricter constraints.
4. Add online request creation/confirmation RPCs and move only authenticated
   online booking to them. Keep face-to-face `book_consultation` behavior.
5. Replace clinical and Storage policies with category-aware default-deny rules.
6. Add immutable provenance/addendum triggers and access audit coverage.
7. Enable the workflow through a hospital-specific feature flag, starting with
   the designated synthetic pilot hospital.
8. Run direct-RPC/RLS tests for cross-hospital denial, revocation, expiration,
   employment termination, reassignment, non-transitivity, and external
   immutability before retiring legacy online booking.

## Acceptance validation

The following live tests execute inside `BEGIN` / `ROLLBACK`; they exercise the
connected Supabase project without retaining fixture data:

- `multi_hospital_authorization_acceptance.sql`: explicit A-to-B consent grants
  the selected A record to the assigned B clinician, B cannot create under A,
  B can create a B record, A does not inherit B's record, administrators cannot
  read the clinical record, and revocation, expiry, employment termination, and
  emergency read-only access all deny or allow as intended.
- `reviewed_online_lifecycle_acceptance.sql`: online submission creates no
  consultation or slot reservation; hospital confirmation atomically creates
  one scheduled consultation and reservation; a conflicting confirmation is
  rejected; patient cancellation updates the official consultation and revokes
  the linked relationship and grants.
- `guest_review_tracking_acceptance.sql`: guest online slots map to published
  schedules, no consultation exists before review, approval links a temporary
  patient and creates the required provenance chain, and reference-based status
  tracking survives a client/session change.
- `direct_rls_boundary_acceptance.sql`: the authenticated API role can read the
  explicitly shared Hospital A record, cannot write under Hospital A, can write
  a separately sourced Hospital B finding only when `create` is explicitly in
  the consent/grant, cannot pass Hospital A data to Hospital C, and cannot use a
  hospital-administrator identity to cross the operational-only boundary.
- `face_to_face_booking_acceptance.sql`: at the feature-enabled pilot hospital,
  face-to-face booking still creates the immediate pending consultation,
  reserves the selected slot, and creates no reviewed-online request.

All five suites passed after the final migration. The reviewed-online suite also
proves profile/phone snapshotting, status/audit history, and that a patient can
join a prepared room during the server-side window without waiting for the
doctor to join. Flutter static analysis also passed, and the 39 focused
guest/workspace/repository action tests passed. The complete non-golden Flutter
suite passed 148 tests with 12 environment-gated live tests skipped.

`supabase/tests/multi_hospital_data_comparison.sql` is the repeatable read-only
provenance report. `supabase/rollback/20260823170000_reviewed_online_workflow.down.sql`
is the guarded operational rollback: it refuses to disable the pilot while a
request is non-terminal, then turns off the hospital flags without deleting
requests, consents, grants, clinical provenance, or audit history.

The live postcondition is zero online test requests, zero unresolved quarantine
rows, and zero `search_existing_patients` / `link_existing_patient` function
overloads. The last point is deliberate: clinician-facing global name/email
patient discovery is not part of the identity-resolution model.

The final advisor scan still reports project-level items outside this migration:
one default-deny `appointment_reminder_jobs` table with no explicit policy,
`pg_net` installed in `public`, anonymous sign-in configuration notices, and
leaked-password protection disabled. Security-definer workflow RPC notices are
expected for the guarded command/query boundary, but each RPC must retain its
internal actor and authorization checks.

## Advisor references

- [RLS enabled without a policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
- [Extension installed in public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public)
- [Authenticated-callable security-definer functions](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
- [Leaked password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
