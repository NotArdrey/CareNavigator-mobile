# CareNavigator PH health check

Checked on 11 October 2026, Asia/Manila, against the current working tree and live Supabase project `crhsbpkuteyqbxjpozrp`.

**Result: the application compiles and the database is online, but the project does not have a clean verification pass. Several features, credentials, and documentation need attention.**

## Verified results

| Check | Result | Evidence |
| --- | --- | --- |
| Flutter static analysis | PASS | `flutter analyze`: no issues |
| Ordinary Flutter suite | FAIL | 244 passed, 8 screenshot failures, 11 live tests skipped |
| Main visual tests, isolated rerun | FAIL | Same 8 failures; 8 visual tests passed |
| Submission screenshot tests | FAIL | All 4 CRUD screenshot comparisons differ from their baselines |
| Web release build using public values from `env` | PASS | `build/web`; compilation completed in 41 seconds |
| Android debug build using public values from `env` | PASS | `build/app/outputs/flutter-apk/app-debug.apk`; approximately 188 MiB |
| Built web HTTP smoke check | PASS | Local server returned HTTP 200 and Flutter bootstrap markup |
| Supabase database through MCP | PASS | Live schema, policies, constraints, indexes, functions, migrations, logs, and storage metadata retrieved |
| Public directory | PASS with contract issue | 7 published hospitals load; all 7 image URLs return HTTP 200 |
| Public settings | PASS | Anonymous query returns 5 settings |
| Database protection | PASS for tested boundaries | All 61 public tables have RLS enabled; unauthenticated clinical/user/message/audit reads were rejected; preferences returned zero rows |
| Deployed Edge Functions | PRESENT | All 6 functions are ACTIVE; all locally declared chat action names appear in deployed source |
| Notification cron | PASS for scheduling | Active every five minutes; 288 successful SQL job runs in the preceding 24 hours |
| SMTP configuration in `env` | PASS for authentication | TLS connection, greeting, EHLO, and authentication succeeded; no email sent |
| Groq configuration in `env` | PARTIAL | API key and text model work for model discovery; configured vision model is absent from the provider's current model list |
| Authenticated live tests | BLOCKED by stored credentials | 15 saved demo role logins and 4 workspace login prerequisites failed; another 4 stored UI audit accounts also failed |
| ERD against live column inventory | FAIL | All 37 diagrammed entities exist; 14 listed column names do not |

The 244 successful ordinary tests include 8 successful visual tests. The other 236 tests cover application behavior. The configured live run had 20 failures: 19 authentication prerequisite failures and 1 public image contract failure. Those authentication failures prevented the workspace read tests from reaching their database queries; they do not establish that ordinary user sign-in is broken.

## Findings and repair priorities

### 1. A working SMTP credential is hardcoded in tracked and deployed source

`supabase/functions/care-navigator-chat/index.ts` has literal SMTP password fallbacks at lines 1716, 2049, and 2172. The deployed function also contains a literal fallback. The password in `env` matches the literal, and authenticated successfully with the SMTP server during this check.

Remove those fallbacks, rotate the exposed SMTP app password, store the replacement as a server secret, and deploy the corrected function. The credential value is deliberately excluded from this report. Email delivery itself was not tested.

### 2. Assistant conversation history expects a missing table

`SupabaseCareAssistantHistoryRepository` reads, saves, and deletes rows in `public.care_assistant_conversations`. The live table is absent. A direct API query returned HTTP 404 / `PGRST205`.

The corresponding local migration is `supabase/migrations/20260825223000_persist_care_assistant_conversations.sql`. Verify and apply this migration in the intended environment, then exercise history loading, saving, pinning, renaming, and deleting with a dedicated account.

### 3. Daily medication reminder preferences cannot persist independently

The live `notification_preferences` table has no `medication_reminders` column. A direct column query returned HTTP 400 / `42703`. The corresponding local migration is `supabase/migrations/20260826080000_medication_intake_reminders.sql`.

There is also an application issue: the profile UI passes `medicationReminders` into `NotificationPreferenceUpdate`, but `NotificationPreferenceUpdate.toJson()` omits it (`lib/src/repositories/profile_repository.dart:152`). Loading falls back to the prescriptions preference when the database value is absent. Applying the migration alone will not make the separate toggle persist; its serialization also needs correction.

### 4. Deployed vision model handling differs from the local fix

`env` configures `GROQ_VISION_MODEL=qwen/qwen3.6-27b`, which is absent from the authenticated Groq model list. Local source recognizes that model as retired and substitutes `qwen/qwen3.8-27b`; the substitute is available.

The deployed `care-navigator-chat` function still defaults to `qwen/qwen3.6-27b` and lacks the local retirement handling for it. Local and deployed source hashes differ. This is a confirmed deployment/configuration mismatch relevant to image and document scanning. Update the server model configuration and deploy the current fallback handling, then test extraction through an authenticated session. This audit did not execute a clinical extraction request or inspect deployed secret values.

### 5. Stored test credentials and the `env` management token are stale

The saved credentials in `.codex-runtime/demo-account-credentials.json` and `.codex-runtime/ui-audit-state.json` were rejected. The database still contains 26 auth accounts with `@demo.test` addresses, but the saved passwords did not establish sessions. Dedicated working test credentials are needed for patient, doctor, hospital administrator, and super administrator verification.

`SUPABASE_ACCESS_TOKEN` in `env` returned `Invalid access token`. An existing user-level token on this computer succeeded against the intended project, allowing the MCP inspection. The public Supabase URL and publishable key in `env` worked. A separate direct PostgreSQL attempt stopped at `SELF_SIGNED_CERT_IN_CHAIN`; therefore the database password in `env` was not verified. Database access itself was verified through MCP and the application API.

### 6. Visual baselines and the public directory contract fail

Main screenshot failures: guest, patient, doctor, and doctor-prescriptions screens, each at mobile and web sizes. Differences range from 0.36% to 7.07%. The guest mobile comparison shows an altered published-facilities panel layout. Four submission screenshots also differ by 26.08% to 47.63%.

Review the current renderings and intended design before updating baselines. No baseline images were regenerated.

The anonymous repository contract test reaches live data but fails because `CareNavigator Regional Hospital (Demo)` uses a `placehold.co` image instead of a managed directory image. Its URL responds, so this is a data/contract failure rather than an unreachable image. Review whether this synthetic facility should be published and replace its image as appropriate.

### 7. The open ERD has physical column-name mismatches

`docs/defense/database_erd.mmd` lists these names that are absent from their live tables:

| Diagram field | Live schema |
| --- | --- |
| `roles.name` | `role_name` |
| `role_permissions.permission_key` | `permission` |
| `users.status` | `account_status` |
| `hospital_classifications.name` | `classification_name` |
| `hospitals.name` | `hospital_name` |
| `hospital_departments.name` | `department_name` |
| `hospital_departments.is_active` | Uses `availability_status`; no such Boolean column |
| `healthcare_service_categories.name` | `category_name` |
| `healthcare_service_categories.slug` | No such column |
| `online_consultation_request_status_history.old_status` | `from_status` |
| `online_consultation_request_status_history.new_status` | `to_status` |
| `patient_consents.status` | Uses `is_granted`, `granted_at`, and `revoked_at` |
| `prescriptions.status` | No such column |
| `laboratory_results.review_status` | `verification_status` |

The diagram is intentionally a subset of the database. This check compared entity and column existence; it did not validate every Mermaid cardinality or type annotation.

## Additional database observations

- Inspected 89 public function definitions, 183 public/storage policies, valid constraints, index metadata, 11 storage buckets, and 20 Realtime publication tables. Named RPC references extracted from the repositories exist, including both analytics RPCs. Clinical storage buckets are private; profile and hospital image buckets are public.
- Migration history contains 73 applied migrations. Six local filenames have no matching migration name in that history. However, the department-assignment and patient-search RPCs, 24-hour lead-time helper and three triggers, and cross-source grant loop already exist live. Do not blindly replay all six files based only on migration-name differences. The missing assistant-history table and reminder column are confirmed object-level gaps.
- Anonymous `list_available_consultation_slots` execution succeeds: the probe returned HTTP 200 and 40 slots. The security advisor also flags this grant. Compare it with the intended authenticated-only scheduling boundary in the local migrations.
- Advisors report leaked-password protection disabled, `pg_net` in the public schema, 38 authenticated security-definer function notices, 63 anonymous-sign-in policy notices, and 47 foreign keys without covering indexes. These notices require context; they are not proof of data exposure. Tested anonymous clinical boundaries remained protected. See [password protection guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), [security-definer grants](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), and [foreign-key indexes](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).
- The logs query counted 9 PostgreSQL ERROR entries in the preceding 24 hours. A follow-up classification query returned a backend error, so their causes are unresolved; some may relate to this audit's deliberate failure probes. Successful cron SQL execution does not prove downstream notification delivery.
- The web artifact contains none of the scanned server-only token, password, or API-key values from `env`.

## Verification limits and artifacts

Browser automation inventory returned no browsers, and opening the in-app browser reported `Browser is not available: iab`. The built app received an HTTP smoke check, but a real browser rendering/console pass was unavailable.

Authenticated workspace reads, live CRUD, Realtime delivery, uploads/downloads, AI extraction, Jitsi media, and actual email delivery were not verified end to end. No working dedicated account session was available. Android compiled successfully but was not exercised on a physical device. iOS cannot be built on this Windows host. Windows desktop development also lacks Visual Studio, and the project has no Windows platform directory; Android tooling reports unaccepted licenses despite the successful debug build.

Application source, live schema, deployed functions, account credentials, and screenshot baselines were left unchanged. The audit generated builds, local diagnostic scripts/logs, and screenshots. Sign-in attempts generated normal service logs.

Detailed local evidence is under the gitignored `.codex-runtime/` directory: `health-summary.json`, `health-live.log`, `health-goldens.log`, `health-submission-tests.log`, `health-build-web.log`, `health-build-apk.log`, `health-http.json`, `health-providers.json`, `health-followup.json`, `health-effective-models.json`, `health-erd.json`, and `health-slot-probe.json`. Raw database and deployed-source evidence can contain sensitive configuration and should remain local.
