$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$outDir=Join-Path $PSScriptRoot 'diagrams'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$script:ink=[System.Drawing.ColorTranslator]::FromHtml('#152D43')
$script:line=[System.Drawing.ColorTranslator]::FromHtml('#748491')
$script:fill=[System.Drawing.ColorTranslator]::FromHtml('#F2F6F9')
function BeginDiagram([int]$width,[int]$height) {
  $script:bitmap=[System.Drawing.Bitmap]::new($width,$height)
  $script:g=[System.Drawing.Graphics]::FromImage($bitmap)
  $g.Clear([System.Drawing.Color]::White)
  $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint=[System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  $script:pen=[System.Drawing.Pen]::new($line,2)
}
function Text([string]$text,[single]$x,[single]$y,[single]$w,[single]$h,[int]$size=28,[bool]$bold=$false,[bool]$center=$true) {
  $font=[System.Drawing.Font]::new('Arial',$size,$(if($bold){[System.Drawing.FontStyle]::Bold}else{[System.Drawing.FontStyle]::Regular}),[System.Drawing.GraphicsUnit]::Pixel)
  $format=[System.Drawing.StringFormat]::new()
  $format.Alignment=$(if($center){[System.Drawing.StringAlignment]::Center}else{[System.Drawing.StringAlignment]::Near})
  $format.LineAlignment=[System.Drawing.StringAlignment]::Center
  $brush=[System.Drawing.SolidBrush]::new($ink)
  $g.DrawString($text,$font,$brush,[System.Drawing.RectangleF]::new($x,$y,$w,$h),$format)
  $brush.Dispose();$format.Dispose();$font.Dispose()
}
function Box([string]$text,[single]$x,[single]$y,[single]$w,[single]$h,[bool]$ellipse=$false,[int]$size=28) {
  $brush=[System.Drawing.SolidBrush]::new($fill)
  if($ellipse){$g.FillEllipse($brush,$x,$y,$w,$h);$g.DrawEllipse($pen,$x,$y,$w,$h)}
  else{$g.FillRectangle($brush,$x,$y,$w,$h);$g.DrawRectangle($pen,$x,$y,$w,$h)}
  Text $text ($x+14) ($y+8) ($w-28) ($h-16) $size
  $brush.Dispose()
}
function Arrow([single]$x1,[single]$y1,[single]$x2,[single]$y2) {
  $arrowPen=[System.Drawing.Pen]::new($line,3)
  $arrowPen.CustomEndCap=[System.Drawing.Drawing2D.AdjustableArrowCap]::new(5,7,$true)
  $g.DrawLine($arrowPen,$x1,$y1,$x2,$y2)
  $arrowPen.Dispose()
}
function SaveDiagram([string]$name) {
  $bitmap.Save((Join-Path $outDir ($name+'.png')),[System.Drawing.Imaging.ImageFormat]::Png)
  $pen.Dispose();$g.Dispose();$bitmap.Dispose()
}
BeginDiagram 1200 820
Box "Guest    Patient    Doctor    Hospital administrator    Super administrator" 40 20 1120 80 $false 26
Arrow 600 100 600 142
Box "Flutter mobile and web client`nScreens and shared widgets  |  GoRouter  |  Riverpod" 150 142 900 110
Arrow 600 252 600 292
Box "Typed Dart repositories`nQueries  |  Transactional RPCs  |  Private file operations" 150 292 900 105
Arrow 600 397 600 442
Box "Supabase Auth and PostgreSQL`nOwnership checks  |  Hospital boundaries  |  RLS  |  Transaction locks" 40 442 1120 115
Arrow 235 557 235 603
Arrow 600 557 600 603
Arrow 970 557 970 603
Box "Private Storage`nClinical attachments" 40 603 360 100
Box "Realtime`nMessages and updates" 420 603 360 100
Box "Six Edge Functions`nAI and outbox delivery" 800 603 360 100
Text "External services: Groq AI, SMTP email, Jitsi video, OpenStreetMap and OSRM" 40 735 1120 60 25
SaveDiagram 'architecture'
BeginDiagram 1200 930
Box "Guest`nBrowse directory and verify email" 40 20 520 90
Box "Registered patient`nSign in and choose available clinician" 640 20 520 90
Arrow 300 110 300 165
Arrow 900 110 900 165
Box "Submit intake with a reusable`nsubmission key and verified identity" 40 165 520 100
Box "Submit online request`nPreferred slot is not reserved" 640 165 520 100
Arrow 300 265 490 335
Arrow 900 265 710 335
Box "Hospital review`nStart review, check eligibility and availability" 250 335 700 100
Arrow 250 385 125 385
Arrow 950 385 1075 385
Box "Information or`nschedule proposal`nPatient responds" 10 465 270 130 $false 26
Box "Reject or cancel`nClose request with`nrecorded reason" 920 465 270 130 $false 26
Arrow 125 385 125 465
Arrow 1075 385 1075 465
Arrow 600 435 600 510
Box "Confirmation transaction`nRecheck slot, create official consultation and access" 320 510 560 115 $false 26
Arrow 600 625 600 680
Box "Online visit`nPrepare room, record contact, assigned doctor starts" 250 680 700 105
Arrow 600 785 600 835
Box "Structured checkup and terminal outcome`nSynchronize status, close room, revoke access and notify" 120 835 960 85 $false 26
SaveDiagram 'workflow'
BeginDiagram 1200 1060
$g.DrawRectangle($pen,270,20,890,1020)
Text 'CareNavigator PH' 280 27 870 55 32 $true
$actors=@('Guest','Patient','Doctor','Hospital administrator','Super administrator')
$cases=@(
  @("Discover hospitals`nand emergency guidance","Verify email and`ntrack guest request"),
  @("Book and track care`nRespond to review","Upload supporting files`nManage sharing and preferences"),
  @("Review assigned records`nConduct structured checkup","Issue signed prescriptions`nManage clinical follow-up"),
  @("Review and confirm`nonline requests","Manage staff, services`nschedules and ER capacity"),
  @("Verify hospitals and`nmanage platform accounts","Review audit, security`nmaintenance and delivery")
)
for($row=0;$row -lt 5;$row++) {
  $rowY=110+$row*180
  $actorX=115
  $g.DrawEllipse($pen,($actorX-18),$rowY,36,36)
  $g.DrawLine($pen,$actorX,($rowY+36),$actorX,($rowY+96))
  $g.DrawLine($pen,($actorX-36),($rowY+62),($actorX+36),($rowY+62))
  $g.DrawLine($pen,$actorX,($rowY+96),($actorX-32),($rowY+133))
  $g.DrawLine($pen,$actorX,($rowY+96),($actorX+32),($rowY+133))
  Text $actors[$row] 10 ($rowY+137) 245 40 23 $true
  Box $cases[$row][0] 315 ($rowY+10) 365 125 $true 25
  Box $cases[$row][1] 755 ($rowY+10) 365 125 $true 25
  $g.DrawLine($pen,160,($rowY+72),315,($rowY+72))
  $g.DrawLine($pen,160,($rowY+72),245,($rowY+8))
  $g.DrawLine($pen,245,($rowY+8),750,($rowY+8))
  $g.DrawLine($pen,750,($rowY+8),770,($rowY+28))
}
SaveDiagram 'use_cases'
BeginDiagram 1200 865
function Entity([string]$title,[string]$fields,[int]$x,[int]$y) {
  Box '' $x $y 475 200
  Text $title ($x+10) ($y+8) 455 50 29 $true
  $g.DrawLine($pen,($x+15),($y+64),($x+460),($y+64))
  Text $fields ($x+22) ($y+75) 430 110 24 $false $false
}
Entity 'users' "PK id`nUK auth_user_id`nFK role_id   |   account_status" 45 20
Entity 'patients' "PK id`nFK user_id`nFK primary_hospital_id" 680 20
Entity 'doctors' "PK id`nFK user_id`nFK hospital_id" 45 320
Entity 'consultations' "PK id`nFK patient_id, doctor_id, hospital_id`nappointment_date   |   status" 680 320
Entity 'prescription_orders' "PK id`nFK patient_id, doctor_id`nFK consultation_id   |   idempotency_key" 45 630
Entity 'prescriptions' "PK id`nFK order_id`nmedication_name   |   exact_dose" 680 630
Arrow 520 115 680 115
Text '1 to 0 or 1' 525 55 150 40 22
Arrow 282 220 282 320
Text '1 to 0 or 1' 70 248 390 40 22
Arrow 917 220 917 320
Text '1 to many' 730 248 390 40 22
Arrow 520 415 680 415
Text '1 to many' 525 350 150 40 22
Arrow 720 520 460 630
Text '0 or 1 to many' 270 548 270 42 22
Arrow 520 728 680 728
Text '1 to many' 525 665 150 40 22
SaveDiagram 'erd_core'
Write-Output 'Created architecture, workflow, use case and core ERD diagrams'
