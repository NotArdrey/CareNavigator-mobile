# CareNavigator PH Verification Report

Date: 2026-08-09 (Asia/Manila)

## Verification summary

| Area | Result |
| --- | --- |
| Flutter static analysis | Passed with no issues |
| Full Flutter test suite | 26 passed; 1 intentional live-contract skip in the ordinary run |
| Live anonymous Supabase contract | Skipped because public Supabase test variables were not supplied |
| Flutter web release build | Passed with no Dart defines; output `build/web` |
| Android debug build | Passed with no Dart defines; output `build/app/outputs/flutter-apk/app-debug.apk` |
| Live Supabase migration verification | Passed through MCP |
| Browser-engine screenshot/console run | Unavailable: no browser was connected to the in-app browser runtime |
| iOS build | Not run on the Windows host |

## Runtime-tested behavior

The widget/unit suite exercises public hospital and clinician discovery; explicit unavailable/loading/empty states; deterministic emergency escalation; auth validation and account states; public route/query behavior; root overlay ordering; and responsive public shells. Authenticated workspace actions remain repository-backed and require a configured session and live records.

Repository validation tests confirm unsafe mutation inputs are rejected before a network request, including messages, schedules, prescriptions, laboratory priorities, booking modes, account statuses, operational allowlists, administrator deletion targets, doctor account fields, guest decisions, and maintenance ordering.

The anonymous live contract test loads the real verified hospital directory and confirms exact department IDs without privileged credentials. It is skipped in `flutter test` unless task-specific test variables are supplied; no public test variables were available for this run.

## Build-verified and code-reviewed behavior

- The release web and Android artifacts compile without environment-specific substitutes or privileged credentials; runtime data still requires the configured public Supabase URL/key.
- Real signed-in identities use RLS-backed workspace snapshots; no alternate local record source is selected.
- Public hospital/clinician queries explicitly require verified, operating hospitals, available clinicians, and active published schedules, including when an authenticated admin has broader RLS visibility.
- Patient booking calls the deployed `book_consultation` RPC; server code verifies patient profile, clinician/hospital relationship, recurring schedule, and slot collision. Approved/scheduled rescheduling uses the guarded transition RPC.
- Consultation lifecycle, structured doctor summary/diagnosis/treatment/notes, guest review, secure Jitsi room lookup, prescriptions, lab requests, preliminary-result AI analysis and doctor decisions are connected with exact IDs.
- Realtime drives conversation messages and account notifications. Send/read actions, busy/error states, refreshes, and duplicate-submit prevention are wired.
- Medical files accept PDF/JPEG/PNG up to 20 MB, upload to private Storage, create metadata only after storage succeeds, remove the object if metadata fails, log clinical downloads, and issue short signed URLs.
- Hospital operations support capacity, room, facility, ER, service, and department status. Hospital admins can add/delete services/departments, provision doctors through the privileged Edge Function, and manage account states. Super admins can review hospitals with decision notes, manage accounts/permissions/settings, and schedule/activate/delete maintenance windows.
- Live detail pages show allowlisted clinical/operational fields and do not expose authentication IDs, storage paths, or other internal identifiers.
- The shadcn request was honored through native Flutter composition patterns and centralized tokens. React shadcn/ui was not installed because the governing specification explicitly prohibits replacing the Flutter component system.

## MCP-verified backend

- Intended CareNavigator project ref: `crhsbpkuteyqbxjpozrp`.
- 49 public tables have RLS enabled; relevant columns, keys, foreign keys, constraints, policies, functions, indexes, and relationships were inspected before mapping.
- Realtime publication contains 19 tables.
- Required active Edge Functions: `analyze-symptoms`, `admin-users`, `care-workflows`, `analyze-medical-result`, and `dispatch-notifications`.
- Private Storage and signed-download authorization were inspected.
- Notification dispatch uses Cron and pg_net.
- Migrations `20260809170000_hospital_verification_decisions.sql` and `20260809173000_harden_hospital_verification_rpc.sql` were applied live. The columns/RPC and final execution grants were re-read; only `authenticated`, `postgres`, and `service_role` can execute the governance RPC.

Security advisor findings retained for operator review:

- `appointment_reminder_jobs` intentionally has no client RLS policies and is service-only.
- pg_net resides in the public extension schema.
- The authenticated security-definer functions `get_patient_medical_records`, `record_clinical_access`, and `review_hospital_application` are intentional and verify permissions internally.
- Anonymous-policy advisor notices are mitigated by authenticated helper predicates in the policies inspected.
- Leaked-password protection is disabled in the Supabase dashboard and should be enabled before production launch.
- Unused-index notices are informational for the current data volume.

## Screenshot review

The previous visual-catalog test was removed with the obsolete UI it exercised. The remaining PNG files under `test/visual_catalog` are static reference artifacts only; they are not loaded, served, or used as production data.

An HTTP 200 smoke check was completed against a local static server serving the release web artifact. The in-app browser discovery returned no available browser, so DOM interaction, browser console, and authenticated browser screenshots could not be verified or claimed.

## Remaining production verification

- Exercise patient, doctor, hospital-admin, and super-admin live sessions with dedicated non-production accounts and seeded relationship data. No such credentials were available for this run.
- Verify SMTP delivery, Groq provider responses, Jitsi camera/microphone behavior, and scheduled dispatch in their external provider dashboards; their server implementations/contracts were inspected, but outbound production side effects were not triggered.
- Run physical Android device tests and an iOS build/device pass on macOS.
- Enable leaked-password protection and decide whether to relocate pg_net from the public extension schema.
- Run a real browser visual/console pass when a browser connection is available.

These limitations do not invalidate the static analysis, automated interaction tests, compiled artifacts, or MCP verification described above.
