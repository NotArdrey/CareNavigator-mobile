param(
  [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
  [switch]$SkipDeck,
  [switch]$SkipWord
)

$ErrorActionPreference = 'Stop'

function RGB([int]$r, [int]$g, [int]$b) { return $r + ($g * 256) + ($b * 65536) }
function Pt([double]$inches) { return $inches * 72.0 }

$C = @{
  Navy   = RGB 11 37 69
  Ink    = RGB 22 48 65
  Teal   = RGB 0 139 139
  Teal2  = RGB 38 166 154
  Mint   = RGB 228 247 244
  Pale   = RGB 245 248 250
  Panel  = RGB 237 242 245
  Line   = RGB 207 219 226
  Muted  = RGB 91 112 128
  White  = RGB 255 255 255
  Green  = RGB 33 133 89
  GreenP = RGB 230 245 237
  Amber  = RGB 166 105 0
  AmberP = RGB 255 245 218
  Red    = RGB 173 46 46
  RedP   = RGB 253 235 235
  Blue   = RGB 41 114 168
  BlueP  = RGB 230 241 249
}

$outDir = Join-Path $WorkspaceRoot 'output\defense'
$buildDir = Join-Path $WorkspaceRoot 'tmp\defense_build'
$slidePngDir = Join-Path $buildDir 'slides_png'
New-Item -ItemType Directory -Force -Path $outDir, $buildDir, $slidePngDir | Out-Null

$pptxPath = Join-Path $outDir 'CareNavigator_PH_System_Defense.pptx'
$pdfPath = Join-Path $outDir 'CareNavigator_PH_System_Defense.pdf'
$docxPath = Join-Path $outDir 'CareNavigator_PH_Project_Documentation.docx'
$docQaPdf = Join-Path $buildDir 'CareNavigator_PH_Project_Documentation_QA.pdf'

$appIcon = Join-Path $WorkspaceRoot 'assets\images\app_icon.png'
$assistantOpen = Join-Path $WorkspaceRoot 'tmp\carefix-open.png'
$assistantResult = Join-Path $WorkspaceRoot 'tmp\carefix-result.png'
$guestMobile = Join-Path $WorkspaceRoot 'test\failures\guest_mobile_testImage.png'
$patientMobile = Join-Path $WorkspaceRoot 'test\failures\patient_mobile_testImage.png'
$doctorMobile = Join-Path $WorkspaceRoot 'test\failures\doctor_mobile_testImage.png'
$hospitalAdminMobile = Join-Path $WorkspaceRoot 'test\visual_catalog\hospital_admin_mobile.png'
$superAdminMobile = Join-Path $WorkspaceRoot 'test\visual_catalog\super_admin_mobile.png'
$doctorRxWeb = Join-Path $WorkspaceRoot 'test\failures\doctor_prescriptions_web_testImage.png'
$hospitalAvailabilityWeb = Join-Path $WorkspaceRoot 'test\visual_catalog\hospital_availability_web.png'

function Set-ShapeText($shape, [string]$text, [double]$size, [int]$color, [bool]$bold=$false, [int]$align=1, [int]$valign=1, [string]$font='Aptos') {
  $shape.TextFrame2.TextRange.Text = $text
  $shape.TextFrame2.MarginLeft = 0
  $shape.TextFrame2.MarginRight = 0
  $shape.TextFrame2.MarginTop = 0
  $shape.TextFrame2.MarginBottom = 0
  $shape.TextFrame2.WordWrap = -1
  $shape.TextFrame2.AutoSize = 0
  $shape.TextFrame2.VerticalAnchor = $valign
  $shape.TextFrame2.TextRange.ParagraphFormat.Alignment = $align
  $shape.TextFrame2.TextRange.Font.Name = $font
  $shape.TextFrame2.TextRange.Font.Size = $size
  $shape.TextFrame2.TextRange.Font.Bold = $(if ($bold) { -1 } else { 0 })
  $shape.TextFrame2.TextRange.Font.Fill.ForeColor.RGB = $color
}

function Add-Text($slide, [string]$text, [double]$x, [double]$y, [double]$w, [double]$h, [double]$size, [int]$color, [bool]$bold=$false, [int]$align=1, [int]$valign=1, [string]$name='text') {
  $s = $slide.Shapes.AddTextbox(1, $x, $y, $w, $h)
  $s.Name = $name
  Set-ShapeText $s $text $size $color $bold $align $valign
  return $s
}

function Add-Box($slide, [double]$x, [double]$y, [double]$w, [double]$h, [int]$fill, [int]$line, [double]$radius=0, [string]$name='box') {
  $shapeType = $(if ($radius -gt 0) { 5 } else { 1 })
  $s = $slide.Shapes.AddShape($shapeType, $x, $y, $w, $h)
  $s.Name = $name
  $s.Fill.ForeColor.RGB = $fill
  $s.Fill.Solid()
  $s.Line.ForeColor.RGB = $line
  $s.Line.Weight = 1
  return $s
}

function Add-Line($slide, [double]$x1, [double]$y1, [double]$x2, [double]$y2, [int]$color, [double]$weight=1.5, [bool]$arrow=$false) {
  $line = $slide.Shapes.AddConnector(1, $x1, $y1, $x2, $y2)
  $line.Line.ForeColor.RGB = $color
  $line.Line.Weight = $weight
  if ($arrow) { $line.Line.EndArrowheadStyle = 3 }
  return $line
}

function Add-ImageFit($slide, [string]$path, [double]$x, [double]$y, [double]$w, [double]$h, [string]$name='image') {
  Add-Type -AssemblyName System.Drawing
  $img = [System.Drawing.Image]::FromFile($path)
  try { $ratio = $img.Width / [double]$img.Height } finally { $img.Dispose() }
  $frameRatio = $w / $h
  if ($ratio -gt $frameRatio) { $iw = $w; $ih = $w / $ratio; $ix = $x; $iy = $y + (($h-$ih)/2) }
  else { $ih = $h; $iw = $h * $ratio; $iy = $y; $ix = $x + (($w-$iw)/2) }
  $pic = $slide.Shapes.AddPicture($path, 0, -1, $ix, $iy, $iw, $ih)
  $pic.Name = $name
  return $pic
}

function Add-Title($slide, [string]$title, [int]$number, [string]$eyebrow='SYSTEM DEFENSE') {
  Add-Text $slide $eyebrow 42 24 600 18 10 $C.Teal $true 1 1 'eyebrow' | Out-Null
  Add-Text $slide $title 42 48 876 52 36 $C.Navy $true 1 1 'slide-title' | Out-Null
  Add-Line $slide 42 107 918 107 $C.Line 1 $false | Out-Null
  Add-Text $slide ([string]$number) 900 510 18 14 9 $C.Muted $false 3 3 'slide-number' | Out-Null
}

function Add-Notes($slide, [string[]]$sources) {
  $noteText = "[Sources]`r`n" + (($sources | ForEach-Object { "- $_" }) -join "`r`n") + "`r`n[/Sources]"
  try {
    foreach ($shape in $slide.NotesPage.Shapes) {
      try {
        if ($shape.PlaceholderFormat.Type -eq 2) {
          $shape.TextFrame.TextRange.Text = $noteText
          break
        }
      } catch {}
    }
  } catch {}
}

function Add-BulletLine($slide, [string]$text, [double]$x, [double]$y, [double]$w, [double]$h, [int]$color=$C.Ink, [double]$size=17) {
  $dot = $slide.Shapes.AddShape(9, $x, $y+7, 8, 8)
  $dot.Fill.ForeColor.RGB = $C.Teal
  $dot.Line.Visible = 0
  Add-Text $slide $text ($x+18) $y ($w-18) $h $size $color $false 1 1 'bullet' | Out-Null
}

$ppt = $null
$pres = $null
if (-not $SkipDeck) {
try {
  $ppt = New-Object -ComObject PowerPoint.Application
  $ppt.Visible = -1
  $pres = $ppt.Presentations.Add()
  $pres.PageSetup.SlideWidth = 960
  $pres.PageSetup.SlideHeight = 540

  # Slide 1 - cover
  $s = $pres.Slides.Add(1, 12)
  $s.Background.Fill.ForeColor.RGB = $C.White
  Add-Box $s 0 0 960 16 $C.Teal $C.Teal 0 'accent-bar' | Out-Null
  Add-ImageFit $s $appIcon 46 43 62 62 'brand-icon' | Out-Null
  Add-Text $s 'CareNavigator PH' 126 50 570 58 54 $C.Navy $true 1 1 'cover-title' | Out-Null
  Add-Text $s 'A role-aware healthcare navigation and digital care platform' 48 124 805 34 24 $C.Ink $false 1 1 'cover-subtitle' | Out-Null
  Add-Text $s 'SYSTEM DEFENSE PRESENTATION' 48 170 390 18 11 $C.Teal $true 1 1 'cover-label' | Out-Null
  $frame = Add-Box $s 48 216 864 246 $C.Pale $C.Line 1 'hero-frame'
  Add-ImageFit $s $assistantOpen 58 226 844 226 'care-assistant-screen' | Out-Null
  Add-Text $s 'Prepared for project defense  |  02 September 2026  |  Proponents: [Insert names]' 48 487 810 20 13 $C.Muted $false 1 1 'cover-meta' | Out-Null
  Add-Notes $s @('README.md', 'SYSTEM_ARCHITECTURE.md', 'tmp/carefix-open.png')

  # Slide 2 - problem
  $s = $pres.Slides.Add(2, 12); Add-Title $s 'Care access breaks across disconnected steps' 2
  Add-Text $s 'Finding a hospital is only the first decision.' 42 135 500 92 34 $C.Navy $true 1 1 'problem-statement' | Out-Null
  Add-BulletLine $s 'Public hospital, service, clinician, schedule, and capacity information are difficult to compare in one place.' 42 250 500 66
  Add-BulletLine $s 'Guest intake, booking, consultation, and follow-up often require repeated handoffs and duplicate information.' 42 330 500 66
  Add-BulletLine $s 'Clinical records, documents, prescriptions, laboratory results, and reminders can become fragmented across actors.' 42 410 500 66
  Add-Box $s 606 136 312 350 $C.Navy $C.Navy 1 'response-field' | Out-Null
  Add-Text $s 'DESIGN RESPONSE' 638 166 240 22 12 $C.Teal2 $true 1 1 'response-label' | Out-Null
  $items = @(
    @('01','Guide','Verified discovery plus safety-aware assistance'),
    @('02','Connect','A continuous path from request to consultation'),
    @('03','Protect','Role-scoped data, private files, and auditability')
  )
  $yy=216
  foreach($it in $items){
    Add-Text $s $it[0] 638 $yy 40 28 18 $C.Teal2 $true 1 1 | Out-Null
    Add-Text $s $it[1] 692 $yy 178 25 20 $C.White $true 1 1 | Out-Null
    Add-Text $s $it[2] 692 ($yy+31) 182 48 14 $C.Panel $false 1 1 | Out-Null
    $yy += 91
  }
  Add-Notes $s @('README.md', 'SYSTEM_ARCHITECTURE.md sections 1 and 6')

  # Slide 3 - roles
  $s = $pres.Slides.Add(3, 12); Add-Title $s 'One platform supports five role-aware experiences' 3
  Add-Text $s 'The same care journey changes by responsibility; routes, actions, and data visibility follow the signed-in role.' 42 128 870 32 18 $C.Muted $false 1 1 | Out-Null
  $roleData = @(
    @('Guest','Discover care, ask the assistant, and submit a verified request',$guestMobile),
    @('Patient','Book care, communicate, and manage records',$patientMobile),
    @('Doctor','Manage schedules, consultations, prescriptions, and labs',$doctorMobile),
    @('Hospital admin','Operate one hospital, staff, services, and capacity',$hospitalAdminMobile),
    @('Super admin','Govern hospitals, accounts, settings, analytics, and audits',$superAdminMobile)
  )
  $x=42
  foreach($r in $roleData){
    Add-Box $s $x 178 160 270 $C.Pale $C.Line 1 | Out-Null
    Add-ImageFit $s $r[2] ($x+42) 192 76 142 | Out-Null
    Add-Text $s $r[0] ($x+14) 350 132 26 18 $C.Navy $true 2 1 | Out-Null
    Add-Text $s $r[1] ($x+14) 384 132 52 13 $C.Muted $false 2 1 | Out-Null
    $x += 176
  }
  Add-Notes $s @('lib/src/models/auth/user_role.dart', 'lib/src/routing/app_router.dart', 'test visual artifacts named on slide')

  # Slide 4 - objectives
  $s = $pres.Slides.Add(4, 12); Add-Title $s 'Six objectives make care accountable' 4
  Add-Box $s 42 132 876 84 $C.Mint $C.Teal 1 'general-objective' | Out-Null
  Add-Text $s 'GENERAL OBJECTIVE' 66 152 185 18 11 $C.Teal $true 1 1 | Out-Null
  Add-Text $s 'Design and implement a secure, responsive platform that helps people find appropriate care and supports the care lifecycle across authorized users.' 66 178 824 28 17 $C.Navy $true 1 1 | Out-Null
  $objectives = @(
    @('1','Make care discoverable','Publish verified hospitals, services, clinicians, schedules, routes, and availability.'),
    @('2','Guide safely','Use deterministic emergency checks and preliminary AI guidance without replacing diagnosis.'),
    @('3','Connect the journey','Link guest intake, booking, consultation, communication, documents, and follow-up.'),
    @('4','Enable role-based work','Provide patient, doctor, hospital-administrator, and platform-governance workspaces.'),
    @('5','Protect clinical data','Enforce authorization with JWTs, RLS, private storage, constraints, triggers, and audit logs.'),
    @('6','Verify quality','Use analysis, unit/widget tests, SQL acceptance tests, build checks, and visual baselines.')
  )
  $positions=@(@(42,242),@(338,242),@(634,242),@(42,364),@(338,364),@(634,364))
  for($i=0;$i -lt $objectives.Count;$i++){
    $o=$objectives[$i]; $p=$positions[$i]
    Add-Text $s $o[0] $p[0] $p[1] 30 28 20 $C.Teal $true 1 1 | Out-Null
    Add-Text $s $o[1] ($p[0]+38) $p[1] 218 24 17 $C.Navy $true 1 1 | Out-Null
    Add-Text $s $o[2] ($p[0]+38) ($p[1]+32) 218 62 14 $C.Muted $false 1 1 | Out-Null
  }
  Add-Notes $s @('README.md', 'SYSTEM_ARCHITECTURE.md sections 1, 5, 6, 8, and 10', 'test/ and supabase/tests/')

  # Slide 5 - flowchart, connectors first
  $s = $pres.Slides.Add(5, 12); Add-Title $s 'The workflow preserves continuity from discovery to follow-up' 5
  $nodes = @(
    @{x=42;y=174;w=132;h=92;t='Discover';d='Hospitals, clinicians, services, availability'},
    @{x=190;y=174;w=132;h=92;t='Guide';d='Assistant triage and emergency escalation'},
    @{x=338;y=174;w=132;h=92;t='Request';d='Guest verification or patient booking'},
    @{x=486;y=174;w=132;h=92;t='Consult';d='In person, email-assisted, or video'},
    @{x=634;y=174;w=132;h=92;t='Document';d='Checkup, prescription, and laboratory data'},
    @{x=782;y=174;w=136;h=92;t='Follow up';d='Private files, messages, and reminders'}
  )
  for($i=0;$i -lt $nodes.Count-1;$i++){ $a=$nodes[$i];$b=$nodes[$i+1];Add-Line $s ($a.x+$a.w) ($a.y+46) $b.x ($b.y+46) $C.Teal 2 $true | Out-Null }
  foreach($n in $nodes){
    Add-Box $s $n.x $n.y $n.w $n.h $C.White $C.Teal 1 | Out-Null
    Add-Text $s $n.t ($n.x+12) ($n.y+14) ($n.w-24) 24 18 $C.Navy $true 2 1 | Out-Null
    Add-Text $s $n.d ($n.x+10) ($n.y+45) ($n.w-20) 36 12 $C.Muted $false 2 1 | Out-Null
  }
  Add-Box $s 190 320 580 102 $C.Navy $C.Navy 1 | Out-Null
  Add-Text $s 'Authorization and safety remain continuous' 220 344 520 26 22 $C.White $true 2 1 | Out-Null
  Add-Text $s 'Role guards in the client; RLS, constraints, and server-side checks in the backend; preliminary AI always separated from official clinical decisions.' 228 378 504 42 14 $C.Panel $false 2 1 | Out-Null
  Add-Notes $s @('docs/defense/system_flowchart.mmd', 'SYSTEM_ARCHITECTURE.md section 6')

  # Slide 6 - scope and limits
  $s = $pres.Slides.Add(6, 12); Add-Title $s 'Scope is broad; production boundaries are explicit' 6
  Add-Text $s 'IN SCOPE' 42 132 410 20 12 $C.Teal $true 1 1 | Out-Null
  Add-Text $s 'CURRENT LIMITATIONS' 506 132 412 20 12 $C.Amber $true 1 1 | Out-Null
  Add-Line $s 480 136 480 462 $C.Line 1.2 $false | Out-Null
  $scope=@('Responsive Flutter mobile and web experiences','Public hospital and clinician discovery with maps and routes','Guest intake, patient booking, consultation, messaging, and notifications','Doctor schedules, structured clinical documentation, prescriptions, and laboratories','Hospital operations plus platform governance','Supabase Auth, RLS, Realtime, private Storage, RPCs, Edge Functions, and audit controls')
  $limits=@('Care-assistant output is preliminary guidance, not a diagnosis or prescription','External-provider behavior depends on configured Groq, SMTP, Jitsi, map, and Supabase services','Live role-to-role end-to-end tests require seeded non-production accounts and credentials','iOS/device, load, disaster-recovery, privacy, and compliance validation remain before release','Public directory screenshots show explicit unavailable states when backend configuration is absent','Current visual regression baselines require review after recent UI changes')
  $yy=172
  foreach($b in $scope){Add-BulletLine $s $b 42 $yy 390 44 $C.Ink 15;$yy+=50}
  $yy=172
  foreach($b in $limits){Add-BulletLine $s $b 506 $yy 400 44 $C.Ink 15;$yy+=50}
  Add-Notes $s @('README.md', 'SYSTEM_ARCHITECTURE.md sections 8 and 11', 'VERIFICATION_REPORT.md', 'Local flutter test run, 2026-09-02')

  # Slide 7 - architecture, connectors first
  $s = $pres.Slides.Add(7, 12); Add-Title $s 'Layers separate presentation, data access, and authority' 7
  # connectors first
  Add-Line $s 170 212 240 212 $C.Teal 2 $true | Out-Null
  Add-Line $s 398 212 468 212 $C.Teal 2 $true | Out-Null
  Add-Line $s 626 212 696 212 $C.Teal 2 $true | Out-Null
  Add-Line $s 582 298 582 352 $C.Muted 1.5 $true | Out-Null
  Add-Line $s 780 298 780 352 $C.Muted 1.5 $true | Out-Null
  $arch=@(
    @{x=42;y=164;w=128;h=96;h1='Actors';p='Five role-aware user types';f=$C.Mint;l=$C.Teal},
    @{x=240;y=164;w=158;h=96;h1='Flutter UI';p='Feature screens, shared widgets, GoRouter, Riverpod';f=$C.White;l=$C.Navy},
    @{x=468;y=164;w=158;h=96;h1='Repositories';p='Typed queries, mutations, validation, and realtime mapping';f=$C.White;l=$C.Navy},
    @{x=696;y=164;w=222;h=134;h1='Supabase';p='Auth | API and RPC | PostgreSQL plus RLS | Realtime | private Storage | Edge Functions | Cron';f=$C.Panel;l=$C.Teal},
    @{x=468;y=352;w=228;h=78;h1='Server integrations';p='Groq AI and Gmail SMTP';f=$C.AmberP;l=$C.Amber},
    @{x=714;y=352;w=204;h=78;h1='Client integrations';p='Jitsi, OpenStreetMap, OSRM';f=$C.BlueP;l=$C.Blue}
  )
  foreach($n in $arch){Add-Box $s $n.x $n.y $n.w $n.h $n.f $n.l 1 | Out-Null;Add-Text $s $n.h1 ($n.x+14) ($n.y+14) ($n.w-28) 24 18 $C.Navy $true 1 1 | Out-Null;Add-Text $s $n.p ($n.x+14) ($n.y+44) ($n.w-28) ($n.h-50) 13 $C.Muted $false 1 1 | Out-Null}
  Add-Text $s 'Public configuration stops at the client. Privileged keys and clinical authorization remain server-side.' 42 468 850 24 16 $C.Teal $true 1 1 | Out-Null
  Add-Notes $s @('docs/defense/system_architecture.mmd', 'SYSTEM_ARCHITECTURE.md sections 2 through 5')

  # Slide 8 - conceptual ERD, connectors first
  $s = $pres.Slides.Add(8, 12); Add-Title $s 'Care relationships govern clinical access' 8
  $boxes = @{
    users=@(42,150,132,54); patients=@(42,246,132,54); doctors=@(42,342,132,54)
    hospitals=@(244,150,150,54); employment=@(244,246,150,54); departments=@(244,342,150,54)
    relation=@(470,150,170,54); consult=@(470,246,170,54); chat=@(470,342,170,54)
    records=@(716,150,202,54); rx=@(716,246,202,54); labs=@(716,342,202,54)
  }
  # relationship lines before nodes
  Add-Line $s 108 204 108 246 $C.Muted 1.2 $true | Out-Null
  Add-Line $s 108 204 108 342 $C.Muted 1.2 $true | Out-Null
  Add-Line $s 174 369 244 273 $C.Muted 1.2 $true | Out-Null
  Add-Line $s 319 204 319 246 $C.Muted 1.2 $true | Out-Null
  Add-Line $s 319 204 319 342 $C.Muted 1.2 $true | Out-Null
  Add-Line $s 394 177 470 177 $C.Teal 1.5 $true | Out-Null
  Add-Line $s 174 273 470 177 $C.Teal 1.5 $true | Out-Null
  Add-Line $s 174 369 470 177 $C.Teal 1.5 $true | Out-Null
  Add-Line $s 555 204 555 246 $C.Teal 1.5 $true | Out-Null
  Add-Line $s 174 273 470 273 $C.Teal 1.5 $true | Out-Null
  Add-Line $s 174 369 470 369 $C.Teal 1.5 $true | Out-Null
  Add-Line $s 640 273 716 177 $C.Muted 1.2 $true | Out-Null
  Add-Line $s 640 273 716 273 $C.Muted 1.2 $true | Out-Null
  Add-Line $s 640 273 716 369 $C.Muted 1.2 $true | Out-Null
  $labels=@{
    users=@('users','Role, status, hospital scope'); patients=@('patients','Application patient identity'); doctors=@('doctors','Clinician identity and profile')
    hospitals=@('hospitals','Verified directory and operations'); employment=@('employments','Hospital-clinician links'); departments=@('departments','Hospital-specific care units')
    relation=@('care relationships','Purpose, scope, status, expiry'); consult=@('consultations','Schedule and lifecycle'); chat=@('chat conversations','Doctor-patient communication')
    records=@('medical records','Structured checkups and notes'); rx=@('prescriptions','Signed medication orders'); labs=@('lab requests / results','Order, upload, analysis, review')
  }
  foreach($key in $boxes.Keys){$b=$boxes[$key];$lab=$labels[$key];$fill=$(if($key -in @('relation','consult')){$C.Mint}else{$C.White});$line=$(if($key -in @('relation','consult')){$C.Teal}else{$C.Line});Add-Box $s $b[0] $b[1] $b[2] $b[3] $fill $line 1 | Out-Null;Add-Text $s $lab[0] ($b[0]+10) ($b[1]+9) ($b[2]-20) 18 14 $C.Navy $true 1 1 | Out-Null;Add-Text $s $lab[1] ($b[0]+10) ($b[1]+30) ($b[2]-20) 18 10.5 $C.Muted $false 1 1 | Out-Null}
  Add-Text $s 'Full field-level Mermaid ERD: docs/defense/database_erd.mmd' 42 454 876 22 15 $C.Teal $true 1 1 | Out-Null
  Add-Text $s 'RLS policies, grants, triggers, functions, indexes, audit logs, and private Storage policies complete the physical design.' 42 482 876 22 13 $C.Muted $false 1 1 | Out-Null
  Add-Notes $s @('docs/defense/database_erd.mmd', 'supabase/migrations/', 'lib/src/repositories/')

  # Slide 9 - security
  $s = $pres.Slides.Add(9, 12); Add-Title $s 'Security is enforced below the interface' 9
  Add-Text $s 'The UI improves usability. It is not the authorization boundary.' 42 128 870 30 20 $C.Muted $false 1 1 | Out-Null
  $layers=@(
    @('1','Role-aware routes and guarded actions','Presentation layer prevents invalid navigation and exposes clear account states',$C.Pale,$C.Line),
    @('2','Typed repository boundary','Validation, exact IDs, controlled mutations, and explicit failure handling',$C.White,$C.Line),
    @('3','JWT plus PostgreSQL Row Level Security','Patient, doctor, hospital, relationship, and action scope are checked by the backend',$C.Mint,$C.Teal),
    @('4','Private Storage and signed URLs','Clinical and identity files are never permanent public assets',$C.BlueP,$C.Blue),
    @('5','Constraints, triggers, audits, and server-only secrets','Clinical invariants and privileged operations remain observable and accountable',$C.AmberP,$C.Amber)
  )
  $yy=178
  foreach($l in $layers){Add-Box $s 42 $yy 876 56 $l[3] $l[4] 1 | Out-Null;Add-Text $s $l[0] 60 ($yy+12) 28 28 18 $C.Teal $true 2 1 | Out-Null;Add-Text $s $l[1] 102 ($yy+10) 320 22 17 $C.Navy $true 1 1 | Out-Null;Add-Text $s $l[2] 430 ($yy+10) 468 34 13 $C.Muted $false 1 1 | Out-Null;$yy+=66}
  Add-Notes $s @('SYSTEM_ARCHITECTURE.md sections 7 and 8', 'docs/MULTI_HOSPITAL_SCHEMA_AUTHORIZATION_AUDIT.md', 'supabase/migrations/')

  # Slide 10 - product evidence
  $s = $pres.Slides.Add(10, 12); Add-Title $s 'Implemented screens span care and operations' 10
  $shots=@(
    @($assistantResult,'Care assistant','Safety-aware guidance with facility context'),
    @($doctorRxWeb,'Doctor prescription workflow','Reviewable structured medication orders'),
    @($hospitalAvailabilityWeb,'Hospital operations','Connected availability and capacity controls')
  )
  $x=42
  foreach($sh in $shots){Add-Box $s $x 140 276 298 $C.Pale $C.Line 1 | Out-Null;Add-ImageFit $s $sh[0] ($x+10) 150 256 184 | Out-Null;Add-Text $s $sh[1] ($x+14) 350 248 24 17 $C.Navy $true 1 1 | Out-Null;Add-Text $s $sh[2] ($x+14) 382 248 44 13 $C.Muted $false 1 1 | Out-Null;$x+=300}
  Add-Notes $s @('tmp/carefix-result.png', 'test/failures/doctor_prescriptions_web_testImage.png', 'test/visual_catalog/hospital_availability_web.png')

  # Slide 11 - metrics
  $s = $pres.Slides.Add(11, 12); Add-Title $s 'Current build evidence is strong - but not fully green' 11
  Add-Text $s 'Verified locally on 02 September 2026' 42 126 876 20 15 $C.Muted $false 1 1 | Out-Null
  $metrics=@(
    @('0','analyzer issues',$C.Mint,$C.Green),
    @('243','tests passed',$C.BlueP,$C.Blue),
    @('11','live tests skipped',$C.Panel,$C.Muted),
    @('63','migration files',$C.AmberP,$C.Amber)
  )
  $x=42
  foreach($m in $metrics){Add-Box $s $x 170 204 132 $m[2] $m[3] 1 | Out-Null;Add-Text $s $m[0] ($x+18) 190 168 56 36 $C.Navy $true 1 3 | Out-Null;Add-Text $s $m[1] ($x+18) 250 168 24 15 $C.Muted $false 1 1 | Out-Null;$x+=224}
  Add-Box $s 42 338 876 102 $C.AmberP $C.Amber 1 | Out-Null
  Add-Text $s 'Visual regression status' 66 360 260 24 18 $C.Navy $true 1 1 | Out-Null
  Add-Text $s '8 passed  |  8 failed' 66 392 260 28 22 $C.Amber $true 1 1 | Out-Null
  Add-Text $s 'The failures are golden-image differences after recent UI changes. They require intentional review and baseline refresh - not concealment - before claiming a fully green suite.' 356 360 530 58 15 $C.Ink $false 1 1 | Out-Null
  Add-Notes $s @('Local command: flutter analyze (no issues), 2026-09-02', 'Local command: flutter test (243 passed, 11 skipped, 8 failed), 2026-09-02', 'supabase/migrations/ directory count')

  # Slide 12 - progress timeline
  $s = $pres.Slides.Add(12, 12); Add-Title $s 'Progress moved from foundation to integrated care' 12
  Add-Line $s 104 380 856 380 $C.Navy 1.5 $false | Out-Null
  $milestones=@(
    @{x=62;date='09 AUG';title='Foundation verified';body='Flutter architecture, role routing, live Supabase contract, public discovery, auth, and initial workspaces.';fill=$C.Pale},
    @{x=346;date='23-26 AUG';title='Care workflow expansion';body='Multi-hospital authorization, online requests, patient linking, structured prescriptions and diagnostics, persistent messaging, reminders.';fill=$C.Mint},
    @{x=630;date='02 SEP';title='Current defense state';body='Care assistant integration, 63 migrations, clean static analysis, broad automated coverage, and identified golden-test drift.';fill=$C.BlueP}
  )
  foreach($m in $milestones){Add-Box $s $m.x 160 266 186 $m.fill $C.Line 1 | Out-Null;Add-Text $s $m.date ($m.x+18) 180 220 20 12 $C.Teal $true 1 1 | Out-Null;Add-Text $s $m.title ($m.x+18) 216 230 32 20 $C.Navy $true 1 1 | Out-Null;Add-Text $s $m.body ($m.x+18) 258 230 72 14 $C.Muted $false 1 1 | Out-Null;$dot=$s.Shapes.AddShape(9,($m.x+124),372,16,16);$dot.Fill.ForeColor.RGB=$C.Teal;$dot.Line.Visible=0}
  Add-Text $s 'Current state: a functioning integrated prototype with verified strengths and explicit gaps.' 120 430 720 34 18 $C.Navy $true 2 1 | Out-Null
  Add-Notes $s @('git log through 5bd0866', 'PRE_BUILD_REPORT.md', 'supabase/migrations/', 'Local verification on 2026-09-02')

  # Slide 13 - next steps
  $s = $pres.Slides.Add(13, 12); Add-Title $s 'Four actions remain before production' 13
  $next=@(
    @('01','Review visual drift','Confirm intended UI changes, then update only approved golden baselines.'),
    @('02','Run live role journeys','Use seeded non-production accounts for patient-to-doctor-to-admin end-to-end tests.'),
    @('03','Validate providers and devices','Exercise Groq, SMTP, Jitsi, scheduled jobs, Android hardware, and iOS/macOS builds.'),
    @('04','Formalize operations and compliance','Complete privacy/security review, monitoring, load tests, backups, retention, recovery, and key rotation.')
  )
  $yy=144
  foreach($n in $next){Add-Text $s $n[0] 48 $yy 48 40 26 $C.Teal $true 1 1 | Out-Null;Add-Text $s $n[1] 116 $yy 276 30 20 $C.Navy $true 1 1 | Out-Null;Add-Text $s $n[2] 410 $yy 500 48 15 $C.Muted $false 1 1 | Out-Null;if($yy -lt 400){Add-Line $s 116 ($yy+62) 910 ($yy+62) $C.Line 1 $false | Out-Null};$yy+=84}
  Add-Notes $s @('SYSTEM_ARCHITECTURE.md section 11', 'VERIFICATION_REPORT.md remaining production verification', 'Local visual regression run 2026-09-02')

  # Slide 14 - conclusion
  $s = $pres.Slides.Add(14, 12)
  Add-Box $s 0 0 960 540 $C.Navy $C.Navy 0 'closing-background' | Out-Null
  Add-Text $s 'DEFENSE CONCLUSION' 48 46 300 18 11 $C.Teal2 $true 1 1 | Out-Null
  Add-Text $s 'CareNavigator PH demonstrates a viable, secure path from finding care to managing care.' 48 96 824 126 42 $C.White $true 1 1 'closing-title' | Out-Null
  Add-Text $s 'The prototype is defensible because its value, architecture, authorization boundaries, database relationships, implemented workflows, and remaining risks are all visible and testable.' 48 250 824 74 20 $C.Panel $false 1 1 | Out-Null
  Add-Box $s 48 372 824 84 $C.White $C.White 1 | Out-Null
  Add-Text $s 'Panel decision requested' 72 394 230 22 16 $C.Teal $true 1 1 | Out-Null
  Add-Text $s 'Approve continued development toward live end-to-end validation and production-readiness controls.' 320 388 520 40 20 $C.Navy $true 1 1 | Out-Null
  Add-Text $s 'CareNavigator PH  |  System Defense  |  02 September 2026' 48 496 824 18 11 $C.Teal2 $false 1 1 | Out-Null
  Add-Notes $s @('README.md', 'SYSTEM_ARCHITECTURE.md', 'Local repository and verification evidence reviewed 2026-09-02')

  $pres.SaveAs($pptxPath, 24)
  $pres.Export($slidePngDir, 'PNG', 1600, 900)
  $pres.SaveAs($pdfPath, 32)
}
finally {
  if ($pres -ne $null) { $pres.Close() }
  if ($ppt -ne $null) { $ppt.Quit() }
  [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
}

# Build the Word report using the standard_business_brief preset.
function Add-WordParagraph($doc, [string]$text, [string]$style='Normal', [bool]$keep=$false) {
  $p = $doc.Paragraphs.Add()
  $p.Range.Text = $text
  try { $p.Style = $style } catch {}
  $p.Format.KeepWithNext = $(if($keep){-1}else{0})
  $p.Range.InsertParagraphAfter()
  return $p
}

function Add-WordBullet($doc, [string]$text) {
  $p = Add-WordParagraph $doc $text 'Normal'
  $p.Range.ListFormat.ApplyBulletDefault()
  $p.Format.LeftIndent = 36
  $p.Format.FirstLineIndent = -18
  $p.Format.SpaceAfter = 6
  return $p
}

function Add-WordTable($doc, [object[]]$rows, [double[]]$widths) {
  $range = $doc.Range($doc.Content.End-1, $doc.Content.End-1)
  $table = $doc.Tables.Add($range, $rows.Count, $rows[0].Count)
  $table.AllowAutoFit = $false
  $table.Borders.Enable = 1
  $table.Range.Font.Name = 'Calibri'
  $table.Range.Font.Size = 9.5
  for($c=1;$c -le $widths.Count;$c++){ $table.Columns.Item($c).Width = $widths[$c-1] }
  for($r=1;$r -le $rows.Count;$r++){
    for($c=1;$c -le $rows[$r-1].Count;$c++){
      $cell=$table.Cell($r,$c)
      $cell.Range.Text=[string]$rows[$r-1][$c-1]
      $cell.VerticalAlignment=0
      $cell.Range.ParagraphFormat.SpaceAfter=3
      if($r -eq 1){ try {$cell.Range.Font.Bold=-1;$cell.Range.Font.Color=$C.Navy} catch {} }
    }
  }
  try { $table.Rows.Item(1).Range.Shading.BackgroundPatternColor=$C.Panel } catch {}
  $doc.Range($doc.Content.End-1,$doc.Content.End-1).InsertParagraphAfter()
  return $table
}

function Add-WordFigure($doc, [string]$path, [string]$caption, [double]$width=468) {
  $p=$doc.Paragraphs.Add();$p.Alignment=1
  $pic=$p.Range.InlineShapes.AddPicture($path)
  $pic.LockAspectRatio=-1
  $pic.Width=$width
  $p.Range.InsertParagraphAfter()
  $cp=Add-WordParagraph $doc $caption 'Caption'
  $cp.Alignment=1
  $cp.Range.Font.Italic=-1
  $cp.Range.Font.Color=$C.Muted
}

$word=$null
$doc=$null
if (-not $SkipWord) {
try {
  $word=New-Object -ComObject Word.Application
  $word.Visible=$false
  $word.ScreenUpdating=$false
  try { $word.Options.Pagination=$false } catch {}
  $doc=$word.Documents.Add()
  $sec=$doc.Sections.Item(1)
  $sec.PageSetup.PageWidth=612
  $sec.PageSetup.PageHeight=792
  $sec.PageSetup.TopMargin=72
  $sec.PageSetup.BottomMargin=72
  $sec.PageSetup.LeftMargin=72
  $sec.PageSetup.RightMargin=72
  $sec.PageSetup.HeaderDistance=35.424
  $sec.PageSetup.FooterDistance=35.424

  $normal=$doc.Styles.Item('Normal')
  $normal.Font.Name='Calibri';$normal.Font.Size=11;$normal.Font.Color=$C.Ink
  $normal.ParagraphFormat.SpaceBefore=0;$normal.ParagraphFormat.SpaceAfter=6
  $normal.ParagraphFormat.LineSpacingRule=5;$normal.ParagraphFormat.LineSpacing=13.2
  $h1=$doc.Styles.Item('Heading 1');$h1.Font.Name='Calibri';$h1.Font.Size=16;$h1.Font.Bold=-1;$h1.Font.Color=$C.Blue;$h1.ParagraphFormat.SpaceBefore=16;$h1.ParagraphFormat.SpaceAfter=8;$h1.ParagraphFormat.KeepWithNext=-1
  $h2=$doc.Styles.Item('Heading 2');$h2.Font.Name='Calibri';$h2.Font.Size=13;$h2.Font.Bold=-1;$h2.Font.Color=$C.Blue;$h2.ParagraphFormat.SpaceBefore=12;$h2.ParagraphFormat.SpaceAfter=6;$h2.ParagraphFormat.KeepWithNext=-1
  $h3=$doc.Styles.Item('Heading 3');$h3.Font.Name='Calibri';$h3.Font.Size=12;$h3.Font.Bold=-1;$h3.Font.Color=$C.Navy;$h3.ParagraphFormat.SpaceBefore=8;$h3.ParagraphFormat.SpaceAfter=4;$h3.ParagraphFormat.KeepWithNext=-1

  # Header and footer
  $hdr=$sec.Headers.Item(1).Range
  $hdr.Text='CareNavigator PH  |  Project Defense Documentation'
  $hdr.Font.Name='Calibri';$hdr.Font.Size=9;$hdr.Font.Color=$C.Muted
  $hdr.ParagraphFormat.Borders.Item(-3).LineStyle=1
  $hdr.ParagraphFormat.Borders.Item(-3).Color=$C.Line
  $ftr=$sec.Footers.Item(1).Range
  $ftr.ParagraphFormat.Alignment=2
  $ftr.Font.Name='Calibri';$ftr.Font.Size=9;$ftr.Font.Color=$C.Muted
  $ftr.Text='CareNavigator PH  |  '
  $ftr.Collapse(0)
  $ftr.Fields.Add($ftr,-1,'PAGE',$false) | Out-Null

  # Cover
  $p=$doc.Paragraphs.Add();$p.Alignment=1
  $pic=$p.Range.InlineShapes.AddPicture($appIcon);$pic.LockAspectRatio=-1;$pic.Width=90
  $p.Range.InsertParagraphAfter()
  $p=Add-WordParagraph $doc 'CareNavigator PH' 'Normal';$p.Alignment=1;$p.Range.Font.Size=28;$p.Range.Font.Bold=-1;$p.Range.Font.Color=$C.Navy;$p.Format.SpaceBefore=20;$p.Format.SpaceAfter=8
  $p=Add-WordParagraph $doc 'System Defense and Project Documentation' 'Normal';$p.Alignment=1;$p.Range.Font.Size=18;$p.Range.Font.Bold=-1;$p.Range.Font.Color=$C.Teal;$p.Format.SpaceAfter=24
  $p=Add-WordParagraph $doc 'A role-aware healthcare navigation and digital care platform for the Philippines' 'Normal';$p.Alignment=1;$p.Range.Font.Size=13;$p.Range.Font.Color=$C.Muted;$p.Format.SpaceAfter=36
  $meta=@(
    @('Project title','CareNavigator PH'),
    @('Prepared for','System / project defense'),
    @('Proponents','[Insert names]'),
    @('Adviser / Panel','[Insert name or panel]'),
    @('Date','02 September 2026')
  )
  Add-WordTable $doc $meta @((Pt 1.55),(Pt 4.95)) | Out-Null
  $p=Add-WordParagraph $doc 'Document status: defense-ready working draft based on the current repository implementation and local verification.' 'Normal';$p.Alignment=1;$p.Range.Font.Italic=-1;$p.Range.Font.Color=$C.Muted;$p.Format.SpaceBefore=24
  $doc.Range($doc.Content.End-1,$doc.Content.End-1).InsertBreak(7)

  # TOC
  Add-WordParagraph $doc 'Contents' 'Heading 1' | Out-Null
  foreach($entry in @(
    'Executive Summary',
    '1. Project Title and Description',
    '2. Project Objectives Defined',
    '3. Scope and Limitations Identified',
    '4. Updated System Flowchart and Architecture Diagram',
    '5. Database Design (ERD / Schema)',
    '6. Project Progress Report (Current Accomplishments)',
    '7. Defense Conclusion',
    'Appendix A. Source-of-Truth Locations'
  )){ Add-WordParagraph $doc $entry 'Normal' | Out-Null }
  $doc.Range($doc.Content.End-1,$doc.Content.End-1).InsertBreak(7)

  Add-WordParagraph $doc 'Executive Summary' 'Heading 1' | Out-Null
  Add-WordParagraph $doc 'CareNavigator PH is a Flutter mobile-and-web healthcare-navigation and digital-care platform. It unifies verified hospital and clinician discovery, safety-aware care guidance, guest consultation intake, authenticated patient and doctor workflows, hospital operations, and platform governance in one role-aware system backed by Supabase.' | Out-Null
  Add-WordParagraph $doc 'The current prototype demonstrates an end-to-end care pathway and a deliberate security model: UI guards support usability, typed repositories isolate data access, while JWT validation, Row Level Security, private Storage, constraints, triggers, and server-side authorization enforce access. The project is functionally substantial, but it is not represented as production-ready; live credentialed journeys, provider/device validation, formal compliance work, and visual-baseline review remain.' | Out-Null

  Add-WordParagraph $doc '1. Project Title and Description' 'Heading 1' | Out-Null
  Add-WordParagraph $doc 'Project Title' 'Heading 2' | Out-Null
  Add-WordParagraph $doc 'CareNavigator PH: A Role-Aware Healthcare Navigation and Digital Care Platform' | Out-Null
  Add-WordParagraph $doc 'Project Description' 'Heading 2' | Out-Null
  Add-WordParagraph $doc 'CareNavigator PH helps users find an appropriate healthcare facility and continue through consultation, clinical documentation, communication, and follow-up without losing context. Guests can discover verified care and submit a protected consultation request. Patients can book and manage care, communicate with clinicians, and access authorized records. Doctors can manage schedules, consultations, structured checkups, prescriptions, laboratories, and review workflows. Hospital administrators operate assigned facilities, while super administrators manage platform governance.' | Out-Null
  Add-WordParagraph $doc 'The application uses one adaptive Flutter codebase. GoRouter manages deep links and role-based routing, Riverpod manages state and Realtime streams, typed Dart repositories form the data-access boundary, and Supabase provides Auth, PostgreSQL, RLS, Realtime, private Storage, RPCs, Edge Functions, triggers, and scheduled jobs. External integrations include Groq, Gmail SMTP, Jitsi, OpenStreetMap, and OSRM.' | Out-Null

  Add-WordParagraph $doc '2. Project Objectives Defined' 'Heading 1' | Out-Null
  Add-WordParagraph $doc 'General Objective' 'Heading 2' | Out-Null
  Add-WordParagraph $doc 'To design and implement a secure, responsive, role-aware healthcare platform that helps people discover appropriate care and supports the care lifecycle across authorized guests, patients, clinicians, hospital personnel, and platform administrators.' | Out-Null
  Add-WordParagraph $doc 'Specific Objectives' 'Heading 2' | Out-Null
  foreach($b in @(
    'Provide searchable, verified hospital, service, clinician, schedule, availability, map, and route information.',
    'Provide safety-aware preliminary guidance that detects emergency signals and directs users to appropriate care without presenting AI output as a diagnosis.',
    'Connect guest consultation intake, verification, registered-patient booking, consultation, messaging, document processing, and follow-up.',
    'Provide role-specific workspaces and actions for patients, doctors, hospital administrators, and super administrators.',
    'Protect clinical and identity data through backend-enforced authorization, private file storage, short-lived access, clinical invariants, and auditing.',
    'Support maintainability through a layered architecture, typed models and repositories, centralized design components, migrations, and automated tests.',
    'Provide evidence-based project reporting that distinguishes implemented work from remaining production validation.'
  )){Add-WordBullet $doc $b | Out-Null}

  Add-WordParagraph $doc '3. Scope and Limitations Identified' 'Heading 1' | Out-Null
  Add-WordParagraph $doc 'Scope' 'Heading 2' | Out-Null
  $scopeRows=@(
    @('Area','Included capabilities'),
    @('Public access','Hospital and clinician discovery, maps/routes, assistant guidance, guest consultation request and verification'),
    @('Patient care','Booking, rescheduling/cancellation, consultations, messages, notifications, records, prescriptions, diagnostics, files, profile and preferences'),
    @('Doctor care','Patient relationships, scheduling, consultation lifecycle, structured notes/checkups, prescriptions, laboratory requests/results, document review'),
    @('Hospital operations','Appointments, staff, departments, services, facilities, beds/capacity, emergency-room status, reports and audit views'),
    @('Platform governance','Hospital approval, accounts, permissions, settings, analytics, security, maintenance and audit'),
    @('Technical platform','Flutter, GoRouter, Riverpod, typed repositories, Supabase Auth/PostgreSQL/RLS/Realtime/Storage/RPC/Edge Functions/Cron'),
    @('External integration','Groq AI, Gmail SMTP, Jitsi, OpenStreetMap and OSRM')
  )
  Add-WordTable $doc $scopeRows @((Pt 1.55),(Pt 4.95)) | Out-Null
  Add-WordParagraph $doc 'Limitations' 'Heading 2' | Out-Null
  foreach($b in @(
    'Care-assistant and document-analysis outputs remain preliminary and must not be treated as a diagnosis, prescription, or replacement for professional care.',
    'External services require configured credentials, network access, and provider availability; those production side effects were not triggered for this defense document.',
    'The ordinary local test run skipped credential-dependent live Supabase journeys because live test variables and demo passwords were not supplied.',
    'The project still needs physical Android tests, an iOS/macOS build-and-device pass, load testing, backup/recovery drills, production monitoring, key rotation, and a formal privacy/security/compliance assessment.',
    'When public Supabase configuration is absent, the interface intentionally shows explicit unavailable states instead of fabricated hospital or clinical data.',
    'Eight visual regression cases currently differ from their approved golden images and require an intentional UI review and baseline decision.'
  )){Add-WordBullet $doc $b | Out-Null}

  $doc.Range($doc.Content.End-1,$doc.Content.End-1).InsertBreak(7)
  Add-WordParagraph $doc '4. Updated System Flowchart and Architecture Diagram' 'Heading 1' | Out-Null
  Add-WordParagraph $doc 'End-to-End System Flow' 'Heading 2' | Out-Null
  Add-WordFigure $doc (Join-Path $slidePngDir 'Slide5.PNG') 'Figure 1. Core CareNavigator PH workflow from discovery through protected follow-up.'
  Add-WordParagraph $doc 'The flow preserves user and clinical context across discovery, guidance, consultation entry, scheduling, care delivery, documentation, and follow-up. At every transition, the system separates usability controls in Flutter from authoritative policy and data checks in Supabase.' | Out-Null
  Add-WordParagraph $doc 'Logical Architecture' 'Heading 2' | Out-Null
  Add-WordFigure $doc (Join-Path $slidePngDir 'Slide7.PNG') 'Figure 2. Layered client, repository, Supabase, and external-service architecture.'
  Add-WordParagraph $doc 'Editable Mermaid sources for VS Code are provided in docs/defense/system_flowchart.mmd and docs/defense/system_architecture.mmd. The companion docs/defense/CareNavigator_PH_Diagrams.md supports Markdown Preview with a Mermaid extension.' | Out-Null

  $doc.Range($doc.Content.End-1,$doc.Content.End-1).InsertBreak(7)
  Add-WordParagraph $doc '5. Database Design (ERD / Schema)' 'Heading 1' | Out-Null
  Add-WordFigure $doc (Join-Path $slidePngDir 'Slide8.PNG') 'Figure 3. Defense-oriented conceptual ERD emphasizing identity, hospital, care-relationship, consultation, communication, and clinical-record domains.'
  Add-WordParagraph $doc 'The central design decision is to model care authorization as an explicit relationship among the patient, hospital, doctor, consultation, purpose, scope, status, and time boundary. This prevents a role label alone from granting broad clinical access. Multi-hospital identifiers and doctor employments preserve facility-specific context, while consultations produce structured records, prescriptions, laboratory orders/results, messages, documents, notifications, and audit evidence.' | Out-Null
  Add-WordParagraph $doc 'Database Design Principles' 'Heading 2' | Out-Null
  foreach($b in @(
    'Use UUID primary and foreign keys for authoritative entities and exact-ID actions.',
    'Use foreign keys, uniqueness constraints, check constraints, and clinical lifecycle triggers to preserve invariants.',
    'Enable Row Level Security for client-accessible tables and enforce patient, doctor, hospital, relationship, and action scope.',
    'Store sensitive clinical and identity documents in private buckets; issue short-lived signed URLs only after authorization.',
    'Use RPCs and Edge Functions for privileged, transactional, provider-facing, and auditable workflows.',
    'Use indexes for relationship lookups, status queues, schedules, recent activity, and conversation history.',
    'Preserve observability through status history, audit/security logs, processing jobs, and notification outboxes.'
  )){Add-WordBullet $doc $b | Out-Null}
  Add-WordParagraph $doc 'Mermaid ERD Source' 'Heading 2' | Out-Null
  Add-WordParagraph $doc 'Open docs/defense/database_erd.mmd in VS Code with a Mermaid extension. The file includes the main field-level entities and relationships used in the defense; the full physical schema remains defined by the Supabase database and the 63 migration files under supabase/migrations/.' | Out-Null

  Add-WordParagraph $doc '6. Project Progress Report (Current Accomplishments)' 'Heading 1' | Out-Null
  Add-WordParagraph $doc 'Progress Snapshot' 'Heading 2' | Out-Null
  $progress=@(
    @('Workstream','Status','Current evidence','Remaining work'),
    @('Architecture and UI foundation','Implemented','Adaptive Flutter shells; centralized theme/widgets; GoRouter; Riverpod; typed repositories','Continue accessibility/device validation'),
    @('Public discovery and guest access','Implemented','Hospitals, clinicians, map/routing, assistant, request/verification flows, explicit unavailable states','Live provider and credentialed browser journeys'),
    @('Patient and doctor care','Implemented','Booking, scheduling, consultation lifecycle, messaging, documents, checkups, prescriptions, diagnostics and labs','Live multi-role acceptance pass'),
    @('Hospital and platform administration','Implemented','Hospital operations, staff/services/departments, capacity/ER, approvals, accounts, permissions, settings, maintenance and audits','Operational runbooks and production monitoring'),
    @('Security and data model','Implemented with further review required','RLS-oriented access, private Storage, multi-hospital grants, constraints, triggers, RPCs and audit patterns','Independent security/privacy/compliance review'),
    @('Quality verification','Partially complete','Static analysis clean; 243 tests passed; 11 credentialed tests skipped; 8 golden tests passed and 8 differed','Review visual changes; rerun live and device suites')
  )
  Add-WordTable $doc $progress @((Pt 1.22),(Pt 0.82),(Pt 2.18),(Pt 2.28)) | Out-Null

  Add-WordParagraph $doc 'Current Accomplishments' 'Heading 2' | Out-Null
  foreach($b in @(
    'Implemented one responsive Flutter application for web and mobile with public, patient, doctor, hospital-administrator, and super-administrator experiences.',
    'Established a repository-only Supabase boundary and role-aware routing/state architecture.',
    'Implemented public hospital and clinician discovery, OpenStreetMap/OSRM routing, guest intake, account flows, and explicit unavailable states.',
    'Implemented booking and consultation lifecycle workflows, secure Jitsi room access, Realtime messaging/notifications, and private file handling.',
    'Implemented structured checkups, prescriptions, diagnostic result extraction, laboratory requests/results, review states, and medication reminder workflows.',
    'Added multi-hospital identities, clinician employment, patient care relationships, grants/scopes, online consultation requests, and cross-source authorization.',
    'Added persistent patient conversations and persistent care-assistant conversation history.',
    'Added a care-navigator-chat Edge Function for safety-aware conversation, document extraction, hospital recommendation, and email-related workflows.',
    'Accumulated 63 focused Supabase migration files and seven SQL acceptance-test scripts in the repository.',
    'Verified the current code with flutter analyze: no issues found.'
  )){Add-WordBullet $doc $b | Out-Null}

  Add-WordParagraph $doc 'Latest Verification Results' 'Heading 2' | Out-Null
  $verify=@(
    @('Check','Result','Defense interpretation'),
    @('flutter analyze','PASS - no issues','Static analysis is clean on the current repository state.'),
    @('flutter test','243 passed; 11 skipped; 8 failed','Functional coverage is broad. Skips require live credentials. Failures are visual-golden differences.'),
    @('Visual regression subset','8 passed; 8 failed','Hospital-admin and super-admin baselines passed; guest, patient, doctor, and prescription views require review.'),
    @('Repository inventory','60 Dart implementation files; 39 Dart test files; 63 migration files; 7 SQL test files','The prototype has substantial breadth, but file counts are not substitutes for live acceptance.'),
    @('Previous documented builds','Web release and Android debug passed in the August verification record','These are historical evidence and should be rerun before release.')
  )
  Add-WordTable $doc $verify @((Pt 1.35),(Pt 1.45),(Pt 3.70)) | Out-Null

  Add-WordParagraph $doc 'Immediate Next Steps' 'Heading 2' | Out-Null
  foreach($b in @(
    'Review the eight visual diffs and approve or reject the corresponding UI changes before refreshing baselines.',
    'Run seeded, non-production patient, doctor, hospital-admin, and super-admin journeys with live Supabase configuration.',
    'Exercise Groq, SMTP, Jitsi, scheduled notification dispatch, private-file access, and mobile permissions in controlled environments.',
    'Run physical Android and iOS tests, browser console/interaction verification, load tests, and accessibility checks.',
    'Complete privacy, security, compliance, retention, backup, recovery, observability, incident-response, and key-rotation procedures.'
  )){Add-WordBullet $doc $b | Out-Null}

  Add-WordParagraph $doc '7. Defense Conclusion' 'Heading 1' | Out-Null
  Add-WordParagraph $doc 'CareNavigator PH is a defensible integrated prototype: it addresses a clear healthcare-navigation problem, defines measurable objectives, covers the principal care and governance workflows, separates interface behavior from backend authority, and provides concrete implementation and test evidence. Its strongest architectural claim is not that one role can see everything, but that access is derived from verified identity, hospital context, care relationship, clinical purpose, and permitted action.' | Out-Null
  Add-WordParagraph $doc 'The recommended defense position is to approve continued development toward live end-to-end validation and production-readiness controls. The remaining gaps are documented as engineering and governance work—not hidden as completed functionality.' | Out-Null

  Add-WordParagraph $doc 'Appendix A. Source-of-Truth Locations' 'Heading 1' | Out-Null
  $sources=@(
    @('Area','Repository location'),
    @('Application entry and bootstrap','lib/main.dart; lib/bootstrap.dart'),
    @('Routing and role guards','lib/src/routing/app_router.dart'),
    @('State and providers','lib/src/providers/'),
    @('Repository boundary','lib/src/repositories/'),
    @('Domain models','lib/src/models/'),
    @('Shared UI and theme','lib/src/widgets/; lib/src/theme/'),
    @('Database migrations','supabase/migrations/'),
    @('Edge Function','supabase/functions/care-navigator-chat/'),
    @('Flutter and SQL tests','test/; supabase/tests/'),
    @('Mermaid diagrams','docs/defense/*.mmd; docs/defense/CareNavigator_PH_Diagrams.md'),
    @('Architecture and verification records','SYSTEM_ARCHITECTURE.md; README.md; PRE_BUILD_REPORT.md; VERIFICATION_REPORT.md')
  )
  Add-WordTable $doc $sources @((Pt 2.1),(Pt 4.4)) | Out-Null
  Add-WordParagraph $doc 'Verification date: 02 September 2026 (Asia/Manila). Counts and test results reflect the local repository state reviewed for this document. Team and adviser metadata remain placeholders because they were not present in the repository.' | Out-Null

  try { $word.Options.Pagination=$true } catch {}
  $doc.SaveAs2($docxPath,16)
  $doc.ExportAsFixedFormat($docQaPdf,17)
}
finally {
  if($doc -ne $null){$doc.Close(0)}
  if($word -ne $null){$word.Quit()}
  [GC]::Collect();[GC]::WaitForPendingFinalizers()
}
}

$outputs=@($pptxPath,$pdfPath)
if(-not $SkipWord){$outputs+=@($docxPath,$docQaPdf)}
Get-Item $outputs -ErrorAction SilentlyContinue | Select-Object FullName,Length
