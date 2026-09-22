param([Parameter(Mandatory=$true)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
function RGB([int]$r,[int]$g,[int]$b){$r+($g*256)+($b*65536)}
$html=Join-Path $WorkspaceRoot 'tmp\defense_build\report.html'
$docx=Join-Path $WorkspaceRoot 'output\defense\CareNavigator_PH_Project_Documentation.docx'
$pdf=Join-Path $WorkspaceRoot 'tmp\defense_build\CareNavigator_PH_Project_Documentation_QA.pdf'
$word=$null;$doc=$null
try{
  $word=New-Object -ComObject Word.Application
  $word.Visible=$false
  $word.DisplayAlerts=0
  $word.ScreenUpdating=$false
  $doc=$word.Documents.Open($html,$false,$false)
  foreach($sec in $doc.Sections){
    $sec.PageSetup.PageWidth=612;$sec.PageSetup.PageHeight=792
    $sec.PageSetup.TopMargin=72;$sec.PageSetup.BottomMargin=72
    $sec.PageSetup.LeftMargin=72;$sec.PageSetup.RightMargin=72
    $sec.PageSetup.HeaderDistance=35.424;$sec.PageSetup.FooterDistance=35.424
    $hdr=$sec.Headers.Item(1).Range
    $hdr.Text='CareNavigator PH  |  Project Defense Documentation'
    $hdr.Font.Name='Calibri';$hdr.Font.Size=9;$hdr.Font.Color=(RGB 91 112 128)
    $ftr=$sec.Footers.Item(1).Range
    $ftr.Text='CareNavigator PH  |  '
    $ftr.Font.Name='Calibri';$ftr.Font.Size=9;$ftr.Font.Color=(RGB 91 112 128)
    $ftr.ParagraphFormat.Alignment=2
    $ftr.Collapse(0)
    $ftr.Fields.Add($ftr,-1,'PAGE',$false)|Out-Null
  }
  $doc.SaveAs2($docx,16)
  $doc.ExportAsFixedFormat($pdf,17)
  Get-Item $docx,$pdf|Select-Object FullName,Length
}finally{
  if($doc -ne $null){$doc.Close(0)}
  if($word -ne $null){$word.Quit()}
  [GC]::Collect();[GC]::WaitForPendingFinalizers()
}
