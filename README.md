# CareNavigator PH

CareNavigator PH is a greenfield Flutter application for mobile and web. It combines public hospital and clinician discovery, deterministic emergency triage, guest consultation intake, authenticated patient and doctor care, hospital operations, and platform governance in one role-aware product.

## Architecture

- Flutter with adaptive mobile, tablet, and desktop shells
- GoRouter for deep links, redirects, account-state handling, and role guards
- Riverpod for identity, view state, asynchronous data, and Realtime streams
- Typed Dart repositories as the only Supabase boundary
- Supabase Auth, PostgreSQL with RLS, Realtime, private Storage, RPCs, Edge Functions, triggers, Cron, and pg_net
- Groq preliminary analysis behind doctor-review states, opt-in Gmail SMTP notifications, approved Jitsi rooms, and external Google Maps directions
- Central clinical design tokens plus shared Flutter-native Card, Alert, Badge, Table/List, Dialog, Sheet, loading, empty, and error compositions

The component composition follows the clear, restrained patterns associated with shadcn/ui, translated into the required native Flutter system. React shadcn/ui is deliberately not installed.

## Live data behavior

With valid public Supabase configuration, public directories and authenticated workspaces use the live CareNavigator project. Public queries explicitly constrain verified, operating hospitals and published clinician schedules. Signed-in identities receive RLS-scoped data and connected actions for booking/rescheduling/cancellation, messaging, notifications, private files, clinical documentation, prescriptions, laboratory workflows, schedules, hospital operations, staff provisioning, governance, and maintenance.

Without public configuration, data-backed screens show explicit loading, empty, or unavailable states. The app does not substitute identities, facilities, schedules, clinical records, metrics, or mutations that were not returned by the backend.

## Public configuration

Only public client values may be compiled into Flutter:

```powershell
flutter run `
  --dart-define=NEXT_PUBLIC_SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=PUBLIC_KEY
```

`APP_BASE_URL` is optional. Public operational values such as the emergency number and region are loaded from RLS-readable `system_settings` rows. Never pass the root `env` file through `--dart-define-from-file`: it also contains deployment and server-only variables. Supabase access/database credentials, service-role keys, Groq keys, SMTP credentials, bootstrap tokens, and scheduler tokens must remain outside Flutter.

## Supabase

The intended live project is configured through the local Supabase MCP helper at `tool/supabase_mcp_call.ps1`. It reads `SUPABASE_ACCESS_TOKEN` from the environment and does not embed credentials.

The live contract was inspected before schema-dependent work. It includes 49 RLS-enabled public tables, private clinical Storage, Realtime publication for 19 tables, the five required active Edge Functions, clinical/operational RPCs, audit and security triggers, and scheduled notification dispatch. Two focused migrations add auditable hospital verification decisions and remove anonymous execution from that privileged RPC:

```text
supabase/migrations/20260809170000_hospital_verification_decisions.sql
supabase/migrations/20260809173000_harden_hospital_verification_rpc.sql
```

See [PRE_BUILD_REPORT.md](PRE_BUILD_REPORT.md) for the architecture/data inventory and [VERIFICATION_REPORT.md](VERIFICATION_REPORT.md) for evidence and limitations.

## Verification

```powershell
flutter analyze
flutter test
flutter build web --release `
  --dart-define=NEXT_PUBLIC_SUPABASE_URL=... `
  --dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=...
flutter build apk --debug `
  --dart-define=NEXT_PUBLIC_SUPABASE_URL=... `
  --dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=...
```

On Windows, use the helper to load only the public Supabase values from `env`:

```powershell
.\tool\run_care_navigator.ps1              # Edge (default)
.\tool\run_care_navigator.ps1 -Target windows
```

The live anonymous contract test intentionally skips in the ordinary suite and is run separately with task-specific test environment variables. UI tests cover production unavailable states and emergency-safe behavior; live seeded-account workflows require a configured test project.

Browser-engine verification remains unavailable on this workstation because the in-app browser reported no connected browser. iOS was not built on Windows. These limitations are stated explicitly in the verification report.
