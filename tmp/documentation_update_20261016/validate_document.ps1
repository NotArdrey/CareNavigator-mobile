param([string]$RenderDirectory='E:\Codes\CareNavigatorPh\tmp\documentation_update_20261016\render-v2')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8=[Text.UTF8Encoding]::new($false)
function Parts([string]$path){$zip=[IO.Compression.ZipFile]::OpenRead($path);$map=@{};foreach($entry in $zip.Entries){$s=$entry.Open();$m=[IO.MemoryStream]::new();$s.CopyTo($m);$s.Dispose();$map[$entry.FullName]=$m.ToArray();$m.Dispose()};$zip.Dispose();return $map}
function Sha($bytes){$h=[Security.Cryptography.SHA256]::Create();$v=[BitConverter]::ToString($h.ComputeHash($bytes));$h.Dispose();return $v}
$before=Parts (Join-Path $PSScriptRoot 'documentation-before-update.docx')
$after=Parts (Join-Path $PSScriptRoot 'MAD_Final_Project_Documentation_CareNavigator_PH.docx')
$changed=@();foreach($key in $before.Keys){if(-not $after.ContainsKey($key)){throw ('Missing package part '+$key)};if((Sha $before[$key]) -ne (Sha $after[$key])){$changed+=$key}}
if(@($changed | Where-Object {$_ -notin @('word/document.xml','docProps/app.xml') -and -not $_.StartsWith('word/media/')}).Count){throw 'Unrelated package parts changed'}
if(@($changed | Where-Object {$_.StartsWith('word/media/')}).Count -ne 2){throw 'Expected exactly two updated figure media parts'}
if($after.Count -ne $before.Count){throw 'Package inventory changed'}
[xml]$xml=$utf8.GetString($after['word/document.xml'])
$ns=[Xml.XmlNamespaceManager]::new($xml.NameTable);$ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main');$ns.AddNamespace('a','http://schemas.openxmlformats.org/drawingml/2006/main')
$text=($xml.SelectNodes('//w:t',$ns) | ForEach-Object {$_.InnerText}) -join ' '
foreach($required in @('Google Meet','281','28','SMTP_PASSWORD','Seven local SMTP','Valid password recovery','Concurrent scheduling','[S24]','patient_supplied','64 application tables','906 columns','200 declared foreign-key','TC_AUTH_001','TC_AUTH_002','TC_BOOKING_001','TC_BOOKING_002','Neil Ardrey Laza','ITE 231')){if(-not $text.Contains($required)){throw ('Missing content '+$required)}}
foreach($forbidden in @('Jitsi','qa.patient@carenavigator.test','267 tests passed','9 passed, 2 failed','System.Object[]')){if($text.Contains($forbidden)){throw ('Obsolete or invalid content '+$forbidden)}}
if(($xml.SelectNodes('//w:sectPr',$ns)).Count -ne 6){throw 'Section geometry count changed'}
if(($xml.SelectNodes('//a:blip',$ns)).Count -ne 25){throw 'Figure count changed'}
foreach($table in $xml.SelectNodes('//w:body/w:tbl',$ns)){if(-not $table.SelectSingleNode('w:tr[1]/w:trPr/w:tblHeader',$ns)){throw 'Missing repeated table header'}}
$headings=Get-Content -Raw -LiteralPath (Join-Path $RenderDirectory 'heading-pages.json') | ConvertFrom-Json
$summary=Get-Content -Raw -LiteralPath (Join-Path $RenderDirectory 'render-summary.json') | ConvertFrom-Json
if($summary.pages -ne 63){throw 'Expected the preserved 63-page document'}
$originalRender='E:\Codes\CareNavigatorPh\tmp\final_project_doc\test-case-revision\render-final'
$same=@();$different=@()
for($i=1;$i -le $summary.pages;$i++){
  $old=Join-Path $originalRender ('page-'+$i+'.png');$new=Join-Path $RenderDirectory ('page-'+$i+'.png')
  if((Get-FileHash -LiteralPath $old).Hash -eq (Get-FileHash -LiteralPath $new).Hash){$same+=$i}else{$different+=$i}
}
$scenarios=@($xml.SelectNodes('//w:tbl/w:tr/w:tc[1]',$ns) | ForEach-Object {($_.SelectNodes('.//w:t',$ns) | ForEach-Object {$_.InnerText}) -join ''} | Where-Object {$_ -match '^TS-\d\d$'})
if(@($scenarios | Select-Object -Unique).Count -ne 15){throw 'Scenario identifier coverage changed'}
$qa=[pscustomobject]@{pages=$summary.pages;sections=6;figures=25;scenarios=15;detailedCases=4;changedPackageParts=$changed;pixelIdenticalPages=$same;changedPageImages=$different;backupSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'documentation-before-update.docx')).Hash;candidateSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'MAD_Final_Project_Documentation_CareNavigator_PH.docx')).Hash;layoutReview='Pending final PNG inspection';applicationSourceChanged=$false}
$qa | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'final-document-qa.json') -Encoding UTF8
$qa | ConvertTo-Json -Depth 6
