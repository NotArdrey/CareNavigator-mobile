param([Parameter(Mandatory=$true)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$source=Join-Path $WorkspaceRoot 'output\defense\report.docx'
$final=Join-Path $WorkspaceRoot 'output\defense\CareNavigator_PH_Project_Documentation.docx'
$work=Join-Path $WorkspaceRoot 'tmp\defense_build\docx_work'
$resolvedRoot=[IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')+'\'
$resolvedWork=[IO.Path]::GetFullPath($work)
if(-not $resolvedWork.StartsWith($resolvedRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'DOCX work path escaped the workspace.'}
if(Test-Path -LiteralPath $resolvedWork){Remove-Item -LiteralPath $resolvedWork -Recurse -Force}
New-Item -ItemType Directory -Path $resolvedWork|Out-Null
[IO.Compression.ZipFile]::ExtractToDirectory($source,$resolvedWork)

$media=Join-Path $resolvedWork 'word\media'
New-Item -ItemType Directory -Force -Path $media|Out-Null
$images=@(
  @{id='rId2';src=Join-Path $WorkspaceRoot 'assets\images\app_icon.png';target='media/image1.png';name='image1.png'},
  @{id='rId3';src=Join-Path $WorkspaceRoot 'tmp\defense_build\slides_png\Slide5.PNG';target='media/image2.png';name='image2.png'},
  @{id='rId4';src=Join-Path $WorkspaceRoot 'tmp\defense_build\slides_png\Slide7.PNG';target='media/image3.png';name='image3.png'},
  @{id='rId5';src=Join-Path $WorkspaceRoot 'tmp\defense_build\slides_png\Slide8.PNG';target='media/image4.png';name='image4.png'}
)
foreach($img in $images){Copy-Item -LiteralPath $img.src -Destination (Join-Path $media $img.name) -Force}

$relsPath=Join-Path $resolvedWork 'word\_rels\document.xml.rels'
[xml]$rels=Get-Content -Raw $relsPath
$relNs='http://schemas.openxmlformats.org/package/2006/relationships'
foreach($img in $images){
  $node=$rels.Relationships.Relationship|Where-Object{$_.Id -eq $img.id}
  if($null -eq $node){throw "Missing image relationship $($img.id)"}
  $node.SetAttribute('Target',$img.target)
  $node.RemoveAttribute('TargetMode')
}
function Add-Relationship([string]$id,[string]$type,[string]$target){
  $node=$rels.CreateElement('Relationship',$relNs)
  $node.SetAttribute('Id',$id);$node.SetAttribute('Type',$type);$node.SetAttribute('Target',$target)
  [void]$rels.Relationships.AppendChild($node)
}
Add-Relationship 'rId10' 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/header' 'header1.xml'
Add-Relationship 'rId11' 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer' 'footer1.xml'
$utf8=New-Object Text.UTF8Encoding($false)
$rels.Save($relsPath)

$header=@'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="4" w:space="4" w:color="CFDBE2"/></w:pBdr></w:pPr>
    <w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:color w:val="5B7080"/><w:sz w:val="18"/></w:rPr><w:t>CareNavigator PH  |  Project Defense Documentation</w:t></w:r>
  </w:p>
</w:hdr>
'@
$footer=@'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p><w:pPr><w:jc w:val="right"/></w:pPr>
    <w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:color w:val="5B7080"/><w:sz w:val="18"/></w:rPr><w:t xml:space="preserve">CareNavigator PH  |  </w:t></w:r>
    <w:fldSimple w:instr="PAGE"><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:color w:val="5B7080"/><w:sz w:val="18"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple>
  </w:p>
</w:ftr>
'@
[IO.File]::WriteAllText((Join-Path $resolvedWork 'word\header1.xml'),$header,$utf8)
[IO.File]::WriteAllText((Join-Path $resolvedWork 'word\footer1.xml'),$footer,$utf8)

$ctPath=Join-Path $resolvedWork '[Content_Types].xml'
[xml]$ct=Get-Content -Raw -LiteralPath $ctPath
$ctNs='http://schemas.openxmlformats.org/package/2006/content-types'
function Add-Override([string]$part,[string]$contentType){
  if($ct.Types.Override|Where-Object{$_.PartName -eq $part}){return}
  $n=$ct.CreateElement('Override',$ctNs);$n.SetAttribute('PartName',$part);$n.SetAttribute('ContentType',$contentType);[void]$ct.Types.AppendChild($n)
}
Add-Override '/word/header1.xml' 'application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml'
Add-Override '/word/footer1.xml' 'application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml'
$ct.Save($ctPath)

$docPath=Join-Path $resolvedWork 'word\document.xml'
[xml]$xml=Get-Content -Raw $docPath
$nsm=New-Object Xml.XmlNamespaceManager($xml.NameTable)
$wNs='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$rNs='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
$aNs='http://schemas.openxmlformats.org/drawingml/2006/main'
$wpNs='http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
$picNs='http://schemas.openxmlformats.org/drawingml/2006/picture'
$nsm.AddNamespace('w',$wNs);$nsm.AddNamespace('r',$rNs);$nsm.AddNamespace('a',$aNs);$nsm.AddNamespace('wp',$wpNs);$nsm.AddNamespace('pic',$picNs)

# Convert linked pictures to embedded pictures and apply deterministic dimensions.
foreach($blip in $xml.SelectNodes('//a:blip[@r:link]',$nsm)){
  $id=$blip.GetAttribute('link',$rNs)
  if($id -notin @('rId2','rId3','rId4','rId5')){continue}
  $blip.RemoveAttribute('link',$rNs)
  [void]$blip.SetAttribute('embed',$rNs,$id)
  if($id -eq 'rId2'){$cx='1051560';$cy='1051560'}else{$cx='5943600';$cy='3343275'}
  $inline=$blip.SelectSingleNode('ancestor::wp:inline',$nsm)
  $extent=$inline.SelectSingleNode('./wp:extent',$nsm)
  if($extent -ne $null){[void]$extent.SetAttribute('cx',$cx);[void]$extent.SetAttribute('cy',$cy)}
  $shapeExtent=$blip.SelectSingleNode('ancestor::pic:pic/pic:spPr/a:xfrm/a:ext',$nsm)
  if($shapeExtent -ne $null){[void]$shapeExtent.SetAttribute('cx',$cx);[void]$shapeExtent.SetAttribute('cy',$cy)}
}

# Insert real Word page breaks at the report's major boundaries.
$breakHeadings=@(
  'Contents',
  'Executive Summary',
  '4. Updated System Flowchart and Architecture Diagram',
  '5. Database Design (ERD / Schema)',
  '6. Project Progress Report (Current Accomplishments)',
  'Appendix A. Source-of-Truth Locations'
)
foreach($p in $xml.SelectNodes('//w:body/w:p',$nsm)){
  $text=(($p.SelectNodes('.//w:t',$nsm)|ForEach-Object{$_.InnerText}) -join '').Trim()
  if($text -notin $breakHeadings){continue}
  $pPr=$p.SelectSingleNode('./w:pPr',$nsm)
  $style=$pPr.SelectSingleNode('./w:pStyle',$nsm)
  $styleName=$(if($style){$style.GetAttribute('val',$wNs)}else{''})
  if($styleName -eq 'BodyText'){continue}
  if($null -eq $pPr){$pPr=$xml.CreateElement('w','pPr',$wNs);[void]$p.PrependChild($pPr)}
  if($null -eq $pPr.SelectSingleNode('./w:pageBreakBefore',$nsm)){
    $pb=$xml.CreateElement('w','pageBreakBefore',$wNs);[void]$pPr.AppendChild($pb)
  }
}

$sect=$xml.SelectSingleNode('//w:body/w:sectPr',$nsm)
if($null -eq $sect){$sect=$xml.SelectSingleNode('(//w:sectPr)[last()]',$nsm)}
if($null -eq $sect){throw 'Could not locate section properties.'}
$hr=$xml.CreateElement('w','headerReference',$wNs);$hr.SetAttribute('type',$wNs,'default');$hr.SetAttribute('id',$rNs,'rId10')
$fr=$xml.CreateElement('w','footerReference',$wNs);$fr.SetAttribute('type',$wNs,'default');$fr.SetAttribute('id',$rNs,'rId11')
[void]$sect.PrependChild($fr);[void]$sect.PrependChild($hr)
$xml.Save($docPath)

if(Test-Path -LiteralPath $final){Remove-Item -LiteralPath $final -Force}
$archive=[IO.Compression.ZipFile]::Open($final,[IO.Compression.ZipArchiveMode]::Create)
try{
  foreach($file in Get-ChildItem -LiteralPath $resolvedWork -Recurse -File){
    $entryName=$file.FullName.Substring($resolvedWork.Length).TrimStart('\') -replace '\\','/'
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$entryName,[IO.Compression.CompressionLevel]::Optimal)
  }
}finally{$archive.Dispose()}
Get-Item $final|Select-Object FullName,Length
