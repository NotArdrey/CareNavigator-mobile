$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing
$utf8=[System.Text.UTF8Encoding]::new($false)
$w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
function Parts([string]$path){
  $zip=[System.IO.Compression.ZipFile]::OpenRead($path);$map=@{}
  foreach($entry in $zip.Entries){$s=$entry.Open();$m=[System.IO.MemoryStream]::new();$s.CopyTo($m);$s.Dispose();$map[$entry.FullName]=$m.ToArray();$m.Dispose()}
  $zip.Dispose();return $map
}
function Hash($bytes){$h=[System.Security.Cryptography.SHA256]::Create();$digest=[BitConverter]::ToString($h.ComputeHash($bytes));$h.Dispose();return $digest}
$old=Parts (Join-Path $PSScriptRoot 'documentation-before-test-cases.docx')
$new=Parts (Join-Path $PSScriptRoot 'MAD_Final_Project_Documentation_CareNavigator_PH.docx')
$changed=@()
foreach($key in $old.Keys){if(-not $new.ContainsKey($key)){throw ('Missing part '+$key)};if((Hash $old[$key]) -ne (Hash $new[$key])){$changed+=$key}}
if(@($changed | Where-Object {$_ -notin @('word/document.xml','docProps/app.xml')}).Count){throw 'An unrelated document part changed'}
[xml]$doc=$utf8.GetString($new['word/document.xml'])
$ns=[System.Xml.XmlNamespaceManager]::new($doc.NameTable);$ns.AddNamespace('w',$w)
$text=($doc.SelectNodes('//w:t',$ns) | ForEach-Object {$_.InnerText}) -join ' '
$chapters=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'chapter4-content.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($scenario in @($chapters[0].blocks[3].table.rows)+@($chapters[1].blocks[0].table.rows)){
  if(-not $text.Contains($scenario[0]) -or -not $text.Contains($scenario[1])){throw 'A supplied scenario is missing or changed'}
}
foreach($case in $chapters | Where-Object {$_.title.StartsWith('Test Case')}){
  foreach($block in $case.blocks){
    if($block.p -and -not $text.Contains($block.p)){throw 'Test-case prose missing'}
    if($block.h2 -and -not $text.Contains($block.h2)){throw 'Test-case title missing'}
    foreach($step in $block.steps){if(-not $text.Contains($step)){throw ('Test-case step missing: '+$step)}}
  }
}
if($doc.OuterXml.Contains('System.Object[]')){throw 'Invalid serialized content'}
if(@($doc.SelectNodes('//w:sectPr',$ns)).Count -ne 6){throw 'Page orientation sections changed'}
$ns.AddNamespace('a','http://schemas.openxmlformats.org/drawingml/2006/main')
if(@($doc.SelectNodes('//a:blip',$ns)).Count -ne 25){throw 'Existing screenshots or ERD images changed'}
foreach($table in $doc.SelectNodes('//w:body/w:tbl',$ns)){if(-not $table.SelectSingleNode('w:tr[1]/w:trPr/w:tblHeader',$ns)){throw 'A table header does not repeat'}}
$headings=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'render-final\heading-pages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$summary=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'render-final\render-summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($summary.pages -ne 63){throw 'Unexpected final pagination'}
$specific=@{'Functional Testing'=19;'Test Scenarios TS-09 to TS-15'=20;'Test Case TC_AUTH_001'=21;'Test Case TC_AUTH_002'=22;'Test Case TC_BOOKING_001'=23;'Test Case TC_BOOKING_002'=24;'Supplementary Workflow Verification'=25;'Evaluation and Recorded Verification'=26;'Project References'=63}
foreach($key in $specific.Keys){if(@($headings | Where-Object {$_.text -eq $key -and $_.page -eq $specific[$key]}).Count -ne 1){throw ('Unexpected heading placement: '+$key)}}
function CropHash([string]$file){
  $image=[System.Drawing.Bitmap]::new($file)
  $region=$(if($image.Width -gt 2000){[System.Drawing.Rectangle]::new(125,145,$image.Width-250,$image.Height-310)}else{[System.Drawing.Rectangle]::new(125,145,1030,1340)})
  $crop=$image.Clone($region,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $memory=[System.IO.MemoryStream]::new();$crop.Save($memory,[System.Drawing.Imaging.ImageFormat]::Png);$hash=Hash $memory.ToArray();$memory.Dispose();$crop.Dispose();$image.Dispose();return $hash
}
$retained=@()
foreach($originalPage in @(1)+(3..18)+(20..56)){
  $revisedPage=$originalPage+$(if($originalPage -ge 20){6}else{0})
  $oldImage=Join-Path (Split-Path $PSScriptRoot) ('render-revision-verified\page-'+$originalPage+'.png')
  $newImage=Join-Path $PSScriptRoot ('render-final\page-'+$revisedPage+'.png')
  $retained += [pscustomobject]@{originalPage=$originalPage;revisedPage=$revisedPage;identicalBody=((CropHash $oldImage) -eq (CropHash $newImage))}
}
$retained | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'retained-page-comparison.json') -Encoding UTF8
$source='C:\Users\Neila\Downloads\Activity1_CareNavigator_PH_Test_Scenarios_and_Test_Cases.docx'
if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne '526E688C250D9B393D14122E7FD0066A92CAB280FDABA14252F730F193C60CF1'){throw 'Activity 1 source changed'}
$qa=[pscustomobject]@{pages=63;scenarios=15;detailedCases=4;caseIds=@('TC_AUTH_001','TC_AUTH_002','TC_BOOKING_001','TC_BOOKING_002');caseResults='No execution results supplied';changedPackageParts=$changed;retainedPageBodiesCompared=$retained.Count;retainedPageBodiesIdentical=@($retained | Where-Object {$_.identicalBody}).Count;retainedPagesNeedingReview=@($retained | Where-Object {-not $_.identicalBody}).revisedPage;sourceUnchanged=$true;sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'MAD_Final_Project_Documentation_CareNavigator_PH.docx') -Algorithm SHA256).Hash}
$qa | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'final-qa.json') -Encoding UTF8
$qa | ConvertTo-Json -Depth 8
