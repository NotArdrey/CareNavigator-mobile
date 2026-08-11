# CareNavigator PH Architecture and Pre-Build Record

Date: 2026-08-09 (Asia/Manila)

Status: implementation proceeded after the intended live Supabase project was verified. This document records the required pre-build interpretation and the contract used by the completed foundation.

## Inputs and governing constraints

The build uses the attached master prompt, `SYSTEM_ARCHITECTURE.md`, `VISUAL_REFERENCE.md`, the attached reference image, `SKILL.md`, and `SKILL(3).md`. `DESIGN_REQUIREMENTS.md`, `SUPABASE_SAFETY.md`, and a workspace `VISUAL_REFERENCE.png` were not present; the master prompt and attached image supplied those requirements.

The system is a fresh Flutter implementation. Screens never own raw Supabase calls. Riverpod exposes view-ready state; typed repositories map Supabase contracts; RLS and server-side authorization are authoritative. The client contains only public Supabase configuration. Super administrators do not automatically gain clinical access.

## Implemented structure

```text
lib/
  main.dart, bootstrap.dart
  src/
    app/                    application root
    config/                 public compile-time configuration
    models/                 typed auth, hospital, assessment, and intake contracts
    providers/              identity, directories, assessment, workspace streams
    repositories/           auth, hospital, assessment, consultation, care, profile, admin, workspace
    routing/                 GoRouter and root-overlay architecture
    theme/                   semantic color, spacing, radius, elevation, typography tokens
    widgets/                 shells, navigation, panels, feedback, dialogs
    features/
      public/ auth/ assessment/ guest_consultation/ workspaces/
supabase/migrations/         focused live migrations
test/                        unit, repository, route, widget, accessibility, overlay, golden tests
tool/                        credential-free Supabase MCP helper
```

## Route and role inventory

Public routes cover `/`, `/hospitals`, `/hospitals/map`, `/hospitals/:hospitalId`, `/doctors`, assessment question/result routes, guest consultation request/verification/confirmation, and sign-in/register/OTP/recovery/reset/account-state routes.

Protected roots are `/patient`, `/doctor`, `/hospital-admin`, and `/super-admin`. Each has concrete dashboard and section routes for the role inventory below; list resources accept exact-ID detail paths, message paths use exact conversation IDs, and `/doctor/labs` resolves to the laboratory workflow.

| Role | Implemented task focus |
| --- | --- |
| Guest | Verified care discovery, emergency screening, preliminary assessment, guest intake and email verification |
| Patient | Booking, rescheduling, cancellation, consultations/Jitsi, Realtime messages/notifications, records, prescriptions, labs, private files, profile/preferences |
| Doctor | Assigned relationships, schedule publication, appointment lifecycle, structured documentation, diagnosis/treatment plan, prescriptions, lab requests/review, messaging/Jitsi |
| Hospital administrator | Assigned-hospital appointments, staff provisioning/status, services, departments, facility/capacity/room/ER state, reports, audit |
| Super administrator | Hospital approval, accounts, permissions, settings, analytics, security, maintenance, audit |

## Repository, provider, and model map

- `AuthRepository`: live sessions, identity/profile/role/account status, password/OTP/recovery flows.
- `HospitalRepository`: verified public directory, batched department/service/ER/doctor/schedule mapping, search and public availability.
- `AssessmentRepository`: anonymous session, deterministic emergency gate, AI Edge Function invocation, exact stored result.
- `ConsultationRepository`: guest verification/intake, registered-patient booking, rescheduling/lifecycle RPC, guest review, Jitsi room access.
- `CareRepository`: Realtime messages/notifications, signed clinical downloads, private upload, medical-result AI/review, doctor schedules, prescriptions and laboratory requests.
- `ProfileRepository`: RLS-scoped user/patient/doctor fields and notification preferences.
- `AdminRepository`: audited hospital decisions, privileged accounts/staff, services/departments, operations, permissions/settings, maintenance.
- `WorkspaceRepository`: role/section contract map and view-ready RLS-scoped snapshots/analytics.

Riverpod providers expose configuration, Supabase/repositories, auth identity, live hospital/clinician directories, assessment/intake state, profile/workspace futures, and Realtime message/notification streams. Domain models preserve exact IDs and carry only records returned by the connected data source.

## Live Supabase contract inventory

MCP verified the intended CareNavigator project before implementation:

- 49 public tables with RLS enabled, including identity/roles, hospitals and classifications, clinicians/schedules/assignments, consultations and guest requests, messages/notifications, records/documents, prescriptions/laboratory data, operations, governance, security, analytics inputs, and audit data.
- Primary/foreign keys, data types, nullability, defaults, enum/check constraints, indexes, relationships, and nested-select relationships were inspected for every mapped workflow.
- Realtime publication includes 19 tables used for care, operational, message, and notification updates.
- Private Storage policies constrain clinical and identity files; client downloads use short signed URLs and clinical-access logging.
- Active Edge Functions: `analyze-symptoms`, `admin-users`, `care-workflows`, `analyze-medical-result`, and `dispatch-notifications`.
- Verified RPCs include booking and consultation transitions, guest review, video-room creation, chat send/read, notification read, clinical access, medical-result confirmation, analytics, and hospital application review.
- Cron plus pg_net dispatch scheduled notifications. Groq and SMTP/service credentials remain server-side.

Two focused migrations were added. `20260809170000_hospital_verification_decisions.sql` adds hospital decision metadata and an authorization-checked `review_hospital_application` RPC with explicit audit context. `20260809173000_harden_hospital_verification_rpc.sql` removes Supabase's retained explicit anonymous execution grant. Both were applied and re-read through MCP. No visual preference caused a schema change, and no Edge Function deployment was required.

## Environment inventory

Flutter public configuration: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, optional `APP_BASE_URL`.

Developer/deployment-only configuration: `SUPABASE_PROJECT_NAME`, `SUPABASE_PROJECT_ID`, `SUPABASE_ACCESS_TOKEN`, and `SUPABASE_DB_PASSWORD`.

Supabase secret storage: `GROQ_API_KEY`, Groq model names, `SUPABASE_SERVICE_ROLE_KEY`, `ADMIN_BOOTSTRAP_TOKEN`, `NOTIFICATION_DISPATCH_TOKEN`, SMTP host/port/username/password, and notification sender. Values are never documented, logged, committed, or compiled into Flutter.

## Design and component system

The visual system uses cool white/slate surfaces, deep clinical navy/teal actions, restrained information cyan/mint, semantic green/amber/red, thin borders, minimal elevation, controlled 6–16 px radii, readable typography, and content-driven density. Emergency red is reserved for emergency/destructive states.

Shared Flutter-native components cover page headers, navigation shells, content panels, flat data rows, metric tiles, badges/status tags, form controls, alerts, loading/empty/error states, root dialogs/sheets/menus, and responsive layouts. shadcn/ui composition principles informed the hierarchy; the React package was not introduced because this is Flutter.

## Responsive, overlay, and accessibility strategy

Phone layouts use compact app bars, bottom navigation plus a More sheet, safe areas, keyboard avoidance, stacked page actions, and touch-first controls. Tablet/desktop layouts use one scrollable sidebar, compact utility actions, structured rows/tables, controlled widths, and reflow at content-driven breakpoints.

Blocking dialogs, confirmations, filters, sheets, workspace search, menus, and feedback use the root navigator/overlay helpers, application scrim, safe-area constraints, focus request/restoration, Escape handling, and duplicate-submit blocking.

Accessibility includes semantic headings/live regions, logical focus/tab order, keyboard submission and shortcuts, visible focus, WCAG contrast, 48 px Android targets, text scaling/browser zoom reflow, non-color status labels, dialog semantics, accessible progress, and reduced decorative motion.

## Test, deployment, and verification strategy

The suite covers units, validation before network calls, role routing/guards, exact-ID actions, overlay/focus behavior, mobile/desktop reflow, 200% text scaling, accessibility guidelines, and 22 deterministic goldens. Release web and Android debug builds use only real public configuration. The anonymous live contract test runs separately. Final MCP checks re-list migrations/functions and re-run security/performance advisors.

Deployment reuses the existing Supabase project and environment. Only the two focused migrations were deployed. Web hosting publication and app-store release were not requested.
