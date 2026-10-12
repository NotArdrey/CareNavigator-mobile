param([Parameter(Mandatory=$true)][string]$WorkspaceRoot,[Parameter(Mandatory=$true)][string]$ReferenceDocx,[Parameter(Mandatory=$true)][string]$OutputDocx,[string]$HeadingPages)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing
$w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$rel='http://schemas.openxmlformats.org/package/2006/relationships'
$sourceHash=(Get-FileHash -LiteralPath $ReferenceDocx -Algorithm SHA256).Hash
$sourceZip=[System.IO.Compression.ZipFile]::OpenRead($ReferenceDocx)
$parts=@{}
$partInventory=@()
foreach($entry in $sourceZip.Entries){
  $stream=$entry.Open();$memory=[System.IO.MemoryStream]::new();$stream.CopyTo($memory);$stream.Dispose()
  $bytes=$memory.ToArray();$memory.Dispose();$parts[$entry.FullName]=$bytes
  $sha=[System.Security.Cryptography.SHA256]::Create();$digest=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','');$sha.Dispose()
  $partInventory += [pscustomobject]@{part=$entry.FullName;size=$bytes.Length;sha256=$digest}
}
$sourceZip.Dispose()
$partInventory | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'reference-parts.json') -Encoding UTF8
$utf8=[System.Text.UTF8Encoding]::new($false)
[xml]$doc=$utf8.GetString($parts['word/document.xml'])
$ns=[System.Xml.XmlNamespaceManager]::new($doc.NameTable);$ns.AddNamespace('w',$w)
$body=$doc.SelectSingleNode('//w:body',$ns)
$originalNodes=@($body.ChildNodes)
$coverSection=$doc.SelectSingleNode('//w:body/w:p/w:pPr/w:sectPr',$ns).CloneNode($true)
$finalSection=$doc.SelectSingleNode('//w:body/w:sectPr',$ns).CloneNode($true)
$script:content=[System.Text.StringBuilder]::new()
$script:newImages=@{}
$script:nextImageId=100
$script:needsPageBreak=$false
$script:currentLayout='portrait'
$script:newLinks=@()
function X([string]$text){return [System.Security.SecurityElement]::Escape($text)}
function P([string]$text,[string]$style='Normal',[int]$size=24,[bool]$bold=$false,[string]$align='left',[int]$before=0,[int]$after=120,[bool]$keep=$false){
  $keepXml=$(if($keep){'<w:keepNext/>'}else{''})
  $boldXml=$(if($bold){'<w:b/>'}else{'<w:b w:val="0"/>'})
  $outline=$(if($style -eq 'Title'){'<w:outlineLvl w:val="9"/>'}else{''})
  return '<w:p><w:pPr><w:pStyle w:val="'+$style+'"/><w:widowControl/>'+$keepXml+$outline+'<w:spacing w:before="'+$before+'" w:after="'+$after+'" w:line="264" w:lineRule="auto"/><w:jc w:val="'+$align+'"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>'+$boldXml+'<w:color w:val="000000"/><w:sz w:val="'+$size+'"/></w:rPr><w:t xml:space="preserve">'+(X $text)+'</w:t></w:r></w:p>'
}
function AddP([string]$text){[void]$content.Append((P $text))}
function Heading([string]$text,[int]$level=2){
  $headingXml=P $text ('Heading'+$level) $(if($level -eq 1){32}elseif($level -eq 2){28}else{24}) $true 'left' 200 120 $true
  if($script:needsPageBreak){$headingXml=$headingXml.Replace('<w:widowControl/>','<w:pageBreakBefore/><w:widowControl/>');$script:needsPageBreak=$false}
  [void]$content.Append($headingXml)
}
function PageBreak(){$script:needsPageBreak=$true}
function SectionFor([string]$layout,[bool]$withBreak=$false){
  $section=$finalSection.CloneNode($true)
  $pageSize=$section.SelectSingleNode('w:pgSz',$ns)
  if($layout -eq 'a3-landscape'){
    [void]$pageSize.SetAttribute('w',$w,'23811');[void]$pageSize.SetAttribute('h',$w,'16834');[void]$pageSize.SetAttribute('orient',$w,'landscape')
  }else{[void]$pageSize.SetAttribute('w',$w,'12240');[void]$pageSize.SetAttribute('h',$w,'15840');[void]$pageSize.RemoveAttribute('orient',$w)}
  $sectionType=$section.SelectSingleNode('w:type',$ns)
  if($withBreak){
    if(-not $sectionType){$sectionType=$doc.CreateElement('w','type',$w);[void]$section.PrependChild($sectionType)}
    [void]$sectionType.SetAttribute('val',$w,'nextPage')
  }elseif($sectionType){[void]$section.RemoveChild($sectionType)}
  return $section.OuterXml
}
function StartPage([string]$layout){
  if(-not $layout){$layout='portrait'}
  if($layout -ne $script:currentLayout){
    [void]$content.Append('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/>'+(SectionFor $script:currentLayout $true)+'</w:pPr><w:r><w:rPr><w:sz w:val="2"/></w:rPr></w:r></w:p>')
    $script:currentLayout=$layout;$script:needsPageBreak=$false
  }else{PageBreak}
}
function Link($link){
  $id='rIdCareLink'+($script:newLinks.Count+1)
  $script:newLinks += [pscustomobject]@{id=$id;target=$link.target}
  [void]$content.Append('<w:p><w:pPr><w:spacing w:after="120"/><w:widowControl/></w:pPr><w:hyperlink r:id="'+$id+'"><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="22"/><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr><w:t>'+(X $link.text)+'</w:t></w:r></w:hyperlink></w:p>')
}
function ImageRun([string]$relative,[double]$width,[string]$alt){
  if($relative.StartsWith('diagrams/')){$imagePath=Join-Path $PSScriptRoot $relative}else{$imagePath=Join-Path $WorkspaceRoot $relative}
  $imagePath=(Resolve-Path -LiteralPath $imagePath).Path
  if(-not $newImages.ContainsKey($imagePath)){
    $script:nextImageId++
    $imageName='cnph-image-'+$script:nextImageId+'.png'
    $newImages[$imagePath]=[pscustomobject]@{id='rIdCareDoc'+$script:nextImageId;part='word/media/'+$imageName;target='media/'+$imageName;drawId=$script:nextImageId}
  }
  $item=$newImages[$imagePath]
  $img=[System.Drawing.Image]::FromFile($imagePath)
  $height=$width*$img.Height/$img.Width;$img.Dispose()
  $cx=[long][math]::Round($width*914400);$cy=[long][math]::Round($height*914400)
  return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="'+$cx+'" cy="'+$cy+'"/><wp:docPr id="'+$item.drawId+'" name="CareNavigator figure" descr="'+(X $alt)+'"/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="0" name="CareNavigator figure"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="'+$item.id+'"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="'+$cx+'" cy="'+$cy+'"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
}
function Table($table){
  $sizes=@($table.widths);$font=$(if($table.font){[int]($table.font*2)}else{21})
  $totalWidth=($sizes | Measure-Object -Sum).Sum
  $xml=[System.Text.StringBuilder]::new()
  [void]$xml.Append('<w:tbl><w:tblPr><w:tblW w:w="'+$totalWidth+'" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>')
  foreach($border in @('top','left','bottom','right','insideH','insideV')){[void]$xml.Append('<w:'+$border+' w:val="single" w:sz="4" w:color="D9D9D9"/>')}
  [void]$xml.Append('</w:tblBorders><w:tblCellMar><w:top w:w="80" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>')
  foreach($size in $sizes){[void]$xml.Append('<w:gridCol w:w="'+$size+'"/>')};[void]$xml.Append('</w:tblGrid>')
  $allRows=@();$allRows+=,@($table.headers);foreach($row in $table.rows){$allRows+=,@($row)}
  for($i=0;$i -lt $allRows.Count;$i++){
    $isHead=$i -eq 0
    [void]$xml.Append('<w:tr><w:trPr><w:cantSplit/>'+$(if($isHead){'<w:tblHeader/>'}else{''})+'</w:trPr>')
    for($j=0;$j -lt $sizes.Count;$j++){
      $shade=$(if($isHead){'1F4E79'}elseif($i%2 -eq 0){'F3F6F8'}else{'FFFFFF'})
      $color=$(if($isHead){'FFFFFF'}else{'000000'})
      $align=$(if($sizes[$j] -lt 2100 -or $isHead){'center'}else{'left'})
      [void]$xml.Append('<w:tc><w:tcPr><w:tcW w:w="'+$sizes[$j]+'" w:type="dxa"/><w:shd w:val="clear" w:fill="'+$shade+'"/><w:vAlign w:val="center"/></w:tcPr><w:p><w:pPr><w:widowControl/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="'+$align+'"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="'+$font+'"/><w:color w:val="'+$color+'"/>'+$(if($isHead){'<w:b/>'}else{'<w:b w:val="0"/>'})+'</w:rPr><w:t xml:space="preserve">'+(X ([string]$allRows[$i][$j]))+'</w:t></w:r></w:p></w:tc>')
    }
    [void]$xml.Append('</w:tr>')
  }
  [void]$xml.Append('</w:tbl>')
  [void]$content.Append($xml.ToString())
  [void]$content.Append('<w:p><w:pPr><w:spacing w:before="80" w:after="80" w:line="60" w:lineRule="exact"/></w:pPr><w:r><w:rPr><w:sz w:val="6"/></w:rPr><w:t xml:space="preserve"> </w:t></w:r></w:p>')
}
$coverReplacements=@{
  'ADVANCE  MOBILE APPLICATION DEVELOPMENT'='ADVANCED MOBILE APPLICATION DEVELOPMENT';
  'A Mobile Application for Inventory Management'='CareNavigator PH';
  'Student Name 1'='Neil Ardrey Laza';'Student Name 2'='ITE 231';'Student Name 3'='';'September 2026'=''
}
foreach($node in $originalNodes){
  if($node.SelectSingleNode('w:pPr/w:sectPr',$ns)){break}
  if($node.SelectSingleNode('.//w:br[@w:type="page"]',$ns)){continue}
  $copy=$node.CloneNode($true)
  $textNodes=@($copy.SelectNodes('.//w:t',$ns));$text=($textNodes | ForEach-Object {$_.InnerText}) -join ''
  if($text.StartsWith('ADVANCE')){if($textNodes.Count -gt 0){$textNodes[0].InnerText='ADVANCED MOBILE APPLICATION DEVELOPMENT';for($i=1;$i -lt $textNodes.Count;$i++){$textNodes[$i].InnerText=''}}}
  if($coverReplacements.ContainsKey($text)){
    if($textNodes.Count -gt 0){$textNodes[0].InnerText=$coverReplacements[$text];for($i=1;$i -lt $textNodes.Count;$i++){$textNodes[$i].InnerText=''}}
  }
  foreach($border in @($copy.SelectNodes('.//w:pBdr',$ns))){[void]$border.ParentNode.RemoveChild($border)}
  foreach($color in $copy.SelectNodes('.//w:color',$ns)){$color.SetAttribute('val',$w,'000000')}
  if($text -eq 'A Mobile Application for Inventory Management'){
    $pr=$copy.SelectSingleNode('w:pPr',$ns)
    $style=$doc.CreateElement('w','pStyle',$w);$style.SetAttribute('val',$w,'Title');[void]$pr.PrependChild($style)
  }
  [void]$content.Append($copy.OuterXml)
  if($text -eq 'A Mobile Application for Inventory Management'){
    [void]$content.Append((P 'Healthcare Navigation and Care Coordination' 'Normal' 26 $false 'center' 0 180))
  }
}
[void]$content.Append('<w:p><w:pPr>'+$coverSection.OuterXml+'</w:pPr></w:p>')
Heading 'TABLE OF CONTENTS' 1
$data=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'content.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$toc=@(
  @('Chapter 1 Project Overview','PROJECT OVERVIEW'),
  @('  Introduction','PROJECT OVERVIEW'),
  @('  Objectives and significance','Project Objectives and Significance'),
  @('  Scope and limitations','Scope of the Project'),
  @('Chapter 2 System Analysis and Design','SYSTEM ANALYSIS AND DESIGN'),
  @('  System description and architecture','SYSTEM ANALYSIS AND DESIGN'),
  @('  System flow and lifecycle','System Flow'),
  @('  Use case diagram','Use Case Diagram'),
  @('  Database design and tables','Database Design'),
  @('  User interface design','User Interface Design'),
  @('Chapter 3 System Development','SYSTEM DEVELOPMENT'),
  @('  Tools and technologies','SYSTEM DEVELOPMENT'),
  @('  Development process','Development Process'),
  @('  Deployment and reproducibility','Deployment and Reproducibility'),
  @('Chapter 4 Results and Testing','RESULTS AND TESTING'),
  @('  System features','RESULTS AND TESTING'),
  @('  Functional testing','Functional Testing'),
  @('  Evaluation and verification','Evaluation and Recorded Verification'),
  @('Chapter 5 Conclusion and Recommendations','CONCLUSION AND RECOMMENDATIONS'),
  @('Appendix A Screenshots of the Application','Appendix A Screenshots of the Application'),
  @('Appendix B Source Code Snippets','Appendix B Source Code Snippets'),
  @('Appendix C User Manual','Appendix C User Manual'),
  @('Appendix D Complete Physical ERD','Appendix D Complete Physical ERD'),
  @('Research References','Research References'),
  @('Project References','Project References')
)
$pageLookup=@{};$physicalPage=3
foreach($page in $data.pages){$pageLookup[$page.title]=$physicalPage;$physicalPage++}
if($HeadingPages -and (Test-Path -LiteralPath $HeadingPages)){
  foreach($entry in (Get-Content -LiteralPath $HeadingPages -Raw -Encoding UTF8 | ConvertFrom-Json)){$pageLookup[$entry.text]=$entry.page}
}
foreach($tocRow in $toc){
  $number=$pageLookup[$tocRow[1]];$isTop=-not $tocRow[0].StartsWith(' ')
  [void]$content.Append('<w:p><w:pPr><w:tabs><w:tab w:val="right" w:leader="dot" w:pos="9360"/></w:tabs><w:spacing w:after="'+$(if($isTop){150}else{65})+'" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="'+$(if($isTop){23}else{21})+'"/>'+$(if($isTop){'<w:b/>'}else{''})+'</w:rPr><w:t xml:space="preserve">'+(X $tocRow[0])+'</w:t><w:tab/><w:t>'+[string]$number+'</w:t></w:r></w:p>')
}
foreach($page in $data.pages){
  StartPage $page.layout
  if($page.chapter){Heading $page.chapter 1;[void]$content.Append((P $page.title 'Heading1' 30 $true 'center' 0 180 $true))}else{Heading $page.title 1}
  foreach($block in $page.blocks){
    if($block.p){AddP $block.p}
    elseif($block.h2){Heading $block.h2 2}
    elseif($block.h3){Heading $block.h3 3}
    elseif($block.source){[void]$content.Append((P $block.source 'Normal' 18 $false 'left' 80 0))}
    elseif($block.link){Link $block.link}
    elseif($block.table){Table $block.table}
    elseif($block.image){
      [void]$content.Append('<w:p><w:pPr><w:keepNext/><w:jc w:val="center"/><w:spacing w:after="80"/></w:pPr>'+(ImageRun $block.image $block.width $block.caption)+'</w:p>')
      [void]$content.Append((P $block.caption 'Caption' 20 $false 'center' 0 150))
    }
    elseif($block.pair){
      [void]$content.Append('<w:p><w:pPr><w:keepNext/><w:jc w:val="center"/><w:spacing w:after="100"/></w:pPr>'+(ImageRun $block.pair[0] 2.6 $block.labels[0])+'<w:r><w:t xml:space="preserve">      </w:t></w:r>'+(ImageRun $block.pair[1] 2.6 $block.labels[1])+'</w:p>')
      [void]$content.Append((P ($block.labels -join '     |     ') 'Caption' 20 $false 'center' 0 180))
    }
    elseif($block.list -or $block.steps){
      $items=$(if($block.list){$block.list}else{$block.steps});$itemIndex=1
      foreach($item in $items){
        $label=$(if($block.steps){[string]$itemIndex+'. '}else{[char]0x2022+' '})
        $para=P ($label+$item) 'ListParagraph' 24 $false 'left' 0 90
        $para=$para.Replace('<w:widowControl/>','<w:widowControl/><w:ind w:left="360" w:hanging="240"/>')
        [void]$content.Append($para);$itemIndex++
      }
    }
    elseif($block.codeFile){
      $lines=Get-Content -LiteralPath (Join-Path $WorkspaceRoot $block.codeFile) -Encoding UTF8
      if($block.codePattern){
        $allCode=[System.IO.File]::ReadAllText((Join-Path $WorkspaceRoot $block.codeFile))
        $match=[regex]::Match($allCode,$block.codePattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
        if(-not $match.Success){throw ('Source excerpt anchor missing: '+$block.codeFile)}
        $lines=$match.Value.TrimEnd().Split([char]10) | ForEach-Object {$_.TrimEnd([char]13)}
        $block.start=1;$block.end=$lines.Count
      }
      for($line=$block.start-1;$line -lt [math]::Min($block.end,$lines.Length);$line++){
        $codeLine=[string]$lines[$line]
        [void]$content.Append('<w:p><w:pPr><w:spacing w:after="0" w:line="220" w:lineRule="exact"/><w:widowControl/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/><w:b w:val="0"/><w:color w:val="000000"/></w:rPr><w:t xml:space="preserve">'+(X $codeLine)+'</w:t></w:r></w:p>')
      }
      [void]$content.Append((P '' 'Normal' 18 $false 'left' 0 70))
    }
    elseif($block.refs){
      foreach($refEntry in $block.refs){[void]$content.Append((P ('['+$refEntry[0]+'] '+$refEntry[1]+'. '+$refEntry[2]) 'Normal' 19 $false 'left' 0 80))}
    }
  }
}
[void]$content.Append((SectionFor $script:currentLayout))
$body.InnerXml=$content.ToString()
$parts['word/document.xml']=$utf8.GetBytes($doc.OuterXml)
[xml]$relationships=$utf8.GetString($parts['word/_rels/document.xml.rels'])
foreach($pathKey in $newImages.Keys){
  $image=$newImages[$pathKey]
  $parts[$image.part]=[System.IO.File]::ReadAllBytes($pathKey)
  $element=$relationships.CreateElement('Relationship',$rel)
  $element.SetAttribute('Id',$image.id);$element.SetAttribute('Type','http://schemas.openxmlformats.org/officeDocument/2006/relationships/image');$element.SetAttribute('Target',$image.target)
  [void]$relationships.DocumentElement.AppendChild($element)
}
$parts['word/_rels/document.xml.rels']=$utf8.GetBytes($relationships.OuterXml)
foreach($link in $script:newLinks){
  $element=$relationships.CreateElement('Relationship',$rel)
  $element.SetAttribute('Id',$link.id);$element.SetAttribute('Type','http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink');$element.SetAttribute('Target',$link.target);$element.SetAttribute('TargetMode','External')
  [void]$relationships.DocumentElement.AppendChild($element)
}
$parts['word/_rels/document.xml.rels']=$utf8.GetBytes($relationships.OuterXml)
[xml]$styles=$utf8.GetString($parts['word/styles.xml'])
$styleNs=[System.Xml.XmlNamespaceManager]::new($styles.NameTable);$styleNs.AddNamespace('w',$w)
foreach($styleName in @('Heading1','Heading2','Heading3','Title','Subtitle','Header')){
  $style=$styles.SelectSingleNode('//w:style[@w:styleId="'+$styleName+'"]',$styleNs)
  if($style){foreach($color in $style.SelectNodes('.//w:color',$styleNs)){$color.SetAttribute('val',$w,'000000');$color.RemoveAttribute('themeColor',$w)}}
}
$parts['word/styles.xml']=$utf8.GetBytes($styles.OuterXml)
foreach($headerPart in @('word/header2.xml')){
  if($parts.ContainsKey($headerPart)){
    [xml]$header=$utf8.GetString($parts[$headerPart]);$headerNs=[System.Xml.XmlNamespaceManager]::new($header.NameTable);$headerNs.AddNamespace('w',$w)
    $texts=@($header.SelectNodes('//w:t',$headerNs));if($texts.Count -gt 0){$texts[0].InnerText='CareNavigator PH';for($i=1;$i -lt $texts.Count;$i++){$texts[$i].InnerText=''}}
    foreach($color in $header.SelectNodes('//w:color',$headerNs)){$color.SetAttribute('val',$w,'000000')}
    $parts[$headerPart]=$utf8.GetBytes($header.OuterXml)
  }
}
[xml]$settings=$utf8.GetString($parts['word/settings.xml'])
$settingsNs=[System.Xml.XmlNamespaceManager]::new($settings.NameTable);$settingsNs.AddNamespace('w',$w)
$update=$settings.SelectSingleNode('//w:updateFields',$settingsNs)
if(-not $update){$update=$settings.CreateElement('w','updateFields',$w);[void]$settings.DocumentElement.AppendChild($update)}
$update.SetAttribute('val',$w,'true');$parts['word/settings.xml']=$utf8.GetBytes($settings.OuterXml)
[xml]$core=$utf8.GetString($parts['docProps/core.xml'])
$coreNs=[System.Xml.XmlNamespaceManager]::new($core.NameTable);$coreNs.AddNamespace('dc','http://purl.org/dc/elements/1.1/');$coreNs.AddNamespace('cp','http://schemas.openxmlformats.org/package/2006/metadata/core-properties')
foreach($item in @(@('dc:title','CareNavigator PH Final Project Documentation'),@('dc:creator','Neil Ardrey Laza'),@('cp:lastModifiedBy','Neil Ardrey Laza'))){$n=$core.SelectSingleNode('//'+$item[0],$coreNs);if($n){$n.InnerText=$item[1]}}
$parts['docProps/core.xml']=$utf8.GetBytes($core.OuterXml)
[xml]$appProperties=$utf8.GetString($parts['docProps/app.xml'])
$appPages=$appProperties.DocumentElement.ChildNodes | Where-Object {$_.LocalName -eq 'Pages'}
if($appPages){$appPages.InnerText=[string]($data.pages.Count+2)}
$parts['docProps/app.xml']=$utf8.GetBytes($appProperties.OuterXml)
New-Item -ItemType Directory -Force -Path (Split-Path $OutputDocx) | Out-Null
$outStream=[System.IO.File]::Open($OutputDocx,[System.IO.FileMode]::Create,[System.IO.FileAccess]::ReadWrite)
$outZip=[System.IO.Compression.ZipArchive]::new($outStream,[System.IO.Compression.ZipArchiveMode]::Create,$false)
foreach($partName in $parts.Keys){$entry=$outZip.CreateEntry($partName,[System.IO.Compression.CompressionLevel]::Optimal);$entryStream=$entry.Open();$entryStream.Write($parts[$partName],0,$parts[$partName].Length);$entryStream.Dispose()}
$outZip.Dispose();$outStream.Dispose()
if((Get-FileHash -LiteralPath $ReferenceDocx -Algorithm SHA256).Hash -ne $sourceHash){throw 'Reference changed during document creation'}
Write-Output ('Created {0}; {1} images; source reference unchanged' -f $OutputDocx,$newImages.Count)
