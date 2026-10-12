# CareNavigator backend installation and upgrades

The first active migration is a sanitized application baseline: 64 tables, 175 functions and 189 policies. Later active migrations add verified corrections, including the video participant NULL guard. The baseline contains no patient, Auth-user, Vault or SMTP data. Reference seeds and storage bucket definitions are separate. Supabase must supply its managed Auth and Storage schemas before applying the application baseline.

## New isolated Supabase project

1. Create an empty project or start the Supabase local stack. Inspect the CLI commands with `supabase --help`, `supabase db --help`, and the selected command's `--help`.
2. Apply the active `migrations` files once in version order, then `baseline/reference_seed.sql` and `baseline/storage_seed.sql`. A local reset uses the seed paths in `config.toml`.
3. Enable Realtime for the application tables used by live subscriptions, including notifications and messages. Check each subscription against its RLS policy.
4. Configure Auth's actual application Site URL and exact `/reset-password` redirect URL. The client accepts recovery events and expired links. Configure Android application links separately if distributing mobile recovery links. An empty `APP_BASE_URL` on mobile uses the configured Auth Site URL.
5. Deploy all six function folders, retaining each `verify_jwt` setting in `config.toml`. The three functions without gateway JWT validation establish their own user/dispatcher authorization where required. Use only Supabase server secrets for credentials.
6. Set up the five-minute dispatcher from the configuration described below. Run all SQL acceptance suites and the Flutter/browser integration tests using synthetic, verified identities.

Do not seed synthetic hospital or account data into a live project. `tests/local_fixture_seed.sql` deliberately refuses a nonempty hospital directory.

## Existing deployment

The historical SQL chain is archived in `archive/historical-migrations`. It starts after the missing base schema and includes duplicate versions `20260823190000`, `20260823250000`, and `20260823320000`. It is retained for investigation, not replay.

The ten audited corrections live in `upgrades/audit-2026-10`, in numeric order. Apply them only after comparing the target's actual schema and checking which corrections already exist. Their filenames identify the reviewed upgrade sequence; the MCP deployment originally recorded its own unique timestamp versions. `baseline/deployment_reconciliation.json` preserves those versions, names and statement hashes.

The CareNavigator project was compared with `baseline/catalog.json` before its migration metadata was reconciled to the baseline. No baseline DDL was replayed and no application rows were removed. The original complete ledger backup is ignored local runtime data. Future schema changes belong in new unique active migrations, generated with `supabase migration new <name>`. The expected catalog is advanced alongside later migrations; applied baseline SQL remains unchanged.

The audit correction in `migrations/20261012005203_preserve_audit_during_hospital_delete.sql` is deployed. Hospital deletion now cascades through audited capacity records without a foreign-key error, while `source_hospital_id` remains in the audit metadata. The expected catalog advances only the two audit function definitions; function privileges and the original baseline SQL remain unchanged. See `baseline/audit_fix_deployment.json` for deployment/source hashes and `tests/hospital_cascade_audit_acceptance.sql` for the regression.

From the workspace root, install verifier dependencies with `npm ci --prefix tool`, then run `node tool/export_schema_baseline.mjs --check` for a read-only catalog comparison. `tool/reconcile_baseline.mjs` saves a manifest by default. Its `--record` option changes migration metadata only after an exact catalog match and retains the complete prior ledger in ignored runtime storage. Do not use it for a deployment that has legitimate extra or different schema objects; reconcile the differences first.

## Configuration

Client builds receive only `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` and `APP_BASE_URL`. Never pass the full server `env` to a Flutter build. Use a JSON file containing only those public values.

Required server configuration:

| Secret | Purpose |
| --- | --- |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Platform-provided server/client access |
| `GROQ_API_KEY`, `GROQ_MODEL`, `GROQ_VISION_MODEL` | AI provider and validated text/vision models |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `NOTIFICATION_FROM_EMAIL` | SMTP delivery; fresh password required |
| `SMTP_TEST_RECIPIENT` | Single controlled destination for super-admin test email |
| `NOTIFICATION_DISPATCH_TOKEN` | Private five-minute dispatcher authorization |
| `APP_BASE_URL` | Published application URL for notification links |
| `ADMIN_BOOTSTRAP_TOKEN` | Restricted administrative bootstrap, if used |

The exposed Gmail app password must be revoked by its Google-account owner. A replacement must be configured in server secrets after revocation. The compromised Edge SMTP secret was removed, so delivery stays disabled until replacement. Supabase Auth has its own SMTP settings; rotate those too if they use the same exposed password.

The existing dispatcher is invoked every five minutes with its private token. Daily medication summaries are eligible after **08:00 Asia/Manila**, once per patient/local date. Store scheduler credentials in Vault or the scheduler's secret store, never SQL literals committed to source. Inspect the existing job before changing its schedule or credentials. New installations must configure the same invocation against `/functions/v1/dispatch-notifications`; include the `x-dispatch-token` header. The scheduler is deployment configuration, not a database seed containing a secret.

## Verification

`CNPH_TEST_DATABASE_URL` selects an isolated database for `node tool/database_acceptance.mjs`. Every acceptance suite rolls back. The standalone PostgreSQL platform stub under `tests/platform_stub.sql` supports application-schema tests only; it does not reproduce the Auth/Storage/Realtime servers or replace a full Supabase installation test.

Live tests use verified synthetic identities. `tool/repair_live_tests.mjs` reads credentials from ignored runtime fixtures and supplies the existing `CNPH_TEST_*` variables, executing the complete Flutter suite without live-test skips. Browser tests use a separate context per role and the release server (`python tool/serve_release.py`). Playwright must never attach to an existing personal browser profile.

The full empty cloud-project installation and actual staging-copy upgrade remain release gates when project capacity is available. Local clean-schema and reconstructed upgrade tests passed; they are limited evidence and must not be reported as those cloud tests.

Online video appointments use a **Google Meet link supplied by the assigned doctor**, as selected on 12 October 2026. Hospital confirmation still reserves the slot. `set_consultation_meet_link` accepts only canonical HTTPS `meet.google.com` meeting links, records the supplying doctor and notifies the patient without including the link in notification data. Saving/replacing is allowed after confirmation and before the appointment window ends. Registered patients and verified approved guests retrieve the link only from 15 minutes before through four hours after the appointment. Terminal outcomes, expired windows and stale doctor assignments deny access. Raw client access to `video_sessions` is revoked.

The compatibility `ensure_video_session` RPC verifies an existing link; it no longer creates provider rooms. No Jitsi service, app ID, signing secret or OAuth integration is needed. Existing appointments are preserved; open legacy Jitsi rooms require the assigned doctor to set a Google Meet link. The retired token module is kept under `archive/retired-jitsi`, and the unexecuted infrastructure bundle is historical reference.

Playwright tests verify the app's actual external navigation through a controlled Google Meet destination. They do not claim a real Google Meet call or successful provider admission/media. The doctor creates and hosts the meeting in Google Meet, which controls admission and call termination. CareNavigator controls display/retrieval of the link and its clinical workflow; it cannot invalidate a Google meeting link already copied outside the app. See the [Google Meet creation guide](https://support.google.com/meet/answer/9302870) and [host controls](https://support.google.com/a/users/answer/11989526).

The repair verification's synthetic identities and open appointments are retired after testing. Recreate isolated, verified test actors before rerunning the live/browser suite. Do not substitute existing patient or staff accounts or reactivate fixtures without checking their saved identity scope. The final evidence and open release gates are recorded in `docs/REPAIR_STATUS_2026-10-12.md`.
