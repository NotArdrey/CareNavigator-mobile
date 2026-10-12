param([Parameter(Mandatory=$true)][string]$InputDocx,[Parameter(Mandatory=$true)][string]$OutputDirectory,[int]$ImageWidth=1275)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$word=$null;$document=$null
try {
  $word=New-Object -ComObject Word.Application
  $word.Visible=$false;$word.DisplayAlerts=0
  $document=$word.Documents.Open($InputDocx,$false,$true)
  $document.ActiveWindow.View.Type=3
  $document.Fields.Update() | Out-Null
  $document.Repaginate()
  $totalPages=$document.ComputeStatistics(2)
  $layoutWarmup=$document.ActiveWindow.ActivePane.Pages.Item($totalPages).EnhMetaFileBits
  foreach($section in $document.Sections){
    foreach($footer in $section.Footers){if($footer.Exists){$footer.Range.Fields.Update() | Out-Null}}
  }
  $document.Repaginate()
  [pscustomobject]@{pages=$totalPages;engine='Word page Enhanced Metafile';input=$InputDocx} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'render-summary.json') -Encoding UTF8
  $headings=@()
  foreach($paragraph in $document.Paragraphs) {
    $text=$paragraph.Range.Text.Trim([char]13,[char]7)
    if($paragraph.OutlineLevel -le 3 -and $text.Length -gt 0) {
      $headings += [pscustomobject]@{text=$text;page=$paragraph.Range.Information(3);level=$paragraph.OutlineLevel}
    }
  }
  $headings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'heading-pages.json') -Encoding UTF8
  $pages=$document.ActiveWindow.ActivePane.Pages
  Write-Output ('Word paginated {0} pages' -f $pages.Count)
  for($pageIndex=1;$pageIndex -le $pages.Count;$pageIndex++) {
    $page=$pages.Item($pageIndex)
    [byte[]]$pageBits=$page.EnhMetaFileBits
    $pageStream=[System.IO.MemoryStream]::new($pageBits,$false)
    $pageMetafile=[System.Drawing.Imaging.Metafile]::new($pageStream)
    $pageImageWidth=$(if($page.Width -gt 1000){2480}else{$ImageWidth})
    $imageHeight=[int][math]::Round($pageImageWidth*$page.Height/$page.Width)
    $bitmap=[System.Drawing.Bitmap]::new($pageImageWidth,$imageHeight)
    $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::White)
    $graphics.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($pageMetafile,[System.Drawing.Rectangle]::new(0,0,$pageImageWidth,$imageHeight))
    $bitmap.Save((Join-Path $OutputDirectory ('page-{0}.png' -f $pageIndex)),[System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose();$bitmap.Dispose();$pageMetafile.Dispose();$pageStream.Dispose()
    Write-Output ('Rendered page {0}' -f $pageIndex)
  }
} finally {
  if($document -ne $null){$document.Close(0)}
  if($word -ne $null){$word.Quit()}
  [GC]::Collect();[GC]::WaitForPendingFinalizers()
}
