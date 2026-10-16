param([string]$HeadingPages)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskDirectory=Join-Path $PSScriptRoot 'test-case-revision'
[void](New-Item -ItemType Directory -Force -Path $taskDirectory)
$existing='E:\Codes\CareNavigatorPh\output\final_project\MAD_Final_Project_Documentation_CareNavigator_PH.docx'
$reference=Join-Path $taskDirectory 'documentation-before-test-cases.docx'
if(-not (Test-Path -LiteralPath $reference)){Copy-Item -LiteralPath $existing -Destination $reference}
$sourceCases='C:\Users\Neila\Downloads\Activity1_CareNavigator_PH_Test_Scenarios_and_Test_Cases.docx'
$caseHash=(Get-FileHash -LiteralPath $sourceCases -Algorithm SHA256).Hash
$utf8=[System.Text.UTF8Encoding]::new($false)
$w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
function LoadParts([string]$path){
  $zip=[System.IO.Compression.ZipFile]::OpenRead($path);$map=@{}
  foreach($entry in $zip.Entries){$stream=$entry.Open();$memory=[System.IO.MemoryStream]::new();$stream.CopyTo($memory);$stream.Dispose();$map[$entry.FullName]=$memory.ToArray();$memory.Dispose()}
  $zip.Dispose();return $map
}
$parts=LoadParts $reference
$caseParts=LoadParts $sourceCases
[xml]$caseDoc=$utf8.GetString($caseParts['word/document.xml'])
$caseNs=[System.Xml.XmlNamespaceManager]::new($caseDoc.NameTable);$caseNs.AddNamespace('w',$w)
function CaseText($node){
  $paragraphs=foreach($paragraph in $node.SelectNodes('.//w:p',$caseNs)){
    $value=[System.Text.StringBuilder]::new()
    foreach($piece in $paragraph.SelectNodes('.//w:t|.//w:br|.//w:tab',$caseNs)){
      if($piece.LocalName -eq 't'){[void]$value.Append($piece.InnerText)}else{[void]$value.Append("`n")}
    }
    $value.ToString()
  }
  return ($paragraphs -join "`n").Trim()
}
$caseTables=@($caseDoc.SelectNodes('//w:body/w:tbl',$caseNs))
$scenarios=@(foreach($row in $caseTables[1].SelectNodes('w:tr[position()>1]',$caseNs)){
  $cells=$row.SelectNodes('w:tc',$caseNs)
  [pscustomobject]@{id=(CaseText $cells[0]);description=(CaseText $cells[1])}
})
$cases=@(foreach($table in $caseTables[2..5]){
  $fields=@{}
  foreach($row in $table.SelectNodes('w:tr[position()>1]',$caseNs)){
    $cells=$row.SelectNodes('w:tc',$caseNs);$fields[(CaseText $cells[0])]=CaseText $cells[1]
  }
  [pscustomobject]@{id=$fields['Test Case ID'];title=$fields['Title'];scenario=$fields['Related Scenario'];preconditions=$fields['Preconditions'];steps=$fields['Test Steps'];data=$fields['Test Data'];expected=$fields['Expected Result']}
})
if($scenarios.Count -ne 15 -or $cases.Count -ne 4){throw 'Unexpected test-case source structure'}
function NumberedItems([string]$value){return @([regex]::Split($value,'(?:^|\r?\n|(?<=\S))\s*\d+\.\s+') | Where-Object {$_.Trim()} | ForEach-Object {$_.Trim()})}
$oldData=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'content.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$oldMatrix=($oldData.pages | Where-Object {$_.title -eq 'Functional Testing'}).blocks[1].table
$pages=@()
$pages += [pscustomobject]@{title='Functional Testing';blocks=@(
  @{p='The test design follows the existing Activity 1 CareNavigator PH Test Scenarios and Test Cases document. Its 15 scenarios identify the functions to verify. Four detailed cases define positive and negative checks for TS-02 (sign-in) and TS-03 (in-person reservation). The original scenario and test-case identifiers are retained. [S23]'},
  @{p='Activity 1 supplies expected outcomes but no actual results, execution dates, or pass/fail records. The cases below are therefore documented test designs. The recorded implementation evidence appears separately under Evaluation and Recorded Verification and is not assigned as a result for these four cases.'},
  @{h2='Test Scenarios TS-01 to TS-08'},
  @{table=@{widths=@(1050,8310);font=11;headers=@('ID','Test scenario');rows=@($scenarios[0..7] | ForEach-Object {,@($_.id,$_.description)})}},
  @{source='Source S23 Existing Activity 1 test design supplied by the author.'}
)}
$pages += [pscustomobject]@{title='Test Scenarios TS-09 to TS-15';blocks=@(
  @{table=@{widths=@(1050,8310);font=11;headers=@('ID','Test scenario');rows=@($scenarios[8..14] | ForEach-Object {,@($_.id,$_.description)})}},
  @{h2='Detailed Case Coverage'},
  @{p='TS-02 is represented by TC_AUTH_001 and TC_AUTH_002. TS-03 is represented by TC_BOOKING_001 and TC_BOOKING_002. The other 13 scenarios remain scenario-level coverage in Activity 1; that document does not provide a detailed case for each one.'},
  @{p='The TS-03 cases concern in-person appointments and preserve the existing 24-hour minimum reservation lead time. New online requests follow hospital review before a slot is reserved, as described in Chapter 2. Additional online, timing, security, and integration checks are summarized after the four original cases.'},
  @{source='Source S23 Existing Activity 1 test design. Sources S4 S5 S10 S17 provide supplementary workflow requirements.'}
)}
foreach($case in $cases){
  $positive=$case.id -in @('TC_AUTH_001','TC_BOOKING_001')
  $dataText=switch($case.id){
    'TC_AUTH_001' {'Active patient fixture qa.patient@carenavigator.test and its correct configured test password.'}
    'TC_AUTH_002' {'Existing patient fixture qa.patient@carenavigator.test and a deliberately incorrect password.'}
    'TC_BOOKING_001' {'Hospital: verified and operating fixture. Clinician: eligible doctor. Concern: Recurring headache for two days. Slot: 48 hours ahead.'}
    'TC_BOOKING_002' {'Clinician: no qualifying future slots. Search window: next 30 days. Minimum lead time: 24 hours (boundary/edge data).'}
  }
  $pages += [pscustomobject]@{title=('Test Case '+$case.id);blocks=@(
    @{h2=$case.title},
    @{p=('Related scenario: '+$case.scenario+'. Case type: '+$(if($positive){'Positive / happy path.'}else{'Negative / error path.'}))},
    @{h3='Preconditions'},@{steps=(NumberedItems $case.preconditions)},
    @{h3='Test Data'},@{p=$dataText},
    @{h3='Test Steps'},@{steps=(NumberedItems $case.steps)},
    @{h3='Expected Results'},@{steps=(NumberedItems $case.expected)},
    @{source='Execution record: Actual result, execution date, tester, and pass/fail outcome were not supplied in Activity 1. Source S23.'}
  )}
}
$pages += [pscustomobject]@{title='Supplementary Workflow Verification';blocks=@(
  @{p='These checks retain the earlier workflow summary and its 12 October 2026 evidence. They do not assign execution results to the Activity 1 cases.'},
  @{table=@{widths=@(2500,4160,2700);font=10;headers=@('Verification area','Expected behavior','Recorded evidence or outstanding check');rows=@($oldMatrix.rows | ForEach-Object {,@($_[1],$_[2],$_[3])})}},
  @{source='Sources S5 S10 S13 S16 S17 S19.'}
)}
$builder=[System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'build_docx.ps1'))
$functionStart=$builder.IndexOf('function X(');$functionEnd=$builder.IndexOf('$coverReplacements=')
Invoke-Expression $builder.Substring($functionStart,$functionEnd-$functionStart)
$script:content=[System.Text.StringBuilder]::new();$script:needsPageBreak=$false
foreach($page in $pages){
  PageBreak;Heading $page.title 1
  foreach($block in $page.blocks){
    if($block.p){AddP $block.p}
    elseif($block.h2){Heading $block.h2 2}
    elseif($block.h3){Heading $block.h3 3}
    elseif($block.table){Table $block.table}
    elseif($block.source){[void]$content.Append((P $block.source 'Normal' 18 $false 'left' 80 0))}
    elseif($block.steps){
      $i=1
      foreach($item in $block.steps){$paragraph=P ([string]$i+'. '+$item) 'ListParagraph' 24 $false 'left' 0 75;$paragraph=$paragraph.Replace('<w:widowControl/>','<w:widowControl/><w:ind w:left="360" w:hanging="240"/>');[void]$content.Append($paragraph);$i++}
    }
  }
}
[xml]$doc=$utf8.GetString($parts['word/document.xml'])
$ns=[System.Xml.XmlNamespaceManager]::new($doc.NameTable);$ns.AddNamespace('w',$w)
$body=$doc.SelectSingleNode('//w:body',$ns)
function ParagraphText($node){return ($node.SelectNodes('.//w:t',$ns) | ForEach-Object {$_.InnerText}) -join ''}
function BodyHeading([string]$text){return @($body.SelectNodes('w:p[w:pPr/w:pStyle[@w:val="Heading1"]]',$ns) | Where-Object {(ParagraphText $_) -eq $text})[0]}
function NewFragment([string]$xml){
  [xml]$wrapper=('<root xmlns:w="'+$w+'">'+$xml+'</root>')
  $fragment=$doc.CreateDocumentFragment()
  foreach($child in @($wrapper.DocumentElement.ChildNodes)){[void]$fragment.AppendChild($doc.ImportNode($child,$true))}
  return ,$fragment
}
$start=BodyHeading 'Functional Testing';$end=BodyHeading 'Evaluation and Recorded Verification'
if(-not $start -or -not $end){throw 'Chapter 4 anchors missing'}
$toRemove=@();$current=$start
while($current -and $current -ne $end){$toRemove+=$current;$current=$current.NextSibling}
if($current -ne $end){throw 'Chapter 4 region is not contiguous'}
$fragment=NewFragment $content.ToString()
[void]$body.InsertBefore($fragment,$start)
foreach($node in $toRemove){[void]$body.RemoveChild($node)}
$sourceDescription='[S23] Activity1_CareNavigator_PH_Test_Scenarios_and_Test_Cases.docx. Author-supplied scenarios and four detailed cases; no execution results supplied.'
$sourceParagraph=NewFragment (P $sourceDescription 'Normal' 19 $false 'left' 0 80)
$lastReference=@($body.SelectNodes('w:p',$ns) | Where-Object {(ParagraphText $_).StartsWith('[S22]')})[0]
if(-not $lastReference){throw 'System source reference anchor missing'}
[void]$body.InsertAfter($sourceParagraph,$lastReference)
$closingNote=@($body.SelectNodes('w:p',$ns) | Where-Object {(ParagraphText $_).StartsWith('Raw deployed-source snapshots')})[0]
if($closingNote){foreach($size in $closingNote.SelectNodes('.//w:rPr/w:sz',$ns)){[void]$size.SetAttribute('val',$w,'19')}}
$tocParas=@($body.SelectNodes('w:p[w:pPr/w:tabs/w:tab[@w:leader="dot"]]',$ns))
$functionalToc=@($tocParas | Where-Object {(ParagraphText $_).StartsWith('  Functional testing')})[0]
$newToc=$functionalToc.CloneNode($true);$newTocTexts=@($newToc.SelectNodes('.//w:t',$ns));$newTocTexts[0].InnerText='  Detailed test cases';$newTocTexts[-1].InnerText='21';[void]$body.InsertAfter($newToc,$functionalToc)
$pageLookup=@{}
if($HeadingPages){foreach($heading in (Get-Content -LiteralPath $HeadingPages -Raw -Encoding UTF8 | ConvertFrom-Json)){$pageLookup[$heading.text]=$heading.page}}
else{
  foreach($heading in (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'render-revision-verified\heading-pages.json') -Raw -Encoding UTF8 | ConvertFrom-Json)){$pageLookup[$heading.text]=[int]$heading.page+$(if($heading.page -ge 20){6}else{0})}
  $pageLookup['Test Case TC_AUTH_001']=21
}
$tocMap=@{
  'Chapter 1 Project Overview'='PROJECT OVERVIEW';'  Introduction'='PROJECT OVERVIEW';'  Objectives and significance'='Project Objectives and Significance';'  Scope and limitations'='Scope of the Project';
  'Chapter 2 System Analysis and Design'='SYSTEM ANALYSIS AND DESIGN';'  System description and architecture'='SYSTEM ANALYSIS AND DESIGN';'  System flow and lifecycle'='System Flow';'  Use case diagram'='Use Case Diagram';'  Database design and tables'='Database Design';'  User interface design'='User Interface Design';
  'Chapter 3 System Development'='SYSTEM DEVELOPMENT';'  Tools and technologies'='SYSTEM DEVELOPMENT';'  Development process'='Development Process';'  Deployment and reproducibility'='Deployment and Reproducibility';
  'Chapter 4 Results and Testing'='RESULTS AND TESTING';'  System features'='RESULTS AND TESTING';'  Functional testing'='Functional Testing';'  Detailed test cases'='Test Case TC_AUTH_001';'  Evaluation and verification'='Evaluation and Recorded Verification';
  'Chapter 5 Conclusion and Recommendations'='CONCLUSION AND RECOMMENDATIONS';'Appendix A Screenshots of the Application'='Appendix A Screenshots of the Application';'Appendix B Source Code Snippets'='Appendix B Source Code Snippets';'Appendix C User Manual'='Appendix C User Manual';'Appendix D Complete Physical ERD'='Appendix D Complete Physical ERD';'Research References'='Research References';'Project References'='Project References'
}
foreach($toc in $body.SelectNodes('w:p[w:pPr/w:tabs/w:tab[@w:leader="dot"]]',$ns)){
  $texts=@($toc.SelectNodes('.//w:t',$ns));$label=$texts[0].InnerText
  if($tocMap.ContainsKey($label) -and $pageLookup.ContainsKey($tocMap[$label])){$texts[-1].InnerText=[string]$pageLookup[$tocMap[$label]]}
}
$parts['word/document.xml']=$utf8.GetBytes($doc.OuterXml)
[xml]$app=$utf8.GetString($parts['docProps/app.xml']);$appPage=$app.DocumentElement.ChildNodes | Where-Object {$_.LocalName -eq 'Pages'};$appPage.InnerText='63';$parts['docProps/app.xml']=$utf8.GetBytes($app.OuterXml)
$candidate=Join-Path $taskDirectory 'MAD_Final_Project_Documentation_CareNavigator_PH.docx'
$stream=[System.IO.File]::Open($candidate,[System.IO.FileMode]::Create,[System.IO.FileAccess]::ReadWrite)
$zip=[System.IO.Compression.ZipArchive]::new($stream,[System.IO.Compression.ZipArchiveMode]::Create,$false)
foreach($key in $parts.Keys){$entry=$zip.CreateEntry($key,[System.IO.Compression.CompressionLevel]::Optimal);$entryStream=$entry.Open();$entryStream.Write($parts[$key],0,$parts[$key].Length);$entryStream.Dispose()}
$zip.Dispose();$stream.Dispose()
if((Get-FileHash -LiteralPath $sourceCases -Algorithm SHA256).Hash -ne $caseHash){throw 'Activity 1 source changed'}
$proof=[pscustomobject]@{source=$sourceCases;sourceSha256=$caseHash;sourceUnchanged=$true;scenarioIds=@($scenarios.id);caseIds=@($cases.id);replacementContentPages=$pages.Count;testCasePasswords='Represented by fixture roles instead of literal values';candidate=$candidate;originalDocumentation=$reference}
$proof | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $taskDirectory 'case-integration-qa.json') -Encoding UTF8
$pages | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $taskDirectory 'chapter4-content.json') -Encoding UTF8
Write-Output ('Updated Chapter 4: {0} scenarios, {1} detailed cases, {2} planned content pages' -f $scenarios.Count,$cases.Count,$pages.Count)
