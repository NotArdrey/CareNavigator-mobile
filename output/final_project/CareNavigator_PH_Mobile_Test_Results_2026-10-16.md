# CareNavigator PH — Android demo verification

**Result: all five demonstration scenarios passed on the Android emulator after the fixes below.**

Tested on 16 October 2026 using Pixel 10 Pro, Android 17 / API 37, x86_64, with the live project backend. The final installed debug APK is version 1.0.0 (1). Physical Android phones and iOS were not tested.

## What was corrected

- The emulator was running an APK last updated on 26 July 2026. Its Profile screen failed with the ambiguous `users`–`hospitals` relationship error (`PGRST201`). The current source already selects the hospital foreign key explicitly. Building and installing the current app restored Profile loading.
- TS-04's original dummy doctor had no schedule and was therefore omitted from the booking list. The retained synthetic doctor now has a published Monday 09:00–09:15 Manila window requiring a 30-minute reservation. It appears in the selector and produces zero qualifying slots.
- Cancelling from appointment details refreshed the detail screen but left the retained list showing the previous status. The cancellation action now also refreshes the list. A regression test reproduced the failure before the change and passed afterwards.
- The emulator's timezone was changed from GMT to Asia/Manila. Appointment times below use Manila time.

## Five scenarios and observed results

| ID | Demonstration | Observed result | Result |
| --- | --- | --- | --- |
| TS-01 | Enter a wrong patient password, then sign in correctly. | Wrong password displayed “Invalid login credentials.” `demo@cn.test` / `pass123` opened the patient workspace. Profile loaded the demo patient's details without the database error. | PASS |
| TS-02 | Search the public hospital directory and open the prepared hospital. | Searching `Demo` returned two matching hospitals. Opening **CareNavigator Demo Hospital**, Baliwag, Bulacan, displayed its details, Demo General Medicine department, and the two demo doctors. | PASS |
| TS-03 | Reserve an in-person appointment more than 24 hours ahead. | Reserved **Dr. Demo Available**, **18 October 2026, 09:00**. The app displayed “Appointment reserved. Current status: pending.” The appointment showed the selected doctor, hospital, date and time. The real availability RPC stopped offering that occupied time; reopening the selector offered 09:30 first. | PASS |
| TS-04 | Select **Dr. Demo No Slots** with In person care and a concern entered. | The app displayed the no-reservable-times message and disabled Reserve consultation. Tapping its disabled position created no appointment. The final repeat retained the same four consultation records before and after, and the real availability RPC returned zero slots. | PASS |
| TS-05 | Open the booked appointment, inspect its details, then cancel it. | Doctor, facility and date/time matched the booking. Cancellation succeeded. Returning to the list immediately showed the tested record under Past as Cancelled, without a Cancel action. The database retained the cancelled row and offered the released time again. | PASS |

The TS-03 appointment was cancelled during TS-05. After fixing the list refresh, another appointment was booked and cancelled through the installed Android app to repeat the complete transition successfully.

## Account and presentation steps

**Email:** `demo@cn.test`  
**Password:** `pass123`

1. **TS-01:** Sign out through the navigation menu. Try a wrong password, show the error, then use the correct password.
2. **TS-02:** Open **Find care**, search `Demo`, and choose **CareNavigator Demo Hospital** in **Baliwag, Bulacan**. Scroll to Clinician availability to show the doctors.
3. **TS-03:** Open **Appointments → Reserve consultation**. Choose **CareNavigator Demo Hospital → Dr. Demo Available → In person**. Enter a short demo concern, choose a published date/time at least 24 hours ahead, and reserve. Show the confirmation and appointment details. Reopen the reservation selector with the same doctor/date to show that the occupied time is gone, then close it.
4. **TS-04:** Open Reserve consultation, choose the same hospital and **Dr. Demo No Slots**, keep **In person**, and enter a concern. Show the empty-availability message and disabled Reserve consultation button. Close the dialog with Cancel.
5. **TS-05:** Open the prepared appointment labelled **SYNTHETIC TS-05 Demo - View And Cancel This Appointment**. It remains active for **20 October 2026, 09:00**, with **Dr. Demo Available**. Show its details, cancel it, confirm, then return to Appointments and show its Cancelled history entry. You can also use the new appointment you booked during TS-03.

The emulator is left signed in to the demo patient. The two mobile verification bookings are cancelled; the original TS-05 appointment remains pending and available for your presentation.

## Screenshots and backend evidence

- [TS-01: incorrect password](mobile_test_evidence/ts01-invalid.png)
- [TS-01: patient workspace](mobile_test_evidence/ts01-valid.png)
- [Profile working on the final APK](mobile_test_evidence/final-profile-working.png)
- [TS-02: search results](mobile_test_evidence/ts02-demo-search.png)
- [TS-02: hospital doctors](mobile_test_evidence/ts02-doctors-visible.png)
- [TS-03: booking confirmation on the final APK](mobile_test_evidence/final-ts03-reserved.png)
- [TS-03: occupied slot removed](mobile_test_evidence/ts03-slot-removed.png)
- [TS-04: no slots and disabled Reserve button](mobile_test_evidence/final-ts04-disabled.png)
- [TS-05: appointment details](mobile_test_evidence/final-ts05-details.png)
- [TS-05: cancelled record after returning to the list](mobile_test_evidence/final-ts05-list-return.png)
- [Backend state before final cancellation](mobile_test_evidence/final-before-cancellation.json)
- [Backend state after cancellation](mobile_test_evidence/final-backend-proof.json)
- [Backend state after the final no-slot test](mobile_test_evidence/final-after-ts04.json)

The JSON evidence contains only synthetic appointment records and verification results. It contains no session tokens or server keys.

## Build and code checks

- `flutter analyze`: no issues found.
- `flutter test test/appointment_cancellation_refresh_test.dart test/workspace_row_actions_test.dart --reporter expanded`: **44 automated checks passed**. These support the five presentation scenarios; they are not additional presentation scenarios.
- `flutter build apk --debug --dart-define-from-file=.codex-runtime/public-build-env.json`: passed.
- Final APK installed successfully with ADB. Its on-device SHA-256 matched the exported file.
- [Tested Android APK](CareNavigator_PH_Demo_Android.apk)
- SHA-256: `53dad9d7f02de79d46630a59e7b4e3a69f05782e959da1f49f15298fdc62fb96`

The APK uses the project's public client configuration. Testing used real app requests and synthetic demo data, without replacing backend responses. This verifies these five flows on the named Android emulator, rather than every feature or every mobile device.
