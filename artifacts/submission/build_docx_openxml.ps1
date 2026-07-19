$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$output = Join-Path $PSScriptRoot 'Week1_Activity_LastName_FirstName.docx'
$temp = Join-Path $PSScriptRoot 'openxml-build'

if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
New-Item -ItemType Directory -Path $temp, (Join-Path $temp '_rels'), (Join-Path $temp 'docProps'), (Join-Path $temp 'word'), (Join-Path $temp 'word\_rels'), (Join-Path $temp 'word\media') | Out-Null

$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8([string]$path, [string]$content) { [IO.File]::WriteAllText($path, $content, $utf8) }
function X([string]$s) { return [Security.SecurityElement]::Escape($s) }

function Run([string]$text, [int]$size = 21, [string]$color = '122B49', [bool]$bold = $false) {
  $b = if ($bold) { '<w:b/>' } else { '' }
  $parts = $text -split "`n", -1
  $xml = ''
  for ($i=0; $i -lt $parts.Count; $i++) {
    if ($i -gt 0) { $xml += '<w:br/>' }
    $xml += '<w:t xml:space="preserve">' + (X $parts[$i]) + '</w:t>'
  }
  return '<w:r><w:rPr><w:rFonts w:ascii="Aptos" w:hAnsi="Aptos"/><w:color w:val="' + $color + '"/><w:sz w:val="' + $size + '"/><w:szCs w:val="' + $size + '"/>' + $b + '</w:rPr>' + $xml + '</w:r>'
}

function Para([string]$text, [int]$size = 21, [string]$color = '122B49', [bool]$bold = $false, [string]$align = 'left', [int]$after = 100, [int]$before = 0) {
  return '<w:p><w:pPr><w:jc w:val="' + $align + '"/><w:spacing w:before="' + $before + '" w:after="' + $after + '"/></w:pPr>' + (Run $text $size $color $bold) + '</w:p>'
}

function Heading([string]$text, [int]$level = 1) {
  if ($level -eq 1) { return Para $text 38 '122B49' $true 'left' 170 0 }
  return Para $text 26 '1D67C9' $true 'left' 75 120
}

function Bullet([string]$text) { return Para ('- ' + $text) 20 '122B49' $false 'left' 65 0 }
function PageBreak { return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>' }

function Cell([string]$inner, [int]$width, [string]$shade = 'FFFFFF') {
  return '<w:tc><w:tcPr><w:tcW w:w="' + $width + '" w:type="dxa"/><w:shd w:fill="' + $shade + '"/><w:tcMar><w:top w:w="120" w:type="dxa"/><w:left w:w="140" w:type="dxa"/><w:bottom w:w="120" w:type="dxa"/><w:right w:w="140" w:type="dxa"/></w:tcMar></w:tcPr>' + $inner + '</w:tc>'
}

function Table([array]$rows, [array]$widths) {
  $grid = ($widths | ForEach-Object { '<w:gridCol w:w="' + $_ + '"/>' }) -join ''
  $body = ''
  foreach ($row in $rows) { $body += '<w:tr>' + ($row -join '') + '</w:tr>' }
  return '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:bottom w:val="nil"/><w:right w:val="nil"/><w:insideH w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders></w:tblPr><w:tblGrid>' + $grid + '</w:tblGrid>' + $body + '</w:tbl>'
}

function ImagePara([string]$rid, [int]$docPrId, [string]$name, [long]$cx = 2350000, [long]$cy = 4700000) {
  return '<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="60"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="' + $cx + '" cy="' + $cy + '"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:docPr id="' + $docPrId + '" name="' + (X $name) + '"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="' + (X $name) + '"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="' + $rid + '"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="' + $cx + '" cy="' + $cy + '"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
}

$gallery = @(
  [pscustomobject]@{ Id=6;  Title='A1. Web Login'; Category='All registered users'; Source='artifacts\browser\final_login.png'; Purpose='Authenticates patients, doctors, hospital administrators, and super administrators before protected pages are opened.'; Functions='Email/password entry, password recovery, account registration, and role-aware redirection.'; Mobile=$false },
  [pscustomobject]@{ Id=7;  Title='A2. Web Home'; Category='Guests and signed-in users'; Source='artifacts\browser\final_home.png'; Purpose='Serves as the main navigation hub for the application.'; Functions='Hospital search, online consultation, symptom assessment, My Care, and visible emergency instructions.'; Mobile=$false },
  [pscustomobject]@{ Id=8;  Title='A3. Web Symptom Assessment'; Category='Guests and patients'; Source='artifacts\browser\final_assessment_guest.png'; Purpose='Collects symptoms and relevant health context in a structured form.'; Functions='Symptoms, duration, age, conditions, allergies, medicines, emergency escalation, and assessment submission.'; Mobile=$false },
  [pscustomobject]@{ Id=9;  Title='A4. Web Assessment Result'; Category='Assessment users'; Source='artifacts\browser\assessment-result-check.png'; Purpose='Summarizes preliminary urgency and care-direction guidance without diagnosing.'; Functions='Suggested department, warning signs, possible conditions to discuss, safety disclaimer, and hospital matching.'; Mobile=$false },
  [pscustomobject]@{ Id=10; Title='A5. Web Hospital Directory'; Category='Public care seekers'; Source='artifacts\browser\final_hospitals.png'; Purpose='Compares verified hospitals in one searchable directory.'; Functions='Search, hospital-level filters, ER availability, locations, beds, rooms, services, and facility details.'; Mobile=$false },
  [pscustomobject]@{ Id=11; Title='A6. Web Hospital Detail'; Category='Patients and caregivers'; Source='artifacts\browser\president-diverse-departments.png'; Purpose='Presents detailed information about one selected hospital.'; Functions='Classification, ER/beds/rooms status, overview, location, contacts, departments, services, doctors, and schedules.'; Mobile=$false },
  [pscustomobject]@{ Id=12; Title='A7. Web Nearby-Care Map'; Category='Location-based care seekers'; Source='artifacts\browser\final_map.png'; Purpose='Ranks suitable hospitals using the user location and care requirement.'; Functions='Location permission, ER filter, required service entry, matching, ranking, and directions.'; Mobile=$false },
  [pscustomobject]@{ Id=13; Title='A8. Web Notifications'; Category='Signed-in users'; Source='artifacts\browser\final_notifications.png'; Purpose='Centralizes appointment, consultation, clinical, and operational alerts.'; Functions='Protected access, notification review, read status, and navigation to the related workflow.'; Mobile=$false },
  [pscustomobject]@{ Id=14; Title='A9. Doctor Patient Workspace'; Category='Authorized doctors'; Source='artifacts\browser\doctor-patients-history-full.png'; Purpose='Provides a consolidated view of assigned patients and cross-hospital care history.'; Functions='Consultations, diagnoses, plans, prescriptions, laboratory requests, results, documents, and attachments.'; Mobile=$false },
  [pscustomobject]@{ Id=15; Title='A10. Doctor Profile'; Category='Doctors'; Source='artifacts\browser\doctor-profile-tab.png'; Purpose='Displays account and verified professional information.'; Functions='Contact details, specialization, department, hospital, license, availability, fee, and biography.'; Mobile=$false },
  [pscustomobject]@{ Id=16; Title='A11. Hospital-Admin Care Console'; Category='Hospital administrators'; Source='web-hospital-admin.png'; Purpose='Coordinates hospital-level consultations and operational care workflows.'; Functions='Consultation monitoring, hospital patients, messages, status changes, operations, availability, and alerts.'; Mobile=$false },
  [pscustomobject]@{ Id=17; Title='A12. Super-Admin Platform Console'; Category='Platform super administrators'; Source='web-super-admin.png'; Purpose='Governs the CareNavigatorPH hospital network.'; Functions='Hospitals, administrator accounts, services, doctors, reports, permissions, settings, audit, and security review.'; Mobile=$false },
  [pscustomobject]@{ Id=18; Title='B1. Doctor Mobile Care'; Category='Doctors on mobile'; Source='mobile-doctor-care.png'; Purpose='Presents the clinical workspace in a compact mobile layout.'; Functions='Mobile clinical navigation, patient access, care actions, and role-safe responsive behavior.'; Mobile=$true },
  [pscustomobject]@{ Id=19; Title='B2. Hospital-Admin Mobile'; Category='Hospital administrators on mobile'; Source='mobile-hospital-admin.png'; Purpose='Shows hospital operations and care coordination on a small screen.'; Functions='Responsive administrative navigation, hospital workflows, and access controls.'; Mobile=$true },
  [pscustomobject]@{ Id=20; Title='B3. Super-Admin Mobile'; Category='Super administrators on mobile'; Source='mobile-super-admin-fixed.png'; Purpose='Demonstrates responsive presentation of platform-management information.'; Functions='Compact management navigation and mobile-safe administrative layout.'; Mobile=$true },
  [pscustomobject]@{ Id=21; Title='B4. Desktop-Portal Safeguard'; Category='Administrative mobile users'; Source='mobile-admin-blocked.png'; Purpose='Prevents selected high-risk administrative work from being performed in an unsafe mobile layout.'; Functions='Clear desktop requirement, access explanation, and return-to-sign-in action.'; Mobile=$true }
)

$body = ''

# Cover
$body += Para 'WEEK 1 | PRACTICAL ACTIVITY' 20 '009788' $true 'left' 350 0
$body += Para 'CareNavigatorPH' 64 '122B49' $true 'left' 20 150
$body += Para 'Navigate to the right care, at the right time.' 32 '1D67C9' $true 'left' 260 0
$body += Table @(@(Cell (Para "A mobile healthcare navigation app for Filipino communities`n`nSDG 3 | Good Health and Well-Being" 30 '122B49' $true 'center' 40 40) 9300 'EBF4FF')) @(9300)
$body += Para '' 20 '122B49' $false 'left' 120 0
$metaRows = @(
  @((Cell (Para 'Student Name' 18 '5A6D86' $true) 2100), (Cell (Para '[Last Name], [First Name]' 21) 7200)),
  @((Cell (Para 'Course / Section' 18 '5A6D86' $true) 2100), (Cell (Para 'Advanced Mobile Programming / [Section]' 21) 7200)),
  @((Cell (Para 'Instructor' 18 '5A6D86' $true) 2100), (Cell (Para '[Instructor Name]' 21) 7200)),
  @((Cell (Para 'Date' 18 '5A6D86' $true) 2100), (Cell (Para '____________________' 21) 7200)),
  @((Cell (Para 'Filename' 18 '5A6D86' $true) 2100), (Cell (Para 'Week1_Activity_LastName_FirstName' 21) 7200))
)
$body += Table $metaRows @(2100,7200)
$body += Para 'PROJECT SNAPSHOT' 18 '009788' $true 'left' 80 360
$body += Para 'CareNavigatorPH helps people describe symptoms safely, understand the appropriate level of care, find verified hospitals with relevant services and availability, and begin a consultation without presenting AI guidance as a medical diagnosis.' 24 '122B49' $false 'left' 100 0
$body += PageBreak

# Problem and SDG
$body += Heading '1. Community Problem & SDG Alignment' 1
$body += Table @(@(Cell ((Para 'PROBLEM STATEMENT' 18 '5A6D86' $true 'left' 60) + (Para 'People in many Philippine communities struggle to decide where to seek care because hospital information is fragmented, service availability is unclear, and symptoms can be difficult to interpret. This can cause delayed treatment, unnecessary travel, crowded facilities, and confusion during urgent situations.' 22)) 9300 'FFEFED')) @(9300)
$body += Heading 'Why this matters in the community' 2
$body += Bullet 'Patients may not know which nearby facility has the right department, specialist, emergency capability, beds, or rooms.'
$body += Bullet 'Rural residents, older adults, caregivers, and first-time patients may spend extra time calling or visiting multiple facilities.'
$body += Bullet 'Online health information can be misleading when it lacks local context, safety warnings, and a clear path to professional care.'
$body += Heading 'Selected UN Sustainable Development Goal' 2
$body += Table @(@((Cell (Para "SDG`n3" 42 'FFFFFF' $true 'center' 0 50) 1800 '1D67C9'), (Cell ((Para 'GOOD HEALTH AND WELL-BEING' 23 '122B49' $true) + (Para "Ensure healthy lives and promote well-being for all at all ages.`n`nDirect alignment: Target 3.8 focuses on access to quality essential healthcare services. CareNavigatorPH improves access by connecting users to appropriate, verified, and locally available care." 20)) 7500 'EBF4FF'))) @(1800,7500)
$body += Heading 'Intended impact' 2
$body += Para 'The app aims to shorten the path from uncertainty to appropriate professional care. It supports informed decisions and timely referrals while keeping emergency escalation, privacy, and clinician review central to the experience.' 21
$body += PageBreak

# Proposal
$body += Heading '2. Project Proposal' 1
$body += Heading 'Core concept' 2
$body += Para 'CareNavigatorPH is a mobile healthcare navigation platform designed for Philippine communities. A user can describe symptoms, receive preliminary guidance about urgency and the type of care to seek, compare verified hospitals, and start a consultation. The app does not diagnose or replace a licensed healthcare professional.' 21
$body += Heading 'Target audience' 2
$body += Table @(@((Cell (Para "PRIMARY USERS`n- Patients and caregivers`n- Residents searching for nearby care`n- People unsure which department or hospital level they need" 20) 4550 'EBF4FF'), (Cell (Para "SECONDARY USERS`n- Doctors and hospital staff`n- Hospital administrators`n- Community health workers and referral partners" 20) 4550 'E6F7F4'))) @(4550,4550)
$body += Heading 'Primary functionality' 2
$featureRows = @(
  @((Cell (Para '01' 20 '1D67C9' $true 'center') 600 'EBF4FF'), (Cell (Para 'AI symptom navigator' 19 '122B49' $true) 2200 'EBF4FF'), (Cell (Para 'Collects symptoms and context, then suggests urgency and an appropriate care type with safety warnings.' 18) 6500 'EBF4FF')),
  @((Cell (Para '02' 20 '1D67C9' $true 'center') 600), (Cell (Para 'Hospital directory' 19 '122B49' $true) 2200), (Cell (Para 'Searches verified facilities by location, level, service, specialist, and availability.' 18) 6500)),
  @((Cell (Para '03' 20 '1D67C9' $true 'center') 600 'EBF4FF'), (Cell (Para 'Care matching' 19 '122B49' $true) 2200 'EBF4FF'), (Cell (Para 'Connects assessment needs to suitable hospitals and departments.' 18) 6500 'EBF4FF')),
  @((Cell (Para '04' 20 '1D67C9' $true 'center') 600), (Cell (Para 'Consultation request' 19 '122B49' $true) 2200), (Cell (Para 'Lets a first-time user submit care needs and receive a trackable reference.' 18) 6500)),
  @((Cell (Para '05' 20 '1D67C9' $true 'center') 600 'EBF4FF'), (Cell (Para 'My Care' 19 '122B49' $true) 2200 'EBF4FF'), (Cell (Para 'Keeps appointments, messages, records, notifications, and consent in one place.' 18) 6500 'EBF4FF'))
)
$body += Table $featureRows @(600,2200,6500)
$body += Heading 'Scope and safety boundaries' 2
$body += Para 'The first version focuses on discovery, preliminary guidance, referrals, and consultation intake. It directs emergencies to 911 or the nearest emergency room, labels AI output as non-diagnostic, protects health data, and requires professional review for clinical decisions.' 20
$body += PageBreak

# Wireframes 1-2
$body += Heading '3. Mockup / Wireframe' 1
$body += Para 'User flow: Sign in > describe symptoms > review guidance > find matching care' 19 '5A6D86'
$wireRows1 = @(@((Cell (ImagePara 'rId1' 1 'Sign in') 4550), (Cell (ImagePara 'rId2' 2 'Symptom assessment') 4550)), @((Cell (Para "SCREEN 1 - SIGN IN`nPurpose: Provides secure entry for patients and care providers.`nKey elements: Email, password, recovery, and sign-in action.`nNext action: Sign in and proceed to the symptom navigator." 18) 4550 'EBF4FF'), (Cell (Para "SCREEN 2 - SYMPTOM ASSESSMENT`nPurpose: Collects information for preliminary care guidance.`nKey elements: Symptoms, duration, age, conditions, allergies, medicines, and emergency warning.`nNext action: Tap Check symptoms." 18) 4550 'E6F7F4')))
$body += Table $wireRows1 @(4550,4550)
$body += Heading 'Design notes' 2
$body += Para 'The interface uses a calm blue-and-teal palette, plain-language instructions, high-contrast actions, and persistent mobile navigation. Emergency messaging appears before the assessment to prevent unsafe reliance on the tool.' 20
$body += PageBreak

# Wireframes 3-4
$body += Heading '3. Mockup / Wireframe (continued)' 1
$wireRows2 = @(@((Cell (ImagePara 'rId3' 3 'Care guidance') 4550), (Cell (ImagePara 'rId4' 4 'Hospital directory') 4550)), @((Cell (Para "SCREEN 3 - CARE GUIDANCE`nPurpose: Turns the assessment into a clear next step without diagnosing.`nKey elements: Department, warning signs, possible conditions, hospital-level guidance, and disclaimer.`nNext action: Tap Find matching hospitals." 18) 4550 'E6F7F4'), (Cell (Para "SCREEN 4 - HOSPITAL DIRECTORY`nPurpose: Compares verified facilities for the identified need.`nKey elements: Search, level and ER filters, location, beds, rooms, and details.`nNext action: Open a hospital or proceed to consultation." 18) 4550 'EBF4FF')))
$body += Table $wireRows2 @(4550,4550)
$body += Heading 'Flow logic' 2
$body += Table @(@((Cell (Para "1`nSIGN IN" 18 'FFFFFF' $true 'center') 2000 '1D67C9'), (Cell (Para '>' 28 '1D67C9' $true 'center') 400), (Cell (Para "2`nASSESS" 18 'FFFFFF' $true 'center') 2000 '1D67C9'), (Cell (Para '>' 28 '1D67C9' $true 'center') 400), (Cell (Para "3`nGUIDANCE" 18 'FFFFFF' $true 'center') 2000 '1D67C9'), (Cell (Para '>' 28 '1D67C9' $true 'center') 400), (Cell (Para "4`nFIND CARE" 18 'FFFFFF' $true 'center') 2000 '1D67C9'))) @(2000,400,2000,400,2000,400,2000)
$body += Heading 'Expected result' 2
$body += Para 'At the end of the flow, the user understands the suggested level of care and has a practical next step: view a suitable hospital, get directions, or begin a consultation. The design reduces uncertainty without removing professional judgment.' 20
$body += PageBreak

# Wireframe 5
$body += Heading '3. Mockup / Wireframe (continued)' 1
$body += Para 'Final step: begin a first-time online consultation' 19 '5A6D86'
$body += ImagePara 'rId5' 5 'Consultation request' 7600000 5278000
$body += Table @(@(Cell (Para "SCREEN 5 - CONSULTATION REQUEST`nPurpose: Gives the user a direct way to request professional care after finding an appropriate facility or department.`nKey elements: Emergency warning, identity or contact verification, care-needs intake, schedule details, and a trackable reference.`nNext action: Verify the contact method, complete the intake form, and submit the request.`n`nDesign rationale: This screen closes the navigation loop by connecting information and hospital discovery to a professional care workflow." 19) 9300 'E6F7F4')) @(9300)
$body += Heading 'Complete five-screen user flow' 2
$body += Para '1 SIGN IN  >  2 ASSESS  >  3 GUIDANCE  >  4 HOSPITAL  >  5 CONSULT' 21 '1D67C9' $true 'center' 100 60
$body += PageBreak

# Complete application-page appendix
$body += Heading 'Appendix A. Complete Application Page Inventory' 1
$body += Para "The five wireframes above satisfy the required proposal flow. This appendix documents the remaining distinct mobile and web pages represented in the CareNavigatorPH routes and finalized screenshots." 21
$inventoryRows = @(
  @((Cell (Para 'PUBLIC ACCESS' 18 '1D67C9' $true) 1800 'EBF4FF'), (Cell (Para 'Login, registration, home, assessment, hospital directory, hospital detail, nearby map, and first-time consultation.' 19) 7500 'EBF4FF')),
  @((Cell (Para 'PATIENT ACCESS' 18 '1D67C9' $true) 1800), (Cell (Para 'Dashboard/My Care, care workspace, profile, secure messages, and notifications.' 19) 7500)),
  @((Cell (Para 'DOCTOR ACCESS' 18 '1D67C9' $true) 1800 'EBF4FF'), (Cell (Para 'Clinical workspace, consultations, patients, result review, records, clinical actions, messages, and professional profile.' 19) 7500 'EBF4FF')),
  @((Cell (Para 'HOSPITAL ADMIN' 18 '1D67C9' $true) 1800), (Cell (Para 'Hospital profile, operations, consultations, hospital patients, doctors, schedules, availability, analytics, and alerts.' 19) 7500)),
  @((Cell (Para 'SUPER ADMIN' 18 '1D67C9' $true) 1800 'EBF4FF'), (Cell (Para 'Hospitals, administrators, service categories, doctors, reports, settings, permissions, audits, and security review.' 19) 7500 'EBF4FF'))
)
$body += Table $inventoryRows @(1800,7500)
$body += Heading 'Application routes reviewed' 2
$body += Para '/login, /register, /home, /hospitals, /hospitals/map, /hospitals/:hospitalId, /assessment, /consult, /dashboard, /care, /profile, /messages/:conversationId, /notifications, /admin, and /admin/operations.' 19
$body += Table @(@(Cell (Para 'Repeated test captures and duplicate screenshots are omitted. Each following page represents a distinct finalized interface or role-specific responsive view.' 19) 9300 'E6F7F4')) @(9300)
$body += PageBreak

foreach ($item in $gallery) {
  $body += Heading $item.Title 1
  $body += Para ('Audience: ' + $item.Category) 19 '5A6D86' $true
  if ($item.Mobile) {
    $body += ImagePara ('rId' + $item.Id) $item.Id $item.Title 2800000 6060000
  } else {
    $body += ImagePara ('rId' + $item.Id) $item.Id $item.Title 7600000 5278000
  }
  $explanation = 'PURPOSE' + "`n" + $item.Purpose + "`n`n" + 'MAIN FUNCTIONS' + "`n" + $item.Functions
  $body += Table @(@(Cell (Para $explanation 19) 9300 $(if ($item.Mobile) { 'E6F7F4' } else { 'EBF4FF' }))) @(9300)
  $body += PageBreak
}

# Presentation
$body += Heading '4. Presentation Guide' 1
$body += Heading 'Suggested 2-3 minute presentation script' 2
$scriptRows = @(
  @((Cell (Para 'OPENING' 17 '1D67C9' $true) 1700 'EBF4FF'), (Cell (Para 'Our project is CareNavigatorPH, a mobile app that helps Filipino patients navigate from symptoms to suitable local care.' 19) 7600 'EBF4FF')),
  @((Cell (Para 'THE PROBLEM' 17 '1D67C9' $true) 1700), (Cell (Para 'People often do not know which hospital has the right service, specialist, or current capacity. This causes confusion, delays, and unnecessary travel.' 19) 7600)),
  @((Cell (Para 'SDG' 17 '1D67C9' $true) 1700 'EBF4FF'), (Cell (Para 'The project supports SDG 3: Good Health and Well-Being, particularly Target 3.8 on access to quality essential healthcare services.' 19) 7600 'EBF4FF')),
  @((Cell (Para 'THE SOLUTION' 17 '1D67C9' $true) 1700), (Cell (Para 'Users enter symptoms, receive safety-focused guidance, see the recommended type of care, and find verified matching hospitals.' 19) 7600)),
  @((Cell (Para 'USER FLOW' 17 '1D67C9' $true) 1700 'EBF4FF'), (Cell (Para 'The five wireframes show the complete journey: sign in, symptom assessment, care guidance, hospital selection, and consultation request.' 19) 7600 'EBF4FF')),
  @((Cell (Para 'SAFETY' 17 '1D67C9' $true) 1700), (Cell (Para 'CareNavigatorPH does not diagnose. Emergency cases are directed to 911 or the nearest ER, and clinical decisions remain with licensed professionals.' 19) 7600)),
  @((Cell (Para 'CLOSING' 17 '1D67C9' $true) 1700 'EBF4FF'), (Cell (Para 'Our goal is simple: reduce the time and uncertainty between needing help and reaching the right care.' 19) 7600 'EBF4FF'))
)
$body += Table $scriptRows @(1700,7600)
$body += Heading 'Success measures for a future prototype test' 2
$body += Bullet 'Users can identify the next care step without assistance.'
$body += Bullet 'Users can find a suitable facility in three minutes or less.'
$body += Bullet 'Users understand that AI guidance is preliminary and non-diagnostic.'
$body += Bullet 'Users notice emergency instructions before starting an assessment.'
$body += Table @(@(Cell (Para "SUBMISSION CHECKLIST`n[ ] Replace the student, section, instructor, and date placeholders.`n[ ] Rename the file using your real LastName_FirstName.`n[ ] Review the wireframes and rehearse the presentation script.`n[ ] Upload the Word file or exported PDF as instructed." 19) 9300 'E6F7F4')) @(9300)

$sectPr = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="900" w:right="950" w:bottom="900" w:left="950" w:header="360" w:footer="360" w:gutter="0"/></w:sectPr>'
$documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>' + $body + $sectPr + '</w:body></w:document>'

$contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>'
$rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>'
$docRelItems = ''
for ($imageId = 1; $imageId -le 5; $imageId++) {
  $docRelItems += '<Relationship Id="rId' + $imageId + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image' + $imageId + '.png"/>'
}
foreach ($item in $gallery) {
  $docRelItems += '<Relationship Id="rId' + $item.Id + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image' + $item.Id + '.png"/>'
}
$docRelItems += '<Relationship Id="rId99" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
$docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + $docRelItems + '</Relationships>'
$styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Aptos" w:hAnsi="Aptos"/><w:sz w:val="21"/><w:color w:val="122B49"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="100"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>'
$core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>CareNavigatorPH - Week 1 Practical Activity</dc:title><dc:subject>Advanced Mobile Programming proposal and wireframes</dc:subject><dc:creator>Student</dc:creator><cp:keywords>CareNavigatorPH, SDG 3, mobile app, wireframe</cp:keywords><dcterms:created xsi:type="dcterms:W3CDTF">2026-07-19T12:00:00Z</dcterms:created></cp:coreProperties>'
$app = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Microsoft Office Word</Application><AppVersion>16.0000</AppVersion></Properties>'

Write-Utf8 (Join-Path $temp '[Content_Types].xml') $contentTypes
Write-Utf8 (Join-Path $temp '_rels\.rels') $rels
Write-Utf8 (Join-Path $temp 'word\document.xml') $documentXml
Write-Utf8 (Join-Path $temp 'word\_rels\document.xml.rels') $docRels
Write-Utf8 (Join-Path $temp 'word\styles.xml') $styles
Write-Utf8 (Join-Path $temp 'docProps\core.xml') $core
Write-Utf8 (Join-Path $temp 'docProps\app.xml') $app

Copy-Item (Join-Path $root 'mobile-login.png') (Join-Path $temp 'word\media\image1.png')
Copy-Item (Join-Path $root 'artifacts\browser\assessment-result-mobile-check.png') (Join-Path $temp 'word\media\image2.png')
Copy-Item (Join-Path $root 'artifacts\browser\assessment-recommendation-mobile-bottom.png') (Join-Path $temp 'word\media\image3.png')
Copy-Item (Join-Path $root 'artifacts\browser\hospital-directory-mobile-check.png') (Join-Path $temp 'word\media\image4.png')
Copy-Item (Join-Path $root 'artifacts\browser\final_consult.png') (Join-Path $temp 'word\media\image5.png')
foreach ($item in $gallery) {
  Copy-Item (Join-Path $root $item.Source) (Join-Path $temp ('word\media\image' + $item.Id + '.png'))
}

if (Test-Path $output) { Remove-Item -LiteralPath $output -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$archive = [IO.Compression.ZipFile]::Open($output, [IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem -LiteralPath $temp -File -Recurse | ForEach-Object {
    $entryName = $_.FullName.Substring($temp.Length + 1).Replace('\', '/')
    $entry = $archive.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
    $sourceStream = [IO.File]::OpenRead($_.FullName)
    $entryStream = $entry.Open()
    try { $sourceStream.CopyTo($entryStream) }
    finally { $entryStream.Dispose(); $sourceStream.Dispose() }
  }
}
finally { $archive.Dispose() }
Remove-Item -LiteralPath $temp -Recurse -Force
Write-Output "Created: $output"
