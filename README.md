# CareNavigator PH

CareNavigator PH is a Flutter mobile/web healthcare-navigation platform backed by Supabase. Guests can find verified care, receive preliminary AI guidance, and request a first consultation. Patients and doctors use role-protected care workflows, while hospital and platform administrators manage operations without receiving unrestricted access to clinical records.

## Implemented modules

- Public hospital directory, classification/search filters, live ER/bed/room/facility availability, departments, services, doctors, schedules, operating hours, announcements, contacts, distance ranking, and external directions
- Structured Groq symptom assessment with deterministic emergency escalation and hospital recommendations; AI output is explicitly preliminary
- Email-OTP guest consultation intake, private ID upload, location/department/schedule capture, reference generation, AI pre-assessment, review, temporary patient creation, duplicate review, and compensated official-account conversion
- Patient booking against published doctor slots, consultation status history, follow-ups, Jitsi video rooms, secure chat, attachment sharing, read receipts, and Realtime updates
- Doctor patient management, consultation notes/summaries, diagnoses, treatment plans, prescriptions, laboratory requests, private medical documents, and consultation attachments
- Medical-result upload, image/text extraction, Groq analysis, processing-job tracking, doctor modify/confirm/reject controls, official-record synchronization, and patient notification
- Patient medical history, confirmed diagnoses, treatment plans, results, prescriptions, authorized signed-file access, selected profile edits, and versioned consent grant/revoke history
- Hospital-admin profile, department, flexible service-offering CRUD, service-to-doctor assignment, room/bed/ER/facility availability, doctor accounts/status/schedules, announcements, operational patient/appointment monitoring, analytics, and hospital audit logs
- Super-admin hospital approval, hospital-admin accounts, service categories, global announcements, platform analytics, settings, AI configuration, role permissions, maintenance windows, audit review, and security-log review
- In-app notifications plus a Gmail SMTP outbox for opt-in email delivery, deduplication, bounded retry/backoff, and appointment reminders
- Row Level Security, private storage, short-lived signed URLs, active-account enforcement, clinical-integrity triggers, audit/security logging, scoped analytics, and Realtime publication

## Local setup

1. Install Flutter 3.44 or later.
2. Copy `.env.example` to `.env` and set the local values. `.env` is ignored and must not be committed.
3. Run the app from PowerShell:

   ```powershell
   .\tool\run.ps1 -d chrome
   ```

Only the Supabase URL and publishable client key are available to Flutter. They
also live in `assets/config/public.env` so a plain `flutter run` works; explicit
`--dart-define` values take precedence for other environments. The Groq key,
Supabase Management API token/database password, bootstrap token, scheduler
token, and provider secrets remain server-side and must never be added to that
asset or supplied through `--dart-define`.

## Supabase deployment

The linked project reference is declared in `supabase/config.toml`. Apply the timestamped files in `supabase/migrations` in order, then deploy the functions in `supabase/functions` with their existing JWT settings:

- `admin-users`: administrative account provisioning and status changes
- `analyze-symptoms`: JWT-protected structured Groq assessment, including constrained anonymous guest sessions
- `care-workflows`: guest-to-patient account conversion
- `analyze-medical-result`: doctor-only result analysis and processing jobs
- `dispatch-notifications`: scheduler-token-protected reminder/outbox dispatch

Required Edge Function secrets are `GROQ_API_KEY`, `ADMIN_BOOTSTRAP_TOKEN`, and `NOTIFICATION_DISPATCH_TOKEN`. `GROQ_MODEL` and `GROQ_VISION_MODEL` are optional model overrides. Email delivery additionally uses `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `NOTIFICATION_FROM_EMAIL`, and optional `APP_BASE_URL`. External email is opt-in and defaults off.

To enable the Gmail sender, create a Google app password, put the SMTP values from `.env.example` in the ignored local `.env`, and run:

```powershell
.\tool\configure-gmail.ps1
```

The script provisions the Edge Function secrets, connects Supabase Auth to Gmail SMTP, disables phone authentication, and changes the guest verification email to a six-digit code. Use a dedicated mailbox app password, not the mailbox's normal Google password.

Migration `20260716205000_automated_notification_dispatch.sql` installs Supabase Cron and `pg_net`, then schedules `dispatch-notifications` every five minutes. Provision the same `NOTIFICATION_DISPATCH_TOKEN` as an Edge Function secret and as a Vault secret named `carenavigator_notification_dispatch_token`. The job safely does nothing until that Vault secret exists. Each run creates due appointment reminders before claiming the delivery outbox. Keep this token in secret storage, never in Flutter or source control.

## First super administrator

The live project starts with no application users. Create the first Super Admin once from a trusted terminal:

```powershell
.\tool\bootstrap-super-admin.ps1 `
  -Email "admin@example.com" `
  -Password "a-strong-temporary-password" `
  -FirstName "CareNavigator" `
  -LastName "Administrator"
```

The endpoint refuses further bootstrap requests after the first Super Admin exists. After success, rotate or remove `ADMIN_BOOTSTRAP_TOKEN` from both the Supabase Function secrets and local `.env`.

Super Admins create and approve hospitals and hospital administrators from `/admin`. Hospital administrators then manage their assigned hospital only. They cannot change hospital approval fields through the UI or database API.

## External-service activation

- First-time consultation access uses a six-digit Supabase email OTP. Configure the Magic Link email template to display `{{ .Token }}` and configure custom SMTP for production delivery.
- Guest symptom assessment uses Supabase anonymous authentication so the Groq function remains JWT-protected. Keep anonymous-user rate limits enabled; production deployments should also configure Auth CAPTCHA/Turnstile protection.
- Gmail SMTP is the only external notification sender. Supabase Auth and the notification dispatcher share the same server-side SMTP account.
- Online consultations use Jitsi room URLs generated by the backend.
- Directions open Google Maps; no map-provider secret is embedded in Flutter.
- JPEG/PNG medical results can be interpreted by the configured Groq vision model. PDF analysis requires reviewed extracted/OCR text; doctors remain responsible for checking all extracted values.

## Verification

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release `
  --dart-define=NEXT_PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co `
  --dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
flutter build apk --debug `
  --dart-define=NEXT_PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co `
  --dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

The SQL regression scripts in `supabase/tests` are transaction-wrapped and roll back their synthetic data. Run them only against the intended project after confirming the project URL.

## Medical safety and privacy

AI output may suggest possible conditions, urgency, departments, and healthcare actions, but it cannot create an official diagnosis. A licensed doctor must review and confirm clinical findings before they enter the permanent record. Life-threatening warning signs direct users to call 911 and seek the nearest available emergency department instead of waiting for online approval.

Patients can access only their own information; doctors are limited to assigned/consultation patients; hospital administrators are limited to their hospital and operational fields; super administrators do not automatically receive clinical-record access. Private files are accessed through short-lived signed URLs.
