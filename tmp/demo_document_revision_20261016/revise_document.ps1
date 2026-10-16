param([string]$HeadingPages,[int]$PageCount=0)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8=[Text.UTF8Encoding]::new($false)
$parts=@{};$zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $PSScriptRoot 'documentation-before-demo-revision.docx'))
foreach($entry in $zip.Entries){$s=$entry.Open();$m=[IO.MemoryStream]::new();$s.CopyTo($m);$s.Dispose();$parts[$entry.FullName]=$m.ToArray();$m.Dispose()};$zip.Dispose()
[xml]$d=$utf8.GetString($parts['word/document.xml']);$n=[Xml.XmlNamespaceManager]::new($d.NameTable)
$n.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main');$n.AddNamespace('a','http://schemas.openxmlformats.org/drawingml/2006/main');$n.AddNamespace('wp','http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing');$n.AddNamespace('r','http://schemas.openxmlformats.org/officeDocument/2006/relationships')
$body=$d.SelectSingleNode('//w:body',$n);$original=@($body.ChildNodes)
function T($node){return ($node.SelectNodes('.//w:t',$n)|ForEach-Object {$_.InnerText})-join ''}
function SetT($node,[string]$text){$texts=@($node.SelectNodes('.//w:t',$n));if(-not $texts.Count){throw 'Empty text target'};$texts[0].InnerText=$text;foreach($extra in $texts|Select-Object -Skip 1){$extra.InnerText=''}}
function ReplaceP([string]$prefix,[string]$text){$nodes=@($body.SelectNodes('w:p',$n)|Where-Object {(T $_).StartsWith($prefix)});if($nodes.Count -ne 1){throw ('Paragraph not unique: '+$prefix)};SetT $nodes[0] $text;return ,$nodes[0]}
function SetCell($cell,[string]$text){SetT $cell.SelectSingleNode('w:p',$n) $text;foreach($extra in @($cell.SelectNodes('w:p[position()>1]',$n))){[void]$cell.RemoveChild($extra)}}
[void](ReplaceP 'CareNavigator PH uses a relational PostgreSQL database.' 'CareNavigator PH uses PostgreSQL for account profiles, hospital discovery, appointments, and clinical records. The main feature ERD in Appendix D selects nine central tables and their principal relationships. The baseline catalog remains the source for the complete schema. [S3, S11]')
[void](ReplaceP 'Complete Physical ERD' 'Main Feature ERD')
[void](ReplaceP 'The complete physical ERD is presented' 'Appendix D shows the main account-to-care path: users have patient or doctor profiles; hospitals have doctors; doctors publish schedules; patients reserve consultations; consultations link to medical records and prescription orders; orders group medication entries. Only selected fields and foreign keys are shown.')
$fullLink=ReplaceP 'Open the complete interactive ERD' 'See Appendix D for the main feature diagram.'
foreach($link in @($fullLink.SelectNodes('w:hyperlink',$n))){$r=$d.CreateElement('w','r',$n.LookupNamespace('w'));$t=$d.CreateElement('w','t',$n.LookupNamespace('w'));$t.InnerText='See Appendix D for the main feature diagram.';[void]$r.AppendChild($t);[void]$fullLink.ReplaceChild($r,$link)}
[void](ReplaceP 'PK identifies a primary-key column.' 'PK identifies a primary key, FK a displayed foreign key, and UK a unique key. A circle means optional, a bar means one, and a crow foot means many. Diagram labels name the child foreign-key column. Selected fields keep the model readable; additional database constraints remain in the catalog.')
[void](ReplaceP 'An authentication user is distinct' 'Supabase Auth handles credentials separately from the application users table. Patient and doctor profiles refer to users.id. The diagram shows schema nullability and uniqueness; application workflows may impose stricter rules.')
[void](ReplaceP 'Type labels are shortened' 'Type labels are shortened: timestamptz means timestamp with time zone, int2 means smallint, int4 means integer, and enum represents the field-specific enumerated type. Row Level Security and workflow authorization are defined in SQL, outside the diagram.')
[void](ReplaceP 'The test design follows Activity 1' 'Five scenarios cover the presentation: sign-in, directory search, successful in-person booking, no available slots, and appointment viewing/cancellation. The four detailed Activity 1 case identifiers are retained and mapped below. Existing verification results remain dated and qualified. [S23, S24]')
[void](ReplaceP 'Activity 1 supplies expected outcomes' 'Before the demonstration, prepare an active verified test patient, a published unoccupied in-person slot more than 24 hours after the demo, and a separate test doctor with no qualifying slots in the next 30 days. Use synthetic data. Record the actual result and screenshots for each scenario.')
[void](ReplaceP 'Test Scenarios TS-01 to TS-08' 'Five Demonstration Scenarios')
$scenario=$original[198];$rowTemplate=$scenario.SelectSingleNode('w:tr[2]',$n).CloneNode($true);$headTemplate=$scenario.SelectSingleNode('w:tr[1]',$n).CloneNode($true)
function MakeRow($template,$values){$row=$template.CloneNode($true);$cells=@($row.SelectNodes('w:tc',$n));[void]$row.AppendChild($cells[1].CloneNode($true));$cells=@($row.SelectNodes('w:tc',$n));for($j=0;$j -lt 3;$j++){SetCell $cells[$j] $values[$j];[void]$cells[$j].SelectSingleNode('w:tcPr/w:tcW',$n).SetAttribute('w',$n.LookupNamespace('w'),([string]@(800,4400,4160)[$j]))};return ,$row}
foreach($row in @($scenario.SelectNodes('w:tr',$n))){[void]$scenario.RemoveChild($row)}
$grid=$scenario.SelectSingleNode('w:tblGrid',$n);$grid.RemoveAll();foreach($width in @(800,4400,4160)){$col=$d.CreateElement('w','gridCol',$n.LookupNamespace('w'));[void]$col.SetAttribute('w',$n.LookupNamespace('w'),[string]$width);[void]$grid.AppendChild($col)}
[void]$scenario.AppendChild((MakeRow $headTemplate @('ID','Demonstration','Expected result')))
$scenarioRows=@(
 @('TS-01','Patient sign-in: try an incorrect password, then sign in with valid credentials.','Wrong credentials show an error; valid credentials open the correct patient workspace.'),
 @('TS-02','Hospital and doctor search: search the public directory and open a matching result.','Relevant verified, operating hospitals and their doctor details are displayed.'),
 @('TS-03','Successful booking: reserve a published in-person slot more than 24 hours ahead.','Confirmation appears; the appointment has the selected doctor/date/time; the occupied slot is unavailable.'),
 @('TS-04','No available slots: select the prepared test doctor with no qualifying slots.','The empty-availability notice appears; Reserve consultation is disabled; no appointment is created.'),
 @('TS-05','View and cancel: open the test appointment, check its details, then cancel it.','Details match the booking; cancellation succeeds and the appointment is no longer active, with history retained.')
)
foreach($values in $scenarioRows){[void]$scenario.AppendChild((MakeRow $rowTemplate $values))}
foreach($i in @(199,200,201,202,203)){[void]$body.RemoveChild($original[$i])}
[void](ReplaceP 'TS-02 is represented by' 'TS-01 is covered by TC_AUTH_001 and TC_AUTH_002. TS-03 is covered by TC_BOOKING_001; TS-04 by TC_BOOKING_002. TS-02 and TS-05 are demonstrated through the scenario checklist. There are exactly four detailed test cases.')
[void](ReplaceP 'The TS-03 cases concern' 'The booking cases use in-person appointments and the 24-hour minimum lead time. The previous no-slot result used a controlled empty response; prepare a real no-slot test doctor for the live demonstration. Broader automated evidence below remains separate from the five presentation scenarios.')
[void](ReplaceP 'Source S23 Existing Activity 1 test design. Sources' 'Source S23 supplies the four original detailed cases. The five demonstration scenarios are adapted for this presentation; S24 records prior execution evidence.')
$currentCase='';foreach($p in $body.SelectNodes('w:p',$n)){$text=T $p;if($text -match '^Test Case (TC_\w+)$'){$currentCase=$Matches[1]};if($text.StartsWith('Related scenario:')){if($currentCase.StartsWith('TC_AUTH')){SetT $p ($text.Replace('TS-02','TS-01'))}elseif($currentCase -eq 'TC_BOOKING_002'){SetT $p ($text.Replace('TS-03','TS-04'))}}}
[void](ReplaceP '• Prove empty-cloud installation' '• Prove empty-cloud installation and staging upgrades. Maintain migration reconciliation, the baseline catalog, the main feature ERD, and all six function versions.')
$tocD=$original[45];$tocTexts=@($tocD.SelectNodes('.//w:t',$n));$tocTexts[0].InnerText='Appendix D Main Feature ERD'
$appendixHeading=$original[469].CloneNode($true);SetT $appendixHeading 'Appendix D Main Feature ERD';$pb=$appendixHeading.SelectSingleNode('w:pPr/w:pageBreakBefore',$n);if($pb){[void]$pb.ParentNode.RemoveChild($pb)}
$intro=$original[470].CloneNode($true);SetT $intro 'Nine central tables show account profiles, directory doctors, schedules, consultations, medical records, and prescription orders/items. Selected columns and foreign keys are shown; supporting operational and platform tables are omitted. [S5, S11]'
$picture=$original[481].CloneNode($true);$cx=11155680;$cy=[long][math]::Round($cx*1650/2600)
foreach($extent in $picture.SelectNodes('.//wp:extent|.//a:xfrm/a:ext',$n)){$extent.SetAttribute('cx',[string]$cx);$extent.SetAttribute('cy',[string]$cy)}
$picture.SelectSingleNode('.//wp:docPr',$n).SetAttribute('descr','Main feature ERD showing nine central tables and nine selected declared foreign-key relationships.')
$caption=$original[482].CloneNode($true);SetT $caption 'Figure D1 Main feature ERD with selected keys and relationships'
$anchor=$original[469];foreach($newNode in @($original[479].CloneNode($true),$appendixHeading,$intro,$picture,$caption,$original[562].CloneNode($true))){[void]$body.InsertBefore($newNode,$anchor)}
for($i=469;$i -le 562;$i++){[void]$body.RemoveChild($original[$i])}
[void](ReplaceP '[S11] Complete physical ERD' '[S11] Appendix D main feature ERD. Nine tables and selected keys/relationships validated against supabase/baseline/catalog.json.')
[void](ReplaceP '[S23] Activity1_' '[S23] Activity1_CareNavigator_PH_Test_Scenarios_and_Test_Cases.docx. Four original detailed cases; this revision selects five demonstration scenarios.')
[void](ReplaceP '[S24] 16 October' '[S24] 16 October 2026 verification report in output/final_project; evidence in tmp/documentation_accuracy_20261016 and tmp/documentation_update_20261016.')
[xml]$rels=$utf8.GetString($parts['word/_rels/document.xml.rels']);$rn=[Xml.XmlNamespaceManager]::new($rels.NameTable);$rn.AddNamespace('p','http://schemas.openxmlformats.org/package/2006/relationships')
$retained=$rels.SelectSingleNode('//p:Relationship[@Id="rIdCareDoc110"]',$rn)
$parts['word/'+$retained.Target]=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'main_feature_erd.png'))
$used=@($d.SelectNodes('//@r:embed',$n)|ForEach-Object {$_.Value})
foreach($rel in @($rels.SelectNodes('//p:Relationship',$rn))){if($rel.Id -match '^rIdCareDoc1\d\d$' -and $rel.Type.EndsWith('/image') -and $rel.Id -notin $used){$parts.Remove('word/'+$rel.Target);[void]$rel.ParentNode.RemoveChild($rel)}}
$parts['word/_rels/document.xml.rels']=$utf8.GetBytes($rels.OuterXml)
if($HeadingPages){
 $lookup=@{};foreach($h in (Get-Content -Raw -LiteralPath $HeadingPages -Encoding UTF8|ConvertFrom-Json)){$lookup[$h.text]=$h.page}
 $tocMap=@{'Chapter 1 Project Overview'='PROJECT OVERVIEW';'  Introduction'='PROJECT OVERVIEW';'  Objectives and significance'='Project Objectives and Significance';'  Scope and limitations'='Scope of the Project';'Chapter 2 System Analysis and Design'='SYSTEM ANALYSIS AND DESIGN';'  System description and architecture'='SYSTEM ANALYSIS AND DESIGN';'  System flow and lifecycle'='System Flow';'  Use case diagram'='Use Case Diagram';'  Database design and tables'='Database Design';'  User interface design'='User Interface Design';'Chapter 3 System Development'='SYSTEM DEVELOPMENT';'  Tools and technologies'='SYSTEM DEVELOPMENT';'  Development process'='Development Process';'  Deployment and reproducibility'='Deployment and Reproducibility';'Chapter 4 Results and Testing'='RESULTS AND TESTING';'  System features'='RESULTS AND TESTING';'  Functional testing'='Functional Testing';'  Detailed test cases'='Test Case TC_AUTH_001';'  Evaluation and verification'='Evaluation and Recorded Verification';'Chapter 5 Conclusion and Recommendations'='CONCLUSION AND RECOMMENDATIONS';'Appendix A Screenshots of the Application'='Appendix A Screenshots of the Application';'Appendix B Source Code Snippets'='Appendix B Source Code Snippets';'Appendix C User Manual'='Appendix C User Manual';'Appendix D Main Feature ERD'='Appendix D Main Feature ERD';'Research References'='Research References';'Project References'='Project References'}
 foreach($toc in $body.SelectNodes('w:p[w:pPr/w:tabs/w:tab[@w:leader="dot"]]',$n)){$texts=@($toc.SelectNodes('.//w:t',$n));$label=$texts[0].InnerText;if(-not $tocMap.ContainsKey($label) -or -not $lookup.ContainsKey($tocMap[$label])){throw ('Missing contents target '+$label)};$texts[-1].InnerText=[string]$lookup[$tocMap[$label]]}
}
if($PageCount -gt 0){[xml]$app=$utf8.GetString($parts['docProps/app.xml']);($app.DocumentElement.ChildNodes|Where-Object {$_.LocalName -eq 'Pages'}).InnerText=[string]$PageCount;$parts['docProps/app.xml']=$utf8.GetBytes($app.OuterXml)}
$parts['word/document.xml']=$utf8.GetBytes($d.OuterXml)
$path=Join-Path $PSScriptRoot 'MAD_Final_Project_Documentation_CareNavigator_PH_Demo.docx'
$stream=[IO.File]::Open($path,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite);$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
foreach($key in $parts.Keys){$entry=$archive.CreateEntry($key,[IO.Compression.CompressionLevel]::Optimal);$s=$entry.Open();$s.Write($parts[$key],0,$parts[$key].Length);$s.Dispose()};$archive.Dispose();$stream.Dispose()
Write-Output 'Revised five scenarios, retained four detailed cases, and replaced the full ERD appendix with one main feature diagram.'
