# CRUD and fetching verification

Executed on **12 October 2026, Asia/Manila**, against this workspace's fresh Flutter release web build and the Supabase project configured in ignored `env`.

**Result: the hospital cascade/audit defect is fixed and deployed. All eleven live database acceptance suites pass.** The hospital browser case was rerun with an audited bed still attached: deletion succeeds, the bed is removed, and its audit entry preserves the original hospital ID. The earlier 30 browser cases and 281 Flutter tests remain the baseline for the unchanged Flutter client.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| Flutter static analysis | PASS, no issues | `.codex-runtime/e2e-analyze.log` |
| Full Flutter suite, including live repositories and goldens | 281 passed, zero skipped | `.codex-runtime/e2e-flutter.log` |
| Existing auth, clinical, document review and Meet browser cases | 12 passed | `.codex-runtime/repair-browser/playwright-results.json` |
| Added CRUD, staff and fetching browser cases | 18 passed | `.codex-runtime/e2e/final-summary.json` |
| Deployed database acceptance | 11 passed, zero failed; all rolled back | `.codex-runtime/e2e-database.log` |
| Deployed hospital cascade correction | PASS; migration recorded and function privileges preserved | `supabase/baseline/audit_fix_deployment.json` |
| Hospital deletion through the browser with attached capacity | PASS; HTTP 200, child removed and original audit provenance retained | `.codex-runtime/e2e-hospital-cascade-browser.log` |
| Audit correction with all acceptance suites | 11 passed; validation DDL and fixtures rolled back | `.codex-runtime/e2e/audit-fix.json` |
| Fresh release web build | PASS | `.codex-runtime/e2e-web-build.log` |
| Current source/build server-secret literal scan | No matches | `tool/check_secret_exposure.mjs` |
| Fixture retirement and cleanup | PASS | `.codex-runtime/e2e/cleanup-verification.json` |

Browser totals aggregate the final successful result for each distinct case across the initial run and targeted reruns. Initial harness failures and their logs remain available; the counts do not imply one uninterrupted 30-case run. After deployment, the hospital case and all eleven live database suites were rerun. No Flutter source changed for this correction, so the full Flutter and other browser suites were not repeated.

## CRUD matrix

Each admin entity case asserts the actual Supabase mutation response, independently reads the saved values, reloads the browser, deletes the synthetic row, and verifies its absence. Capacity checks use a separate closed, pending hospital and restore the synthetic administrator's original assignment.

| Area | Operations verified | Boundary |
| --- | --- | --- |
| Beds and rooms | Create, read, capacity update, reload, delete | Browser and live Supabase |
| Services and departments | Create, read, rename/edit, reload, delete | Browser and live Supabase |
| Facility status | Create, read, capacity update, reload, delete | Browser and live Supabase |
| Emergency capacity | Create, read, update, computed availability, reload, delete | Browser, RPC and live Supabase |
| Hospitals | Create pending/closed hospital, read, edit, reload, delete hospital with an audited bed attached; verify cascade and retained audit | Browser and live Supabase |
| Role permissions | Create unused permission, read, deny, reload, delete | Browser and live Supabase |
| System settings | Create unused key, read, edit, reload, delete | Browser and live Supabase |
| Maintenance | Create, read, edit dates/copy, deactivate, reload, delete | Browser and live Supabase |
| Doctor schedule | Create unused availability, read, unpublish, reload, delete | Browser and live Supabase |
| Doctor staff | Provision doctor, read profile/department, suspend, reject login, reactivate, reload, remove synthetic account | Browser creation; protected API status changes; browser response and screenshot readback |
| Patient supporting file | Binary upload, metadata create/read, signed download byte comparison, rename, reload, delete row and storage object | Storage/REST creation; browser download/rename/delete; database storage absence check |
| Supporting document review | Patient consent/share, scoped doctor approval, immutable original provenance | Browser, RPC and live Supabase |
| Prescriptions | Atomic order issuance through preview, persisted order ID, patient display; rollback/idempotency and attachment boundaries | Browser and transactional acceptance |
| Laboratory requests | Create, read and cancel with retained lifecycle record | Actual Dart repository and live Supabase |
| Assistant history | Create/save, read/reload, rename, pin, denied unrelated-account read, delete | Authenticated REST |
| Profile reminder preference | Toggle, save, reload and restore | Browser and live Supabase |
| Record sharing | Read relationship scope and revoke complete sharing | Browser, RPC and live Supabase |
| Consultation lifecycle and authorization | Booking, confirmation, schedule races/rescheduling, cancellation, checkup completion, guest activation, review boundaries and clinical issuance | Transactional database acceptance and existing live/browser cases |

Clinical orders and completed records use their supported cancellation/revocation states rather than physical deletion. Audit and security screens are read-only.

## Fetching

All **40 authenticated workspace routes** were visited across patient, doctor, hospital administrator and super administrator. Additional tab checks cover scheduling, laboratory review, beds/rooms, services/departments, audit/reports and all system tabs. Each route requires successful real Supabase responses, an authenticated shell and no retry/error state. Public discovery also checks hospital search, empty search results, clearing the search, details, reload and doctor directory fetching.

Network evidence records request method, resource path and status without authentication headers or response bodies. Browser contexts are isolated. Staff suspension/reactivation screenshots were visually checked at `.codex-runtime/e2e/staff-suspended.png` and `.codex-runtime/e2e/staff-active.png`.

## Resolved hospital cascade defect

Before the correction, deleting a hospital containing an audited bed record returned **HTTP 409 / PostgreSQL 23503** (`audit_logs_hospital_id_fkey`). The hospital cascade removed the parent before the child's delete trigger wrote a new audit entry referencing that parent. The deployed correction now allows that cascade while retaining audit provenance.

The regression is `supabase/tests/hospital_cascade_audit_acceptance.sql`. The deployed fix is `supabase/migrations/20261012005203_preserve_audit_during_hospital_delete.sql`, matching the version assigned by Supabase. It preserves the original hospital ID in audit metadata and leaves the foreign-key field null when the parent no longer exists. Both audit trigger functions are corrected, with their existing execution privileges preserved. Deployment and source hashes are recorded in `supabase/baseline/audit_fix_deployment.json`.

All eleven acceptance suites passed against the deployed functions. The browser hospital case also passed with an attached audited bed, verifying the real DELETE response, absence of the parent/child rows and retained audit metadata. Only these two function definitions changed in the expected schema catalog; the immutable baseline SQL, other schema objects and privileges remain intact. The read-only catalog comparison passes.

## Harness corrections and cleanup

The live Flutter runner now books and confirms a fresh synthetic doctor/patient relationship before laboratory testing; retired consultations no longer make that test fail. Browser input replacement now clears empty strings correctly. New tests handle Flutter alert dialogs, actual button labels, tab animation, and the absence of search controls for short lists. Upload paths follow the repository's patient/uploader segments.

An early staff test selected a stale row and suspended the synthetic administrator. That actor was reactivated. Staff status tests now use the exact newly created ID through the protected endpoint and verify the browser's actual fetched record and visual status. No real account was changed.

Temporary entities, the provisioned staff account, and synthetic PDF uploads were removed. All six verification identities are inactive, globally signed out and banned. Synthetic clinical/audit history is retained for provenance. Post-cleanup counts are zero for active test users, open test consultations, active test schedules, eligible test outbox jobs, remaining isolated hospitals and disabled application triggers. The test HTTP server was stopped.

Google Meet tests verify authorization and actual external navigation with an intercepted destination. They do not establish provider admission/media. Email preference/outbox rules were tested; SMTP delivery and delivery of recovery emails were not exercised in this run. Browser tests target desktop Chromium/Brave; Flutter goldens cover existing mobile layouts, but this run did not use a physical mobile device.

## Re-run

From the repository root:

```powershell
node tool/run_e2e.mjs
```

Requires the ignored Supabase `env`, owned synthetic account files under `.codex-runtime`, installed Flutter/Python/`tool/node_modules`, and Brave (or `CNPH_BROWSER_PATH`). The runner activates and later retires the fixtures, builds with only public Supabase values, executes both browser suites, checks history and database contracts, and records every failure. The deployed cascade regression now passes.

To verify the deployed audit correction and rerun transactional validation:

```powershell
node tool/e2e_verify_audit_fix.mjs --all
```
