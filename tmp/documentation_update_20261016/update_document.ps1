param([string]$HeadingPages,[string]$RenderSummary)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8=[System.Text.UTF8Encoding]::new($false)
$w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$inputPath=Join-Path $PSScriptRoot 'documentation-before-update.docx'
$outputPath=Join-Path $PSScriptRoot 'MAD_Final_Project_Documentation_CareNavigator_PH.docx'
$parts=@{}
$zip=[IO.Compression.ZipFile]::OpenRead($inputPath)
foreach($entry in $zip.Entries){$s=$entry.Open();$m=[IO.MemoryStream]::new();$s.CopyTo($m);$s.Dispose();$parts[$entry.FullName]=$m.ToArray();$m.Dispose()};$zip.Dispose()
[xml]$doc=$utf8.GetString($parts['word/document.xml'])
$ns=[Xml.XmlNamespaceManager]::new($doc.NameTable);$ns.AddNamespace('w',$w)
$body=$doc.SelectSingleNode('//w:body',$ns)
function TextOf($node){return ($node.SelectNodes('.//w:t',$ns) | ForEach-Object {$_.InnerText}) -join ''}
function SetText($node,[string]$value){
  $texts=@($node.SelectNodes('.//w:t',$ns));if(-not $texts.Count){throw 'Text target is empty'}
  $texts[0].InnerText=$value;[void]$texts[0].SetAttribute('space','http://www.w3.org/XML/1998/namespace','preserve')
  foreach($text in $texts | Select-Object -Skip 1){$text.InnerText=''}
}
$changes=[Collections.Generic.List[object]]::new()
function ReplacePrefix([string]$prefix,[string]$replacement){
  $matches=@($body.SelectNodes('w:p',$ns) | Where-Object {(TextOf $_).StartsWith($prefix)})
  if($matches.Count -ne 1){throw ('Expected one paragraph: '+$prefix+'; found '+$matches.Count)}
  $old=TextOf $matches[0];SetText $matches[0] $replacement;$changes.Add([pscustomobject]@{old=$old;new=$replacement})
}
ReplacePrefix 'The exposed SMTP credential requires' 'Live notification email is blocked until the dispatcher receives a replacement SMTP_PASSWORD server secret. Its handler passed seven local SMTP checks. Real inbox delivery, Google Meet media, physical-device behavior, and full cloud installation and upgrade remain verification gates. [S24]'
ReplacePrefix 'The request status describes review and contact progress' 'Request status tracks review and contact; consultation status tracks the clinical appointment. Terminal actions synchronize app sessions, access, history, and notifications. Google Meet controls hosting and admission. [S5, S7, S10]'
ReplacePrefix 'Terminal actions close rooms' 'Terminal actions close app sessions and related access, retaining outcome reasons. They cannot end Google Meet calls or invalidate copied links.'
ReplacePrefix 'Sharing management groups access' 'Sharing management groups access by care relationship. Revocation covers every active grant, category, and selected record in that relationship. Video joining requires an assigned-doctor Google Meet link and an open join window; missing links offer a refresh-and-retry state.'
ReplacePrefix 'The test design follows the existing Activity 1' 'The test design follows Activity 1 CareNavigator PH Test Scenarios and Test Cases. Its 15 scenario identifiers and four detailed cases are retained. The 16 October 2026 verification adds actual results using owned synthetic fixtures and identifies controlled responses explicitly. [S23, S24]'
ReplacePrefix 'Activity 1 supplies expected outcomes' 'Activity 1 supplies expected outcomes but no execution records. The results below come from the separate 16 October verification. They identify fixture substitutions, actual backend actions, controlled UI responses, and remaining integration limits. [S24]'
ReplacePrefix 'Active patient fixture qa.patient' 'Use the owned synthetic patient configured for the test run and its correct test password. Keep credentials in local test configuration and outside this document.'
ReplacePrefix 'Existing patient fixture qa.patient' 'Use the owned synthetic patient configured for the test run and a deliberately incorrect password. Keep the real test password outside this document.'
ReplacePrefix 'Hospital: verified and operating fixture.' 'Use the owned synthetic patient and doctor at a verified, operating hospital. Select the next published, unoccupied in-person slot at least 24 hours ahead; a fixed 48-hour offset may not match a published schedule.'
ReplacePrefix 'Clinician: no qualifying future slots.' 'Expected fixture: no qualifying slots in the next 30 days, with a 24-hour minimum lead time. The recorded UI check supplies an empty availability response; it does not provision a separate no-slot clinician.'
ReplacePrefix 'These checks retain the earlier workflow summary' 'The 16 October checks distinguish live actions, database assertions, and controlled responses. External email delivery and real provider media remain separate gates. [S24]'
ReplacePrefix 'The full browser run at 6:34 AM' 'Verification on 16 October 2026 passed 281 Flutter checks, 28 browser checks and 11 deployed SQL suites. Four follow-ups and the local SMTP and concurrency tests add qualified evidence. External delivery and media remain open. [S24]'
ReplacePrefix 'The implemented structure supports' 'Fresh results support scoped care, transactional orders, and review controls. Earlier AI extraction remains historical evidence and does not establish clinical accuracy.'
ReplacePrefix 'Release acceptance still requires' 'Local races, generated-link recovery and controlled Meet navigation passed. External inbox delivery, real provider media, device checks, and full cloud installation and staging upgrade remain open. [S24]'
ReplacePrefix 'CareNavigator PH implements a mobile and web application' 'CareNavigator PH connects discovery, verified intake, hospital-reviewed booking, clinician records, communication, and administration in one Flutter application. Riverpod and Supabase support shared data flows; role and care-relationship checks control access.'
ReplacePrefix 'The repair work introduces typed booking outcomes' 'The workflows include typed booking outcomes, guest activation, reviewed uploads, atomic prescription orders, and delivery states. Passing tests support these features. Notification email still requires a dispatcher SMTP password; external integration and deployment gates remain open.'
ReplacePrefix '• Revoke the exposed SMTP credential' '• Configure the dispatcher SMTP_PASSWORD server secret, verify a controlled inbox, and revoke previously exposed credentials.'
ReplacePrefix '• Retain the passed focused upload-review check' '• Retain upload-review and browser CRUD regressions; extend document rejection and failure-recovery coverage while preserving provenance.'
ReplacePrefix '• Complete an authenticated two-party Jitsi session' '• Verify real Google Meet admission and received media on both sides. App revocation does not replace provider host controls.'
ReplacePrefix '• Execute the valid recovery-link journey' '• Retain generated-link recovery coverage and test actual recovery-email delivery through deployed routes.'
ReplacePrefix '• Complete database race, reschedule' '• Retain isolated concurrency checks; test staging load, attachment retry, and daily-dispatch timing without weakening booking rules.'
ReplacePrefix '• Prove installation in an empty Supabase project' '• Prove empty-cloud installation and staging upgrades. Maintain migration reconciliation, the full ERD, and all six function versions.'
ReplacePrefix '• Monitor lifecycle inconsistencies' '• Monitor lifecycle, access, outbox, duplicate-summary, and activation errors after rollout. Test real Android devices and verify iOS separately.'
ReplacePrefix '6. Use the authorized video join action' '6. Use Join Google Meet / retry during the permitted window after the doctor saves the link. Follow any identity-resolution action while continuing authorized tracking.'
ReplacePrefix '4. Use the appointment controls to track' '4. Track, reschedule, or cancel where permitted. Select Join Google Meet after the doctor saves the link and the scheduled join window opens.'
ReplacePrefix '3. For online care, prepare or join' '3. After hospital confirmation, create a Google Meet meeting and select Set Google Meet link. Paste its HTTPS meeting URL. Select Join Google Meet during the join window and use Google Meet host controls to admit the patient.'
ReplacePrefix 'Request password recovery from authentication' 'Request recovery and open the emailed link. For an expired link, request a new one. Enter and confirm a new password on reset-password. Generated-link recovery through real Auth passed on 16 October; delivery of an actual recovery email remains a separate check. [S24]'
ReplacePrefix 'The following repository sources and recorded verification artifacts' 'The following repository sources and verification artifacts support the system descriptions and results. Historical evidence is dated 11 and 12 October 2026. Current results and qualified follow-up checks are dated 16 October 2026.'
ReplacePrefix '[S10] supabase/migrations/20261011171441' '[S10] Active Google Meet migrations 20261011231128 and 20261011232923. Doctor-supplied links, assignment guards, participant authorization, and join-window enforcement.'
ReplacePrefix '[S13] Recorded Playwright runs' '[S13] Historical Playwright evidence from 12 October 2026, retained in tmp/final_project_doc/verification_evidence.json. Current browser results are recorded under S24.'

# Adapt the scenario wording while preserving its original identifier.
foreach($p in $body.SelectNodes('.//w:tbl//w:p',$ns)){
  $text=TextOf $p
  if($text -eq 'Verify that a guest can submit a consultation request, complete email OTP verification, and enter the authorized review workflow.'){
    SetText $p 'Verify that a guest can complete email OTP verification, submit a consultation request, and enter the authorized review workflow.'
  }
  if($text -eq 'Groq, SMTP, and Jitsi'){SetText $p 'Groq, SMTP, and Google Meet'}
  if($text -eq 'Preliminary AI assistance, opt-in email, and authorized online rooms.'){SetText $p 'Preliminary AI assistance, opt-in email, and doctor-supplied meeting links.'}
  if($text -eq 'Track the reserved appointment, record contact, or prepare the authorized room.'){SetText $p 'Track the appointment, record contact, or let the assigned doctor save the Meet link.'}
  if($text -eq 'Finalize records; close the room and consultation-specific access, and notify.'){SetText $p 'Finalize records; close app session records and consultation-specific access, and notify.'}
  if($text -eq 'Video room is not ready'){SetText $p 'Google Meet link is not ready'}
  if($text -eq 'Use the retry state and contact the hospital if preparation does not complete.'){SetText $p 'Refresh and retry after the doctor saves the link; contact the hospital if it remains unavailable.'}
}
$caseRecords=@{
  'TC_AUTH_001'='Execution on 16 October 2026: PASS with the owned synthetic patient. Real Auth sign-in and the protected patient appointments page passed. S24. Activity 1 supplied no execution record.'
  'TC_AUTH_002'='Execution on 16 October 2026: PASS with the owned synthetic patient. Incorrect credentials returned HTTP 400 and the protected route redirected to sign-in. S24.'
  'TC_BOOKING_001'='Execution on 16 October 2026: PASS with a published synthetic slot at least 24 hours ahead. The row appeared in the patient list and the occupied slot disappeared. The test reservation was cancelled. S24.'
  'TC_BOOKING_002'='Execution on 16 October 2026: UI PASS with a controlled empty response. The 24-hour notice appeared, submission stayed disabled, and no booking request was sent. A real no-slot backend fixture was not used. S24.'
}
$currentCase=''
foreach($p in $body.SelectNodes('w:p',$ns)){
  $text=TextOf $p
  if($text -match '^Test Case (TC_\w+)$'){$currentCase=$Matches[1]}
  if($text.StartsWith('Execution record:')){if(-not $caseRecords.ContainsKey($currentCase)){throw 'Unknown detailed case'};SetText $p $caseRecords[$currentCase]}
}
function FindTable([string]$firstHeader){
  $tables=@($body.SelectNodes('w:tbl',$ns) | Where-Object {(TextOf $_.SelectSingleNode('w:tr[1]/w:tc[1]',$ns)) -eq $firstHeader})
  if($tables.Count -ne 1){throw ('Table not unique: '+$firstHeader)};return $tables[0]
}
function SetCell($cell,[string]$value){$p=$cell.SelectSingleNode('w:p',$ns);SetText $p $value;foreach($extra in @($cell.SelectNodes('w:p[position()>1]',$ns))){[void]$cell.RemoveChild($extra)}}
$matrix=FindTable 'Verification area'
$evidence=@(
 'Five role browser journeys passed.',
 'Verified retry regression passed.',
 'Live review and confirmation passed.',
 'SQL response/proposal checks passed.',
 'SQL activation and retry passed.',
 'SQL reschedule and local races passed.',
 'Concurrent confirmation race passed.',
 'SQL/UI passed; real media open.',
 'SQL checks before/at 30 minutes passed.',
 'Live upload and scoped review passed.',
 'Full-order rollback assertion passed.',
 'Grouping/attachment checks passed.',
 'Local SMTP passed; live blocked.',
 'Preference reload and revocation passed.',
 'Date guards present; dispatch timing open.',
 'Recovery passed; email delivery open.'
)
$matrixRows=@($matrix.SelectNodes('w:tr[position()>1]',$ns))
if($matrixRows.Count -ne $evidence.Count){throw ('Unexpected supplementary row count: '+$matrixRows.Count)}
for($i=0;$i -lt $evidence.Count;$i++){SetCell $matrixRows[$i].SelectNodes('w:tc',$ns)[2] $evidence[$i]}
$evaluation=FindTable 'Check'
$rows=@(
 @('Flutter static analysis','Passed','16 October: no issues found.'),
 @('Flutter test coverage','281 passed','270 ordinary checks plus 11 separate live checks; none of those live checks remained skipped.'),
 @('Web release build','Passed','Fresh release build on 16 October.'),
 @('Android release build','Recorded','12 October APK retained; not rebuilt or tested on a physical device in this review.'),
 @('Browser verification','Passed with limits','28 broader checks plus four follow-ups. Meet display/join responses were controlled; no provider media claim.'),
 @('Schema and SQL acceptance','Passed with limits','11 deployed suites rolled back; clean local schema passed with 178 functions. Full cloud install/upgrade remain open.'),
 @('SMTP notification delivery','Local pass; live blocked','Seven local SMTP checks passed. The deployed dispatcher has no SMTP_PASSWORD secret; real inbox delivery is open.'),
 @('Two-party Google Meet media','Open','Controlled external navigation does not establish admission or received audio/video.'),
 @('Concurrent scheduling','Local pass','Three checks used independent PostgreSQL sessions, observed advisory waits, and verified both schedule-race orders.'),
 @('Valid password recovery','Passed with limit','Real Auth recovery token, redirect and password change passed; token obtained by admin API, without sending email.')
)
$template=$evaluation.SelectSingleNode('w:tr[2]',$ns).CloneNode($true)
foreach($row in @($evaluation.SelectNodes('w:tr[position()>1]',$ns))){[void]$evaluation.RemoveChild($row)}
foreach($data in $rows){$row=$template.CloneNode($true);$cells=$row.SelectNodes('w:tc',$ns);for($i=0;$i -lt 3;$i++){SetCell $cells[$i] $data[$i]};[void]$evaluation.AppendChild($row)}
$lastSource=@($body.SelectNodes('w:p',$ns) | Where-Object {(TextOf $_).StartsWith('[S23]')})[0]
if(-not $lastSource){throw 'S23 reference missing'}
$newSource=$lastSource.CloneNode($true)
SetText $newSource '[S24] 16 October 2026 verification report and evidence in output/final_project and tmp/documentation_accuracy_20261016. Follow-up recovery, SMTP, Meet and race results are in tmp/documentation_update_20261016.'
[void]$body.InsertAfter($newSource,$lastSource)
$closingNote=@($body.SelectNodes('w:p',$ns) | Where-Object {(TextOf $_).StartsWith('Raw deployed-source snapshots')})[0]
if($closingNote){[void]$body.RemoveChild($closingNote)}

# Refresh the static contents entries from actual Word pagination when supplied.
if($HeadingPages){
  $lookup=@{};foreach($heading in (Get-Content -Raw -LiteralPath $HeadingPages -Encoding UTF8 | ConvertFrom-Json)){$lookup[$heading.text]=$heading.page}
  $tocMap=@{
    'Chapter 1 Project Overview'='PROJECT OVERVIEW';'  Introduction'='PROJECT OVERVIEW';'  Objectives and significance'='Project Objectives and Significance';'  Scope and limitations'='Scope of the Project';
    'Chapter 2 System Analysis and Design'='SYSTEM ANALYSIS AND DESIGN';'  System description and architecture'='SYSTEM ANALYSIS AND DESIGN';'  System flow and lifecycle'='System Flow';'  Use case diagram'='Use Case Diagram';'  Database design and tables'='Database Design';'  User interface design'='User Interface Design';
    'Chapter 3 System Development'='SYSTEM DEVELOPMENT';'  Tools and technologies'='SYSTEM DEVELOPMENT';'  Development process'='Development Process';'  Deployment and reproducibility'='Deployment and Reproducibility';
    'Chapter 4 Results and Testing'='RESULTS AND TESTING';'  System features'='RESULTS AND TESTING';'  Functional testing'='Functional Testing';'  Detailed test cases'='Test Case TC_AUTH_001';'  Evaluation and verification'='Evaluation and Recorded Verification';
    'Chapter 5 Conclusion and Recommendations'='CONCLUSION AND RECOMMENDATIONS';'Appendix A Screenshots of the Application'='Appendix A Screenshots of the Application';'Appendix B Source Code Snippets'='Appendix B Source Code Snippets';'Appendix C User Manual'='Appendix C User Manual';'Appendix D Complete Physical ERD'='Appendix D Complete Physical ERD';'Research References'='Research References';'Project References'='Project References'
  }
  foreach($toc in $body.SelectNodes('w:p[w:pPr/w:tabs/w:tab[@w:leader="dot"]]',$ns)){
    $texts=@($toc.SelectNodes('.//w:t',$ns));$label=$texts[0].InnerText
    if($tocMap.ContainsKey($label) -and $lookup.ContainsKey($tocMap[$label])){$texts[-1].InnerText=[string]$lookup[$tocMap[$label]]}
  }
}
$parts['word/document.xml']=$utf8.GetBytes($doc.OuterXml)
function Sha($bytes){$h=[Security.Cryptography.SHA256]::Create();$s=[BitConverter]::ToString($h.ComputeHash($bytes));$h.Dispose();return $s}
foreach($name in @('architecture','workflow')){
  $oldBytes=[IO.File]::ReadAllBytes((Join-Path (Split-Path $PSScriptRoot) ('final_project_doc\diagrams\'+$name+'.png')))
  $matching=@($parts.Keys | Where-Object {$_.StartsWith('word/media/') -and (Sha $parts[$_]) -eq (Sha $oldBytes)})
  if($matching.Count -ne 1){throw ('Figure part not unique: '+$name)}
  $parts[$matching[0]]=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot ('diagrams\'+$name+'.png')))
}
if($RenderSummary){[xml]$app=$utf8.GetString($parts['docProps/app.xml']);($app.DocumentElement.ChildNodes | Where-Object {$_.LocalName -eq 'Pages'}).InnerText=[string](Get-Content -Raw -LiteralPath $RenderSummary | ConvertFrom-Json).pages;$parts['docProps/app.xml']=$utf8.GetBytes($app.OuterXml)}
$stream=[IO.File]::Open($outputPath,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite)
$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
foreach($key in $parts.Keys){$entry=$archive.CreateEntry($key,[IO.Compression.CompressionLevel]::Optimal);$s=$entry.Open();$s.Write($parts[$key],0,$parts[$key].Length);$s.Dispose()};$archive.Dispose();$stream.Dispose()
$changes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'prose-changes.json') -Encoding UTF8
Write-Output ('Updated {0} prose paragraphs, four case execution records, verification tables, references, and two figures: {1}' -f $changes.Count,$outputPath)
