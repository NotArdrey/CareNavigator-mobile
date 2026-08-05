# CareNavigator PH — Redesign verification

## Evidence summary

- 27 baseline desktop screenshots at 1440×960
- 27 redesigned desktop screenshots at 1440×960
- 27 baseline mobile screenshots at 390×844
- 27 redesigned mobile screenshots at 390×844
- 54/54 before/after pairs have different SHA-256 hashes
- 54/54 redesigned screenshots match the required viewport dimensions
- Fresh public, patient, doctor, hospital-admin, and super-admin browser sessions completed without captured browser errors

The administrator routes intentionally render the redesigned desktop-security policy state below 1024 logical pixels. This is the tested product behavior for compact web and is captured for both administrator roles.

## Complete route and screen checklist

| Screenshot / screen | Route and state | 1440×960 | 390×844 | Substantially redesigned Dart file | Changed lines (+ / − / total) |
|---|---|---:|---:|---|---:|
| root-redirect | `/` → `/login` | ✅ | ✅ | `login_screen.dart` | 145 / 139 / 284 |
| login | `/login` | ✅ | ✅ | `login_screen.dart` | 145 / 139 / 284 |
| register | `/register` | ✅ | ✅ | `register_screen.dart` | 178 / 146 / 324 |
| home | `/home` | ✅ | ✅ | `home_screen.dart` | 512 / 270 / 782 |
| hospitals | `/hospitals` | ✅ | ✅ | `hospital_list_screen.dart` | 445 / 273 / 718 |
| hospital-map | `/hospitals/map` | ✅ | ✅ | `hospital_map_screen.dart` | 857 / 263 / 1,120 |
| hospital-detail | `/hospitals/:hospitalId` | ✅ | ✅ | `hospital_detail_screen.dart` | 368 / 287 / 655 |
| assessment | `/assessment` | ✅ | ✅ | `assessment_screen.dart` | 362 / 279 / 641 |
| consult | `/consult` | ✅ | ✅ | `guest_consultation_screen.dart` | 313 / 215 / 528 |
| dashboard-patient | `/dashboard` · patient | ✅ | ✅ | `dashboard_screen.dart` | 635 / 109 / 744 |
| dashboard-doctor | `/dashboard` · doctor | ✅ | ✅ | `dashboard_screen.dart` | 635 / 109 / 744 |
| dashboard-hospital-admin | `/dashboard` · hospital admin | ✅ | ✅ policy state | `dashboard_screen.dart` | 635 / 109 / 744 |
| dashboard-super-admin | `/dashboard` · super admin | ✅ | ✅ policy state | `dashboard_screen.dart` | 635 / 109 / 744 |
| care-patient | `/care` · patient | ✅ | ✅ | `care_workspace_screen.dart` | 397 / 82 / 479 |
| care-doctor | `/care` · doctor | ✅ | ✅ | `care_workspace_screen.dart` | 397 / 82 / 479 |
| care-hospital-admin | `/care` · hospital admin | ✅ | ✅ policy state | `care_workspace_screen.dart` | 397 / 82 / 479 |
| profile-patient | `/profile` · patient | ✅ | ✅ | `profile_screen.dart` | 700 / 67 / 767 |
| profile-doctor | `/profile` · doctor | ✅ | ✅ | `profile_screen.dart` | 700 / 67 / 767 |
| profile-hospital-admin | `/profile` · hospital admin | ✅ | ✅ policy state | `profile_screen.dart` | 700 / 67 / 767 |
| profile-super-admin | `/profile` · super admin | ✅ | ✅ policy state | `profile_screen.dart` | 700 / 67 / 767 |
| notifications-patient | `/notifications` · patient data | ✅ | ✅ | `notification_center_screen.dart` | 419 / 89 / 508 |
| messages-error-patient | `/messages/:conversationId` · empty seeded thread | ✅ | ✅ | `chat_screen.dart` | 245 / 159 / 404 |
| admin-console-hospital-admin | `/admin` · hospital admin | ✅ | ✅ policy state | `admin_console_screen.dart` | 109 / 136 / 245 |
| admin-console-super-admin | `/admin` · super admin | ✅ | ✅ policy state | `admin_console_screen.dart` | 109 / 136 / 245 |
| admin-operations-hospital-admin | `/admin/operations` · hospital admin | ✅ | ✅ policy state | `admin_operations_screen.dart` | 119 / 92 / 211 |
| admin-operations-super-admin | `/admin/operations` · super admin | ✅ | ✅ policy state | `admin_operations_screen.dart` | 119 / 92 / 211 |
| not-found | unknown route / router error screen | ✅ | ✅ | `app_router.dart` | 94 / 20 / 114 |

The non-routable missing-configuration startup state was also redesigned in `app.dart` (25 additions / 27 deletions / 52 changed lines). It is not part of the configured route screenshot matrix because the verified build has valid public configuration.

## Shared visual system work

| File | Scope | Changed/new lines |
|---|---|---:|
| `app_theme.dart` | Care Atlas tokens; typography; form, button, chip, dialog, sheet, list, navigation themes | 351 / 54 / 405 |
| `app_layout.dart` | New shared responsive layout, cards, buttons, text fields, badges, list rows, dialogs, sheets, and module rail | 795 new lines |
| `app_states.dart` | New full-region empty, error, restricted, and skeleton loading states | 200 new lines |
| `auth_page_shell.dart` | New immersive desktop/mobile authentication composition | 359 new lines |
| `app_page_header.dart` | New editorial page identity and responsive header | 104 / 37 / 141 |
| `app_shell.dart` | New compact evergreen desktop rail and floating mobile dock | 135 / 117 / 252 |
| `admin_desktop_only_screen.dart` | New compact-web administrator security-policy state | 83 / 39 / 122 |
| `brand_mark.dart` | New inverse-aware brand treatment | 16 / 19 / 35 |

## Visual system

- Alabaster application canvas, paper data surfaces, deep-evergreen navigation and feature planes
- Coral primary emphasis, sea-glass care states, cobalt informational accents
- Editorial route headers with eyebrow, strong title, concise context, and constrained actions
- Desktop navigation uses a compact 112-pixel rail; compact navigation uses a floating rounded dock
- Public facility discovery uses a filter workspace and dense comparison rows rather than an equal-card gallery
- Authenticated care uses role-specific command heroes, persistent module rails, and grouped task directories
- Forms use labels outside filled controls, 52-pixel primary actions, and grouped identity/security sections
- Empty and restricted states occupy the full available region; loading uses skeleton surfaces rather than a lone spinner
- Dialogs and bottom sheets use shared `AppDialog` and `AppModalSheet` compositions plus global theme defaults

## Verification commands

- `flutter analyze` — no issues
- `flutter test` — 26 tests passed
- `flutter build web --release` — succeeded
- `git diff --check` — passed (only Git line-ending notices)
