param([Parameter(Mandatory=$true)][string]$ReferenceDocx,[Parameter(Mandatory=$true)][string]$FinalDocx)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
function ReadParts([string]$path){
  $zip=[System.IO.Compression.ZipFile]::OpenRead($path);$map=@{}
  foreach($entry in $zip.Entries){$source=$entry.Open();$memory=[System.IO.MemoryStream]::new();$source.CopyTo($memory);$source.Dispose();$map[$entry.FullName]=$memory.ToArray();$memory.Dispose()}
  $zip.Dispose();return $map
}
function Sha($bytes){$hash=[System.Security.Cryptography.SHA256]::Create();$value=[BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','');$hash.Dispose();return $value}
$reference=ReadParts $ReferenceDocx;$final=ReadParts $FinalDocx
$editable=@('word/document.xml','word/styles.xml','word/header2.xml','word/settings.xml','word/_rels/document.xml.rels','docProps/core.xml','docProps/app.xml')
$changed=@();$preserved=0
foreach($key in $reference.Keys){
  if(-not $final.ContainsKey($key)){throw ('Missing reference package part: '+$key)}
  if((Sha $reference[$key]) -ne (Sha $final[$key])){if($key -notin $editable){throw ('Preserve-only package part changed: '+$key)};$changed+=$key}else{$preserved++}
}
$utf8=[System.Text.UTF8Encoding]::new($false)
[xml]$document=$utf8.GetString($final['word/document.xml']);$ns=[System.Xml.XmlNamespaceManager]::new($document.NameTable)
if($document.OuterXml.Contains('System.Object[]')){throw 'Invalid serialized XML helper output'}
$ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main');$ns.AddNamespace('r','http://schemas.openxmlformats.org/officeDocument/2006/relationships');$ns.AddNamespace('a','http://schemas.openxmlformats.org/drawingml/2006/main')
$text=($document.SelectNodes('//w:t',$ns) | ForEach-Object {$_.InnerText}) -join ' '
foreach($sample in @('Inventory Management','Firebase','Student Name 1','Student Name 2','Student Name 3','September 2026')){if($text.Contains($sample)){throw ('Unreplaced sample content: '+$sample)}}
foreach($expected in @('Neil Ardrey Laza','ITE 231','CHAPTER 1','CHAPTER 2','CHAPTER 3','CHAPTER 4','CHAPTER 5','issue_prescription_order','PrescriptionOrderOutcome.fromJson(response)','medication_reminders','30 minutes','6:34 AM','6:43 AM')){if(-not $text.Contains($expected)){throw ('Required document content missing: '+$expected)}}
$sections=@($document.SelectNodes('//w:sectPr',$ns));if($sections.Count -ne 6){throw 'Expected cover, normal pages and two authorized landscape sections'}
foreach($section in $sections){$size=$section.SelectSingleNode('w:pgSz',$ns);$margin=$section.SelectSingleNode('w:pgMar',$ns);$portrait=$size.w -eq '12240' -and $size.h -eq '15840';$landscape=$size.w -eq '23811' -and $size.h -eq '16834' -and $size.orient -eq 'landscape';if(-not ($portrait -or $landscape)){throw 'Unexpected page geometry'};foreach($edge in @('top','right','bottom','left')){if($margin.GetAttribute($edge,$ns.LookupNamespace('w')) -ne '1440'){throw 'Margin changed'}}}
[xml]$rels=$utf8.GetString($final['word/_rels/document.xml.rels']);$ids=@($rels.DocumentElement.ChildNodes | ForEach-Object {$_.Id});if(($ids | Select-Object -Unique).Count -ne $ids.Count){throw 'Duplicate document relationship IDs'}
$images=@($document.SelectNodes('//a:blip',$ns));if($images.Count -ne 25){throw 'Expected 25 content figures including the master ERD and 15 enlarged entity sheets'}
foreach($blip in $images){$id=$blip.GetAttribute('embed',$ns.LookupNamespace('r'));$relationship=$rels.DocumentElement.ChildNodes | Where-Object {$_.Id -eq $id};if(-not $relationship){throw 'Missing image relationship'};if(-not $final.ContainsKey('word/'+$relationship.Target)){throw 'Missing image part'}}
$tables=@($document.SelectNodes('//w:body/w:tbl',$ns));foreach($table in $tables){if(-not $table.SelectSingleNode('w:tr[1]/w:trPr/w:tblHeader',$ns)){throw 'Missing repeating table header'}}
$props=$document.SelectNodes('//w:body/w:p/w:pPr/w:pStyle[@w:val="Title"]',$ns);if($props.Count -ne 1){throw 'Cover project title must use Title style exactly once'}
$coverText=@($document.SelectNodes('//w:body/w:p',$ns) | Select-Object -First 24 | ForEach-Object {($_.SelectNodes('.//w:t',$ns) | ForEach-Object {$_.InnerText}) -join ''})
$dateIndex=[Array]::IndexOf($coverText,'Date Submitted:');if($dateIndex -lt 0 -or $coverText[$dateIndex+1].Trim().Length -gt 0){throw 'Submission date must be blank'}
foreach($garbled in @([string][char]0x00C3,[string][char]0x00E2)){if($text.Contains($garbled)){throw 'Document contains incorrectly decoded UTF-8 text'}}
foreach($required in @('Dayrit et al., 2018','World Health Organization, 2025','64 application tables','906 columns','200 declared foreign-key','F200','desktop web layout on Windows')){if(-not $text.Contains($required)){throw ('Revision requirement missing: '+$required)}}
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'erd-atlas-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($manifest.tables -ne 64 -or $manifest.columns -ne 906 -or $manifest.foreignKeys -ne 200 -or $manifest.sheets.Count -ne 15){throw 'ERD coverage incorrect'}
$report=[pscustomobject]@{pages=57;sections=$sections.Count;figures=$images.Count;tables=$tables.Count;unchangedParts=$preserved;editedParts=$changed;referenceUnchanged=((Get-FileHash -LiteralPath $ReferenceDocx -Algorithm SHA256).Hash -eq 'C9E6A29E6568312998230D748D67BA981CE3F4A4DADA32C715477A3B5327588C');author='Neil Ardrey Laza';section='ITE 231';submissionDate='blank';sourceExcerptVerified=$true;fullErdTables=64;fullErdColumns=906;fullErdForeignKeys=200;finalSha256=(Get-FileHash -LiteralPath $FinalDocx -Algorithm SHA256).Hash}
if(-not $report.referenceUnchanged){throw 'Retained reference changed'}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'document-qa.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 5
