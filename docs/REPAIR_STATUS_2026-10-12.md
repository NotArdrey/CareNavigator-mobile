# CareNavigator PH repair status

Checked on 12 October 2026, Asia/Manila. **The complete plan is not finished.** Database and Edge Function repairs are deployed to the existing CareNavigator project. Flutter changes are in this workspace, with local web and Android release builds; a published application rollout is not verified.

On 12 October the user selected **doctor-entered Google Meet links** instead of Jitsi. The assigned doctor sets/replaces the link after hospital confirmation. Patients and verified approved guests open it during the existing appointment window. Jitsi hosting and signing secrets are no longer required. The switch is deployed to the database/API and included in the local Flutter release builds.

The later [CRUD/fetching verification](E2E_CRUD_REPORT_2026-10-12.md) expanded coverage to admin entity mutations, patient file rename/deletion, staff provisioning/status and all workspace routes. It found a hospital cascade/audit foreign-key defect, now fixed by deployed migration `20261012005203_preserve_audit_during_hospital_delete.sql`. All eleven live SQL acceptance suites and the focused hospital browser cascade case pass. This correction changes no Flutter source and leaves the broader release gates below unchanged.

## Audit findings

| Finding | Repair and evidence | Status |
| --- | --- | --- |
| 1. Embedded SMTP credential | Removed working-source fallbacks and the compromised Edge secret; public build/source scan has zero matching server-secret literals. The password in ignored `env` still matches historical Git source. | Open: owner must revoke and replace the app password; delivery remains disabled. |
| 2. Public-key email authority | Verified caller identity, patient ownership/active doctor relationship, database recipients/content, configured super-admin test recipient and secret-protected dispatch. Real unauthorized API probes reject public keys, unrelated accounts and recipient overrides. | Repaired and verified. |
| 3. Broken rescheduling trigger | Table-specific trigger branches preserve the 24-hour lead time. Valid rescheduling passes database acceptance. | Repaired and verified. |
| 4. Rejected patient uploads | Patient-owned supporting uploads retain immutable `patient_supplied` provenance; scoped doctor review records its actor, time and decision. Official records reference the original document. Binary upload/download and authorized review pass. | Repaired and verified. |
| 5. Guest activation/video handoff | Verified submitting account activates the approved temporary profile in place, idempotently, without staff password changes. Tracking has activation and Google Meet join/retry actions. Approved guests can join before activation. Hospital confirmation is required for new guest online reservations, even when a doctor is assigned. | Application handoff verified; a real Google Meet call remains unverified. |
| 6. Terminal request inconsistency | Terminal transitions synchronize appointment, room closure, grants, history and notifications. Missed scheduled visits require 30 minutes, a contact attempt and no clinical start; appointment closes as cancelled with its specific outcome reason. | Repaired and verified. |
| 7. Partial prescription issuance | Transactional order issuance validates the full medication batch and uses an idempotency key. Attachment failure/retry is separate from the committed order. | Rollback, duplicate submission and attachment retry verified. |
| 8. Email preferences/content/status | Outbox delivery respects automatic-email and medication preferences, active official prescription dates and PRN directions. Manual summary requests authorize only the requested summary. Delivery status is truthful. | Logic verified; actual SMTP delivery remains unverified. |
| 9. Missing state actions/sharing | Hospital review/information/proposal/confirmation controls, patient response/accept/decline controls, doctor clinical actions and relationship-wide sharing revocation are visible. Supporting uploads can be explicitly shared within an existing consent scope. | Actor, transition and scope checks verified. |
| 10. Stale rescheduled metadata | One transaction updates appointment, online confirmed time, consent/grant validity, room validity and reminder jobs under the shared reservation lock. Schedule edits/deletion and competing confirmations use server guards. | Acceptance and concurrent API races pass. |
| 11. Missing deployed contracts | Conversation history and medication preference are deployed; serialization persists the switch. Five-minute dispatch enqueues summaries after 08:00 Manila once per patient/local date and rechecks preferences. Six deployed sources match versioned source. Controlled AI text/vision extraction passes. | Repaired and verified, excluding delivered email. |
| 12. Inconsistent booking semantics | Versioned booking returns a typed outcome; all new online requests await hospital review without reserving a slot. Active hospital reviewer is required. ER capacity is separate from outpatient/online eligibility. Legacy reservations remain intact. | Repaired and verified. |
| 13. Prescription grouping | Explicit order IDs and attachment references replace time heuristics; missing details show record unavailable. Legacy backfill keeps separate orders when grouping cannot be proven. | Repaired and verified. |
| 14. Unreproducible backend | Sanitized application baseline, reference/storage seeds, all six function folders, configuration and setup instructions are versioned. Historical migrations are archived. Clean PostgreSQL application-schema and reconstructed upgrade proofs pass. | Open: full empty Supabase project and actual staging-copy upgrade have not run. |
| 15. Goldens/ERD | All eight failed screenshots were reviewed before baseline updates; all 16 goldens now pass. Physical ERD comparison checks 38 entities and 269 columns with zero missing names. | Repaired and verified. |

The guest and video checks also uncovered and fixed nullable authorization predicates that could otherwise admit unrelated participants. Explicit false-or-NULL rejection now protects room access and guest hospital review.

## Verification evidence

- Flutter static analysis: no issues. Full Flutter suite: **281 passed, zero skipped**, including 16 goldens and 11 live repository tests. The additional Meet tests cover URL validation, authorized controls and saving against the official consultation ID.
- All ten SQL acceptance suites pass against the live project, a clean local application schema and the reconstructed local upgrade. Every acceptance suite rolls back. The final schema has 64 application tables, 178 functions and 189 policies.
- All six Edge Functions pass Deno checking; the changed `care-workflows` function was checked again after the Meet switch. Deployment source hashes and JWT gateway settings are recorded in `supabase/baseline/function_deployment.json`. The earlier Jitsi cryptographic module/tests are archived and are not part of the active deployment.
- Release web and Android APK builds pass. The APK is `build/app/outputs/flutter-apk/app-release.apk`. Build inputs contain only public client configuration.
- Real API checks cover concurrent confirmation and schedule changes, upload/download bytes, doctor review, extraction fixtures, prescription idempotency/rollback, attachment retry, preferences, history persistence/isolation and room authorization.
- Browser journeys exercised hospital review, patient information response, proposed schedule acceptance, guest tracking/activation, assigned-doctor structured completion, prescription issuance/display, preference persistence, sharing revocation and expired recovery links. Browser checks use isolated contexts and synthetic identities.
- Latest browser suite: **12 passed, zero failed, zero skipped**. Doctor replacement, patient navigation and approved-guest navigation of Google Meet links pass alongside the existing clinical, sharing, preference, role and recovery checks. The earlier Jitsi media attempt failed at its moderator gate; that historical failure is retained and the scenario was retired when the user changed the provider requirement. The new handoff tests do not establish real Google Meet media.
- Recovery tokens were generated through Auth, used once to change only a synthetic account password, then rejected on reuse/expiration. The fixture password was restored. Delivery of the recovery email itself has not been verified.
- Secret scanning found zero current server-secret literal matches in working source and release JavaScript. Historical Git still contains the exposed SMTP credential; removing its current source does not revoke it.

Detailed local test logs and credentials remain under ignored `.codex-runtime`. Google Meet browser tests intercept the destination after verifying the app's actual external navigation; they do not simulate provider admission or media. These results do not establish successful email delivery, a real Google Meet call or a full Supabase platform installation. Google Meet controls admission and ending the external call; CareNavigator cannot revoke a link already copied outside the app.

All six synthetic verification identities are inactive, globally signed out and banned. Their open appointments and guest tracking are cancelled, test schedules are inactive, and eligible test outbox jobs are cancelled. Clearly labelled synthetic clinical history and original document references remain for provenance. Post-cleanup checks found zero active test users, open test appointments, eligible test jobs, active test schedules or disabled booking guards. Aggregate monitoring found zero request/consultation mismatches, confirmed-time mismatches, active terminal grants, duplicate summaries, duplicate patient profiles or missing activation identities. The authorization-failure count includes the deliberately denied security probes; continued monitoring remains required.

## Final workflow states

The later CRUD/fetching matrix adds live create/read/update/delete coverage for admin entities and patient supporting files, plus staff provisioning/status and all workspace routes. Its aggregate evidence contains 30 passing browser cases, with the hospital cascade case repeated after deploying the audit correction. Creation/status boundaries that use direct authenticated API calls are identified explicitly in that report. These results cover the documented matrix; provider media/email and the other release gates below still require their own evidence.

| State | Authorized next action | Result |
| --- | --- | --- |
| `submitted` / `under_review` | Active reviewer for the request hospital starts review, requests information, proposes a schedule, confirms or rejects. Patient can cancel. | Review states do not reserve a new online slot. |
| `more_information_required` | Owning patient responds; hospital reviewer can continue review or reject. | Patient response returns to hospital review. |
| `schedule_proposed` | Owning patient accepts or declines; hospital reviewer can revise/reject. | Acceptance rechecks availability and confirms atomically; decline returns to review. |
| `confirmed` / `awaiting_contact` | Assigned doctor or authorized hospital staff records contact; assigned doctor sets the Google Meet link and starts care. Patient can cancel or reschedule within server rules. | Confirmed reservation, meeting access and clinical access share the same time. |
| `video_ready` | Authorized patient/approved guest and assigned doctor open Google Meet within the existing window; assigned doctor starts clinical care. | Early/expired access and links from a previous doctor assignment are rejected; a missing link has a visible retry action. |
| `in_progress` | Assigned active doctor completes the existing structured checkup or records a face-to-face recommendation. | Completion requires structured diagnosis, treatment, summary and clinical evidence. |
| `no_show` / scheduled `patient_unreachable` | Authorized staff records the missed outcome after the server timing/contact checks. | Consultation cancelled, specific reason retained, room closed and access revoked. |
| `completed` / `cancelled` / `rejected` | Patient/staff can inspect history and notification status; patient can make a new booking where offered. | Terminal clinical/reservation state; no active consultation grants remain. |
| `face_to_face_recommended` | Patient chooses Make a new booking. | Existing consultation closes; another reservation is not created automatically. |
| Approved guest, activation pending | Verified original submitting account activates itself and optionally sets its own password; identity conflict shows a resolution action while tracking remains accessible. | Same patient and clinical provenance retained; repeated activation is harmless. |
| Supporting upload unreviewed | Patient shares within an active consent relationship; scoped doctor approves/rejects the original. | Immutable patient authorship; preliminary extraction alone never creates medication orders. |
| Order saved, attachment failed | Issuing doctor retries attachment against the existing order. | Clinical order is retained once; attachment failure is reported separately. |
| Email queued / failed | Authorized retry reuses the existing job and rechecks applicable preferences. | No duplicate clinical record; sent status requires provider success. |
| Expired recovery link/session | User requests a new recovery link or signs in again. | Explicit recovery screen and protected-route handling. |

## Review of the eight golden differences

| Screenshot | Reviewed change |
| --- | --- |
| Guest mobile | Assistant launcher and directory empty-state layout; See all action stacks within the available width. |
| Guest web | Assistant launcher and directory/hero content width. |
| Patient mobile | Directory spacing and See all layout at the mobile width. |
| Patient web | Sidebar and directory content width. |
| Doctor mobile | Text and workspace spacing changes. |
| Doctor web | Sidebar/navigation and main workspace width. |
| Doctor prescriptions mobile | Explicit View details action and prescription row layout. |
| Doctor prescriptions web | Explicit View details action and prescription row layout. |

The contact sheet was inspected before accepting the new baselines; no overflow was accepted. Screenshot updates were followed by the passing complete golden suite.

## Deployment and remaining gates

The original 63 historical migration files are retained in `supabase/archive/historical-migrations`; their three duplicate versions are documented. The ten reviewed upgrade corrections are retained separately. The active chain contains the immutable application baseline and six later corrections, including the Meet switch, assignment guard and hospital cascade/audit fix. The live migration ledger was reconciled only after exact actual-schema comparison, without replaying baseline DDL or deleting application data. Previous ledger metadata and statement hashes are recorded in the reconciliation manifest.

1. **SMTP rotation and controlled delivery.** The current ignored `env` password matches the exposed historical source. Revoke that app password with its account owner, put a fresh password in server secrets, and perform controlled delivery/retry tests. Check Supabase Auth's separate SMTP settings too. A configured existing credential is not proof of rotation.
2. **Real Google Meet call.** Doctor/patient/approved-guest link authorization and external browser navigation are verified. A real hosted meeting, participant admission and two-way media have not been exercised. The earlier Jitsi moderator/hosting blocker is superseded by the user's Meet choice; no Jitsi infrastructure deployment is required.
3. **Full Supabase clean installation and staging upgrade.** Cloud project creation hit the account's two-project limit. Local PostgreSQL uses managed-platform stubs and a reconstructed old application schema; these proofs do not test Supabase Auth/Storage/Realtime servers and do not substitute for the requested staging copy.
4. **Published links and Flutter rollout.** No published application URL is configured in `env`; the existing Auth Site URL is localhost. Local recovery routing and notification paths work, but production links and deployed Flutter hosting/mobile distribution remain unverified.

The plan requires every integration gate to pass without skips. These open gates prevent a completion claim.
