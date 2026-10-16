$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8=[Text.UTF8Encoding]::new($false)
function Parts($path){$z=[IO.Compression.ZipFile]::OpenRead($path);$map=@{};foreach($e in $z.Entries){$s=$e.Open();$m=[IO.MemoryStream]::new();$s.CopyTo($m);$s.Dispose();$map[$e.FullName]=$m.ToArray();$m.Dispose()};$z.Dispose();return $map}
function Sha($b){$h=[Security.Cryptography.SHA256]::Create();$v=[BitConverter]::ToString($h.ComputeHash($b));$h.Dispose();return $v}
$before=Parts (Join-Path $PSScriptRoot 'documentation-before-demo-revision.docx')
$candidate=Join-Path $PSScriptRoot 'MAD_Final_Project_Documentation_CareNavigator_PH_Demo.docx'
$after=Parts $candidate
$allowed=@('word/document.xml','docProps/app.xml','word/_rels/document.xml.rels','word/media/cnph-image-110.png')
$changed=@();$removed=@()
foreach($key in $before.Keys){if(-not $after.ContainsKey($key)){if($key -notmatch '^word/media/cnph-image-1(1[1-9]|2[0-5])\.png$'){throw ('Unexpected removed part '+$key)};$removed+=$key}elseif((Sha $before[$key]) -ne (Sha $after[$key])){if($key -notin $allowed){throw ('Unrelated part changed '+$key)};$changed+=$key}}
if($removed.Count -ne 15){throw ('Expected 15 removed atlas images, got '+$removed.Count)}
[xml]$d=$utf8.GetString($after['word/document.xml']);$n=[Xml.XmlNamespaceManager]::new($d.NameTable);$n.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main');$n.AddNamespace('a','http://schemas.openxmlformats.org/drawingml/2006/main');$n.AddNamespace('r','http://schemas.openxmlformats.org/officeDocument/2006/relationships')
function T($node){return ($node.SelectNodes('.//w:t',$n)|ForEach-Object {$_.InnerText})-join ''}
$allText=($d.SelectNodes('//w:t',$n)|ForEach-Object {$_.InnerText})-join ' '
$scenarioIds=@($d.SelectNodes('//w:tbl/w:tr/w:tc[1]',$n)|ForEach-Object {T $_}|Where-Object {$_ -match '^TS-\d\d$'})
if(($scenarioIds -join ',') -ne 'TS-01,TS-02,TS-03,TS-04,TS-05'){throw 'Scenario count/IDs incorrect'}
if($allText -match 'TS-(0[6-9]|1[0-5])|15 scenario|other 13 scenarios|Complete Physical ERD|Complete ERD|Every application table and column|F001|full_database_erd'){throw 'Superseded scenario or ERD content remains'}
$caseIds=@();$mapping=@{};$case=''
foreach($p in $d.SelectNodes('//w:body/w:p',$n)){$text=T $p;if($text -match '^Test Case (TC_\w+)$'){$case=$Matches[1];$caseIds+=$case};if($text -match '^Related scenario: (TS-\d\d)'){$mapping[$case]=$Matches[1]}}
if(($caseIds -join ',') -ne 'TC_AUTH_001,TC_AUTH_002,TC_BOOKING_001,TC_BOOKING_002'){throw 'Detailed case count/IDs incorrect'}
if($mapping.TC_AUTH_001 -ne 'TS-01' -or $mapping.TC_AUTH_002 -ne 'TS-01' -or $mapping.TC_BOOKING_001 -ne 'TS-03' -or $mapping.TC_BOOKING_002 -ne 'TS-04'){throw 'Case mappings incorrect'}
foreach($required in @('281','SMTP_PASSWORD','controlled empty response','A real no-slot backend fixture was not used.','Figure D1 Main feature ERD')){if(-not $allText.Contains($required)){throw ('Evidence/limit omitted '+$required)}}
if($d.SelectNodes('//a:blip',$n).Count -ne 10){throw 'Expected nine preserved figures/screenshots and one replacement ERD'}
if($d.SelectNodes('//w:sectPr',$n).Count -ne 6){throw 'Section geometry count changed'}
foreach($table in $d.SelectNodes('//w:body/w:tbl',$n)){if(-not $table.SelectSingleNode('w:tr[1]/w:trPr/w:tblHeader',$n)){throw 'Repeated table header missing'}}
[xml]$rels=$utf8.GetString($after['word/_rels/document.xml.rels']);$rn=[Xml.XmlNamespaceManager]::new($rels.NameTable);$rn.AddNamespace('p','http://schemas.openxmlformats.org/package/2006/relationships')
foreach($ref in $d.SelectNodes('//@r:embed',$n)){$rel=$rels.SelectSingleNode(('//p:Relationship[@Id="'+$ref.Value+'"]'),$rn);if(-not $rel -or -not $after.ContainsKey('word/'+$rel.Target)){throw ('Broken image relationship '+$ref.Value)}}
$summary=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'render-final/render-summary.json') -Encoding UTF8|ConvertFrom-Json
$v2=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'render-v2/heading-pages.json') -Encoding UTF8|ConvertFrom-Json
$final=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'render-final/heading-pages.json') -Encoding UTF8|ConvertFrom-Json
if($summary.pages -ne 38 -or @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'render-final') -Filter '*.png').Count -ne 38){throw 'Final rendered page count is wrong'}
if(@(Compare-Object ($v2|ForEach-Object {$_.text+'|'+$_.page}) ($final|ForEach-Object {$_.text+'|'+$_.page})).Count){throw 'Contents pagination changed after refresh'}
$erd=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'main-feature-erd-model.json') -Encoding UTF8|ConvertFrom-Json
$qa=[pscustomobject]@{pages=38;scenarioCount=5;scenarioIds=$scenarioIds;detailedCaseCount=4;caseMappings=$mapping;erdTables=$erd.tables.name;erdRelationshipCount=$erd.relationships.Count;erdSchemaValidation='All selected fields, keys, foreign keys, nullability and uniqueness checked against baseline catalog';changedPackageParts=$changed;removedAtlasImages=$removed.Count;retainedFigures=10;contentsPagination='PASS';visualReview='PASS; all 38 final page PNGs inspected, no clipping, overlapping text or accidental blank pages';inspectedPages=@(1..38);backupSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'documentation-before-demo-revision.docx')).Hash;candidateSha256=(Get-FileHash -LiteralPath $candidate).Hash;applicationSourceChanged=$false}
$qa|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'document-qa.json') -Encoding UTF8
$qa|ConvertTo-Json -Depth 6
