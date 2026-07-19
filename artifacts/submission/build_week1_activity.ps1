$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outputDir = $PSScriptRoot
$docxPath = Join-Path $outputDir 'Week1_Activity_LastName_FirstName.docx'
$pdfPath = Join-Path $outputDir 'Week1_Activity_LastName_FirstName.pdf'

function Rgb([int]$r, [int]$g, [int]$b) {
  return $r + ($g * 256) + ($b * 65536)
}

$blue = Rgb 29 103 201
$navy = Rgb 18 43 73
$teal = Rgb 0 151 136
$paleBlue = Rgb 235 244 255
$paleTeal = Rgb 230 247 244
$paleRed = Rgb 255 239 237
$gray = Rgb 86 104 128
$lightGray = Rgb 236 241 247
$white = Rgb 255 255 255

$word = $null
$doc = $null

try {
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $word.DisplayAlerts = 0
  $doc = $word.Documents.Add()

  $section = $doc.Sections.Item(1)
  $section.PageSetup.TopMargin = $word.InchesToPoints(0.65)
  $section.PageSetup.BottomMargin = $word.InchesToPoints(0.65)
  $section.PageSetup.LeftMargin = $word.InchesToPoints(0.72)
  $section.PageSetup.RightMargin = $word.InchesToPoints(0.72)

  $normal = $doc.Styles.Item('Normal')
  $normal.Font.Name = 'Aptos'
  $normal.Font.Size = 10.5
  $normal.Font.Color = $navy
  $normal.ParagraphFormat.SpaceAfter = 6
  $normal.ParagraphFormat.LineSpacingRule = 0

  foreach ($styleName in @('Title', 'Subtitle', 'Heading 1', 'Heading 2', 'Heading 3')) {
    $style = $doc.Styles.Item($styleName)
    $style.Font.Name = 'Aptos Display'
    $style.Font.Color = $navy
  }
  $doc.Styles.Item('Title').Font.Size = 30
  $doc.Styles.Item('Title').Font.Bold = $true
  $doc.Styles.Item('Heading 1').Font.Size = 20
  $doc.Styles.Item('Heading 1').Font.Bold = $true
  $doc.Styles.Item('Heading 1').ParagraphFormat.SpaceBefore = 0
  $doc.Styles.Item('Heading 1').ParagraphFormat.SpaceAfter = 10
  $doc.Styles.Item('Heading 2').Font.Size = 13
  $doc.Styles.Item('Heading 2').Font.Bold = $true
  $doc.Styles.Item('Heading 2').Font.Color = $blue
  $doc.Styles.Item('Heading 2').ParagraphFormat.SpaceBefore = 8
  $doc.Styles.Item('Heading 2').ParagraphFormat.SpaceAfter = 4

  function Add-Paragraph {
    param(
      [string]$Text = '',
      [string]$Style = 'Normal',
      [int]$Color = $navy,
      [switch]$Bold,
      [double]$Size = 0,
      [int]$Align = 0,
      [double]$SpaceAfter = 6
    )
    $p = $doc.Paragraphs.Add()
    $p.Range.Text = $Text
    $p.Range.Style = $Style
    $p.Range.Font.Color = $Color
    if ($Bold) { $p.Range.Font.Bold = $true }
    if ($Size -gt 0) { $p.Range.Font.Size = $Size }
    $p.Alignment = $Align
    $p.Format.SpaceAfter = $SpaceAfter
    return $p
  }

  function Add-PageBreak {
    $p = $doc.Paragraphs.Add()
    $p.Range.InsertBreak(7)
  }

  function Shade-Cell($cell, [int]$color) {
    $cell.Shading.BackgroundPatternColor = $color
  }

  function Add-Table {
    param([int]$Rows, [int]$Columns)
    $range = $doc.Range($doc.Content.End - 1, $doc.Content.End - 1)
    $table = $doc.Tables.Add($range, $Rows, $Columns)
    $after = $doc.Range($table.Range.End, $table.Range.End)
    $after.InsertParagraphAfter()
    return ,$table
  }

  function Set-CellText {
    param($Cell, [string]$Text, [double]$Size = 10, [int]$Color = $navy, [switch]$Bold, [int]$Align = 0)
    $Cell.Range.Text = $Text
    $Cell.Range.Font.Name = 'Aptos'
    $Cell.Range.Font.Size = $Size
    $Cell.Range.Font.Color = $Color
    $Cell.Range.Font.Bold = [bool]$Bold
    $Cell.Range.ParagraphFormat.Alignment = $Align
    $Cell.Range.ParagraphFormat.SpaceAfter = 2
    $Cell.VerticalAlignment = 1
  }

  function Set-ColumnWidth {
    param($Table, [int]$Column, [double]$WidthInches)
    $width = $word.InchesToPoints($WidthInches)
    for ($row = 1; $row -le $Table.Rows.Count; $row++) {
      $Table.Cell($row, $Column).Width = $width
    }
  }

  function Add-Bullet {
    param([string]$Text)
    $p = Add-Paragraph -Text $Text -SpaceAfter 3
    $p.Range.ListFormat.ApplyBulletDefault()
    $p.Range.ParagraphFormat.LeftIndent = $word.InchesToPoints(0.22)
    $p.Range.ParagraphFormat.FirstLineIndent = -$word.InchesToPoints(0.15)
  }

  # Header and footer
  $header = $section.Headers.Item(1).Range
  $header.Text = 'ADVANCED MOBILE PROGRAMMING  |  WEEK 1 PRACTICAL ACTIVITY'
  $header.Font.Name = 'Aptos'
  $header.Font.Size = 8
  $header.Font.Bold = $true
  $header.Font.Color = $blue
  $header.ParagraphFormat.Alignment = 2

  $footer = $section.Footers.Item(1).Range
  $footer.Text = 'CareNavigatorPH     |     '
  $footer.Font.Name = 'Aptos'
  $footer.Font.Size = 8
  $footer.Font.Color = $gray
  $footer.ParagraphFormat.Alignment = 1
  $footer.Collapse(0)
  $footer.Fields.Add($footer, -1, 'PAGE', $true) | Out-Null

  # Cover
  Add-Paragraph -Text 'WEEK 1 | PRACTICAL ACTIVITY' -Color $teal -Bold -Size 11 -SpaceAfter 22 | Out-Null
  Add-Paragraph -Text 'CareNavigatorPH' -Style 'Title' -Color $navy -Size 32 -SpaceAfter 2 | Out-Null
  Add-Paragraph -Text 'Navigate to the right care, at the right time.' -Color $blue -Bold -Size 16 -SpaceAfter 16 | Out-Null

  $hero = Add-Table 1 1
  $hero.Borders.Enable = 0
  $hero.Rows.Height = $word.InchesToPoints(1.38)
  Shade-Cell $hero.Cell(1,1) $paleBlue
  Set-CellText $hero.Cell(1,1) "A mobile healthcare navigation app for Filipino communities`n`nSDG 3 | Good Health and Well-Being" 16 $navy -Bold -Align 1
  $hero.Cell(1,1).Range.ParagraphFormat.LeftIndent = $word.InchesToPoints(0.15)
  $hero.Cell(1,1).Range.ParagraphFormat.RightIndent = $word.InchesToPoints(0.15)

  Add-Paragraph -Text '' -SpaceAfter 12 | Out-Null
  $meta = Add-Table 5 2
  $meta.Borders.Enable = 0
  Set-ColumnWidth $meta 1 1.35
  Set-ColumnWidth $meta 2 5.25
  $labels = @('Student Name', 'Course / Section', 'Instructor', 'Date', 'Filename')
  $values = @('[Last Name], [First Name]', 'Advanced Mobile Programming / [Section]', '[Instructor Name]', '____________________', 'Week1_Activity_LastName_FirstName')
  for ($i = 1; $i -le 5; $i++) {
    Set-CellText $meta.Cell($i,1) $labels[$i-1] 9 $gray -Bold
    Set-CellText $meta.Cell($i,2) $values[$i-1] 10.5 $navy
    $meta.Cell($i,1).Range.ParagraphFormat.SpaceAfter = 7
    $meta.Cell($i,2).Range.ParagraphFormat.SpaceAfter = 7
  }

  Add-Paragraph -Text '' -SpaceAfter 34 | Out-Null
  Add-Paragraph -Text 'PROJECT SNAPSHOT' -Color $teal -Bold -Size 9 -SpaceAfter 6 | Out-Null
  Add-Paragraph -Text 'CareNavigatorPH helps people describe symptoms safely, understand the appropriate level of care, find verified hospitals with relevant services and availability, and begin a consultation without presenting AI guidance as a medical diagnosis.' -Size 12 -SpaceAfter 8 | Out-Null

  Add-PageBreak
  Write-Output 'Cover complete.'

  # Problem and SDG
  Add-Paragraph -Text '1. Community Problem & SDG Alignment' -Style 'Heading 1' | Out-Null

  $problemBox = Add-Table 1 1
  $problemBox.Borders.Enable = 0
  Shade-Cell $problemBox.Cell(1,1) $paleRed
  Set-CellText $problemBox.Cell(1,1) "PROBLEM STATEMENT`nPeople in many Philippine communities struggle to decide where to seek care because hospital information is fragmented, service availability is unclear, and symptoms can be difficult to interpret. This can cause delayed treatment, unnecessary travel, crowded facilities, and confusion during urgent situations." 11 $navy
  $problemBox.Cell(1,1).Range.ParagraphFormat.LeftIndent = $word.InchesToPoints(0.12)
  $problemBox.Cell(1,1).Range.ParagraphFormat.RightIndent = $word.InchesToPoints(0.12)

  Add-Paragraph -Text 'Why this matters in the community' -Style 'Heading 2' | Out-Null
  Add-Bullet 'Patients may not know which nearby facility has the right department, specialist, emergency capability, beds, or rooms.'
  Add-Bullet 'Rural residents, older adults, caregivers, and first-time patients may spend extra time calling or visiting multiple facilities.'
  Add-Bullet 'Online health information can be misleading when it lacks local context, safety warnings, and a clear path to professional care.'

  Add-Paragraph -Text 'Selected UN Sustainable Development Goal' -Style 'Heading 2' | Out-Null
  $sdg = Add-Table 1 2
  $sdg.Borders.Enable = 0
  Set-ColumnWidth $sdg 1 1.25
  Set-ColumnWidth $sdg 2 5.35
  Shade-Cell $sdg.Cell(1,1) $blue
  Shade-Cell $sdg.Cell(1,2) $paleBlue
  Set-CellText $sdg.Cell(1,1) "SDG`n3" 24 $white -Bold -Align 1
  Set-CellText $sdg.Cell(1,2) "GOOD HEALTH AND WELL-BEING`nEnsure healthy lives and promote well-being for all at all ages.`n`nDirect alignment: Target 3.8 - access to quality essential healthcare services. CareNavigatorPH improves access by connecting users to appropriate, verified, and locally available care." 10.5 $navy

  Add-Paragraph -Text 'Intended impact' -Style 'Heading 2' | Out-Null
  Add-Paragraph -Text 'The app aims to shorten the path from uncertainty to appropriate professional care. It supports informed decisions and timely referrals while keeping emergency escalation, privacy, and clinician review central to the experience.' -SpaceAfter 0 | Out-Null

  Add-PageBreak
  Write-Output 'Problem and SDG section complete.'

  # Proposal
  Add-Paragraph -Text '2. Project Proposal' -Style 'Heading 1' | Out-Null
  Add-Paragraph -Text 'Core concept' -Style 'Heading 2' | Out-Null
  Add-Paragraph -Text 'CareNavigatorPH is a mobile healthcare navigation platform designed for Philippine communities. A user can describe symptoms, receive preliminary guidance about urgency and the type of care to seek, compare verified hospitals, and start a consultation. The app does not diagnose or replace a licensed healthcare professional.' | Out-Null

  Add-Paragraph -Text 'Target audience' -Style 'Heading 2' | Out-Null
  $audience = Add-Table 2 2
  $audience.Borders.Enable = 0
  Set-ColumnWidth $audience 1 3.2
  Set-ColumnWidth $audience 2 3.4
  Shade-Cell $audience.Cell(1,1) $paleBlue
  Shade-Cell $audience.Cell(1,2) $paleTeal
  Set-CellText $audience.Cell(1,1) "PRIMARY USERS`n- Patients and caregivers`n- Residents searching for nearby care`n- People unsure which department or hospital level they need" 10 $navy
  Set-CellText $audience.Cell(1,2) "SECONDARY USERS`n- Doctors and hospital staff`n- Hospital administrators`n- Community health workers and referral partners" 10 $navy
  Set-CellText $audience.Cell(2,1) "Priority context: users with limited time, incomplete local hospital information, or difficulty navigating healthcare options." 9.5 $gray
  Set-CellText $audience.Cell(2,2) "Accessibility focus: plain language, clear urgency labels, large touch targets, and visible emergency instructions." 9.5 $gray

  Add-Paragraph -Text 'Primary functionality' -Style 'Heading 2' | Out-Null
  $features = @(
    @('01', 'AI symptom navigator', 'Collects symptoms and relevant context, then suggests urgency and an appropriate care type with safety warnings.'),
    @('02', 'Verified hospital directory', 'Searches facilities by location, hospital level, service, specialist, and operational availability.'),
    @('03', 'Care matching', 'Connects assessment needs to suitable hospitals and departments instead of showing an unfiltered list.'),
    @('04', 'Consultation request', 'Lets a first-time user verify contact details, submit care needs, and receive a trackable reference.'),
    @('05', 'My Care', 'Keeps appointments, messages, medical history, notifications, and consent-controlled records in one place.')
  )
  $ft = Add-Table $features.Count 3
  $ft.Borders.Enable = 0
  Set-ColumnWidth $ft 1 0.55
  Set-ColumnWidth $ft 2 1.7
  Set-ColumnWidth $ft 3 4.35
  for ($i=1; $i -le $features.Count; $i++) {
    if ($i % 2 -eq 1) { Shade-Cell $ft.Cell($i,1) $paleBlue; Shade-Cell $ft.Cell($i,2) $paleBlue; Shade-Cell $ft.Cell($i,3) $paleBlue }
    Set-CellText $ft.Cell($i,1) $features[$i-1][0] 10 $blue -Bold -Align 1
    Set-CellText $ft.Cell($i,2) $features[$i-1][1] 9.5 $navy -Bold
    Set-CellText $ft.Cell($i,3) $features[$i-1][2] 9.2 $gray
  }

  Add-Paragraph -Text 'Scope and safety boundaries' -Style 'Heading 2' | Out-Null
  Add-Paragraph -Text 'The first version focuses on discovery, preliminary guidance, referrals, and consultation intake. It will clearly direct emergencies to 911 or the nearest emergency room, label AI output as non-diagnostic, protect personal and medical data, and require professional review for clinical decisions.' -SpaceAfter 0 | Out-Null

  Add-PageBreak
  Write-Output 'Proposal section complete.'

  # Wireframes 1 and 2
  Add-Paragraph -Text '3. Mockup / Wireframe' -Style 'Heading 1' | Out-Null
  Add-Paragraph -Text 'User flow: Sign in > describe symptoms > review guidance > find matching care' -Color $gray -Size 10 -SpaceAfter 8 | Out-Null

  $wire1 = Add-Table 1 2
  $wire1.Borders.Enable = 0
  Set-ColumnWidth $wire1 1 3.3
  Set-ColumnWidth $wire1 2 3.3
  $img1 = Join-Path $root 'mobile-login.png'
  $img2 = Join-Path $root 'artifacts\browser\assessment-result-mobile-check.png'
  $s1 = $wire1.Cell(1,1).Range.InlineShapes.AddPicture($img1, $false, $true)
  $s1.LockAspectRatio = -1
  $s1.Width = $word.InchesToPoints(2.62)
  $wire1.Cell(1,1).Range.ParagraphFormat.Alignment = 1
  $s2 = $wire1.Cell(1,2).Range.InlineShapes.AddPicture($img2, $false, $true)
  $s2.LockAspectRatio = -1
  $s2.Width = $word.InchesToPoints(2.62)
  $wire1.Cell(1,2).Range.ParagraphFormat.Alignment = 1

  $captions1 = Add-Table 1 2
  $captions1.Borders.Enable = 0
  Set-ColumnWidth $captions1 1 3.3
  Set-ColumnWidth $captions1 2 3.3
  Shade-Cell $captions1.Cell(1,1) $paleBlue
  Shade-Cell $captions1.Cell(1,2) $paleTeal
  Set-CellText $captions1.Cell(1,1) "SCREEN 1 - SIGN IN`nSecure entry for patients and care providers. Clear role access keeps health information private." 9.5 $navy
  Set-CellText $captions1.Cell(1,2) "SCREEN 2 - SYMPTOM ASSESSMENT`nThe user describes symptoms, duration, age, conditions, allergies, and medicines before checking symptoms." 9.5 $navy

  Add-Paragraph -Text 'Design notes' -Style 'Heading 2' | Out-Null
  Add-Paragraph -Text 'The interface uses a calm blue-and-teal palette, plain-language instructions, high-contrast actions, and persistent mobile navigation. Emergency messaging appears before the assessment to prevent unsafe reliance on the tool.' -SpaceAfter 0 | Out-Null

  Add-PageBreak
  Write-Output 'Wireframes 1-2 complete.'

  # Wireframes 3 and 4
  Add-Paragraph -Text '3. Mockup / Wireframe (continued)' -Style 'Heading 1' | Out-Null
  $wire2 = Add-Table 1 2
  $wire2.Borders.Enable = 0
  Set-ColumnWidth $wire2 1 3.3
  Set-ColumnWidth $wire2 2 3.3
  $img3 = Join-Path $root 'artifacts\browser\assessment-recommendation-mobile-bottom.png'
  $img4 = Join-Path $root 'artifacts\browser\hospital-directory-mobile-check.png'
  $s3 = $wire2.Cell(1,1).Range.InlineShapes.AddPicture($img3, $false, $true)
  $s3.LockAspectRatio = -1
  $s3.Width = $word.InchesToPoints(2.62)
  $wire2.Cell(1,1).Range.ParagraphFormat.Alignment = 1
  $s4 = $wire2.Cell(1,2).Range.InlineShapes.AddPicture($img4, $false, $true)
  $s4.LockAspectRatio = -1
  $s4.Width = $word.InchesToPoints(2.62)
  $wire2.Cell(1,2).Range.ParagraphFormat.Alignment = 1

  $captions2 = Add-Table 1 2
  $captions2.Borders.Enable = 0
  Set-ColumnWidth $captions2 1 3.3
  Set-ColumnWidth $captions2 2 3.3
  Shade-Cell $captions2.Cell(1,1) $paleTeal
  Shade-Cell $captions2.Cell(1,2) $paleBlue
  Set-CellText $captions2.Cell(1,1) "SCREEN 3 - CARE GUIDANCE`nShows a recommended department, warning signs, possibilities to discuss with a clinician, and a matching-hospital action. AI guidance remains explicitly non-diagnostic." 9.5 $navy
  Set-CellText $captions2.Cell(1,2) "SCREEN 4 - HOSPITAL DIRECTORY`nLets users search verified facilities, filter by hospital level and ER availability, and compare care capacity before viewing a hospital." 9.5 $navy

  Add-Paragraph -Text 'Flow logic' -Style 'Heading 2' | Out-Null
  $flow = Add-Table 1 7
  $flow.Borders.Enable = 0
  Set-ColumnWidth $flow 1 1.28
  Set-ColumnWidth $flow 2 0.25
  Set-ColumnWidth $flow 3 1.28
  Set-ColumnWidth $flow 4 0.25
  Set-ColumnWidth $flow 5 1.28
  Set-ColumnWidth $flow 6 0.25
  Set-ColumnWidth $flow 7 1.28
  foreach ($j in @(1,3,5,7)) { Shade-Cell $flow.Cell(1,$j) $blue }
  Set-CellText $flow.Cell(1,1) "1`nSIGN IN" 9.5 $white -Bold -Align 1
  Set-CellText $flow.Cell(1,2) '>' 16 $blue -Bold -Align 1
  Set-CellText $flow.Cell(1,3) "2`nASSESS" 9.5 $white -Bold -Align 1
  Set-CellText $flow.Cell(1,4) '>' 16 $blue -Bold -Align 1
  Set-CellText $flow.Cell(1,5) "3`nGUIDANCE" 9.5 $white -Bold -Align 1
  Set-CellText $flow.Cell(1,6) '>' 16 $blue -Bold -Align 1
  Set-CellText $flow.Cell(1,7) "4`nFIND CARE" 9.5 $white -Bold -Align 1

  Add-Paragraph -Text 'Expected result' -Style 'Heading 2' | Out-Null
  Add-Paragraph -Text 'At the end of the flow, the user understands the suggested level of care and has a practical next step: view a suitable hospital, get directions, or begin a consultation. The design reduces uncertainty without removing professional judgment.' -SpaceAfter 0 | Out-Null

  Add-PageBreak
  Write-Output 'Wireframes 3-4 complete.'

  # Presentation guide
  Add-Paragraph -Text '4. Presentation Guide' -Style 'Heading 1' | Out-Null
  Add-Paragraph -Text 'Suggested 2-3 minute presentation script' -Style 'Heading 2' | Out-Null
  $script = @(
    @('OPENING', 'Our project is CareNavigatorPH, a mobile app that helps Filipino patients navigate from symptoms to suitable local care.'),
    @('THE PROBLEM', 'People often do not know which hospital has the right service, specialist, or current capacity. This causes confusion, delays, and unnecessary travel.'),
    @('SDG', 'The project supports SDG 3: Good Health and Well-Being, particularly Target 3.8 on access to quality essential healthcare services.'),
    @('THE SOLUTION', 'Users can enter symptoms, receive preliminary and safety-focused guidance, see the recommended type of care, and find verified matching hospitals.'),
    @('USER FLOW', 'The wireframes show four connected screens: sign in, symptom assessment, care guidance, and the hospital directory.'),
    @('SAFETY', 'CareNavigatorPH does not diagnose. Emergency cases are directed to 911 or the nearest ER, and clinical decisions remain with licensed professionals.'),
    @('CLOSING', 'Our goal is simple: reduce the time and uncertainty between needing help and reaching the right care.')
  )
  $pt = Add-Table $script.Count 2
  $pt.Borders.Enable = 0
  Set-ColumnWidth $pt 1 1.22
  Set-ColumnWidth $pt 2 5.38
  for ($i=1; $i -le $script.Count; $i++) {
    if ($i % 2 -eq 1) { Shade-Cell $pt.Cell($i,1) $paleBlue; Shade-Cell $pt.Cell($i,2) $paleBlue }
    Set-CellText $pt.Cell($i,1) $script[$i-1][0] 8.5 $blue -Bold
    Set-CellText $pt.Cell($i,2) $script[$i-1][1] 9.8 $navy
  }

  Add-Paragraph -Text 'Success measures for a future prototype test' -Style 'Heading 2' | Out-Null
  Add-Bullet 'Users can identify the next care step without assistance.'
  Add-Bullet 'Users can find a suitable facility in three minutes or less.'
  Add-Bullet 'Users correctly understand that AI guidance is preliminary and non-diagnostic.'
  Add-Bullet 'Users notice emergency instructions before starting an assessment.'

  Add-Paragraph -Text 'Submission checklist' -Style 'Heading 2' | Out-Null
  $check = Add-Table 1 1
  $check.Borders.Enable = 0
  Shade-Cell $check.Cell(1,1) $paleTeal
  Set-CellText $check.Cell(1,1) "[ ] Replace the student, section, instructor, and date placeholders.`n[ ] Rename the file using your real LastName_FirstName.`n[ ] Review the wireframes and rehearse the presentation script.`n[ ] Upload the Word file or exported PDF as instructed." 10 $navy

  # Document metadata and final layout cleanup
  Write-Output 'Saving Word document...'
  $doc.SaveAs2($docxPath, 16)
  Write-Output 'Exporting PDF...'
  $doc.ExportAsFixedFormat($pdfPath, 17)
  Write-Output "Created: $docxPath"
  Write-Output "Created: $pdfPath"
  Write-Output 'Export complete.'
}
finally {
  if ($doc -ne $null) { $doc.Close($false) }
  if ($word -ne $null) { $word.Quit() }
  [System.GC]::Collect()
  [System.GC]::WaitForPendingFinalizers()
}
