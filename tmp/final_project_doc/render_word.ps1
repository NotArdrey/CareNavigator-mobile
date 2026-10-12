param(
  [Parameter(Mandatory=$true)][string]$InputDocx,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [int]$ImageWidth = 1275
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$renderPdf=Join-Path $OutputDirectory 'render.pdf'
$word=$null
$wordDocument=$null
try {
  $word=New-Object -ComObject Word.Application
  $word.Visible=$false
  $word.DisplayAlerts=0
  $word.ScreenUpdating=$false
  $wordDocument=$word.Documents.Open($InputDocx,$false,$true)
  Write-Output 'Word opened the document'
  $wordDocument.Fields.Update() | Out-Null
  $wordDocument.Repaginate()
  $headings=@()
  foreach($paragraph in $wordDocument.Paragraphs) {
    $text=$paragraph.Range.Text.Trim([char]13,[char]7)
    if($paragraph.OutlineLevel -le 3 -and $text.Length -gt 0) {
      $headings += [pscustomobject]@{text=$text;page=$paragraph.Range.Information(3);level=$paragraph.OutlineLevel}
    }
  }
  $headings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'heading-pages.json') -Encoding UTF8
  Write-Output 'Exporting PDF with document rights metadata disabled'
  $wordDocument.ExportAsFixedFormat($renderPdf,17,$false,0,0,1,1,0,$false,$false,0,$false,$true,$false)
  Write-Output 'Word PDF export completed'
} finally {
  if($wordDocument -ne $null){$wordDocument.Close(0)}
  if($word -ne $null){$word.Quit()}
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null=[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
$null=[Windows.Storage.StorageFolder,Windows.Storage,ContentType=WindowsRuntime]
$null=[Windows.Data.Pdf.PdfDocument,Windows.Data.Pdf,ContentType=WindowsRuntime]
$null=[Windows.Data.Pdf.PdfPageRenderOptions,Windows.Data.Pdf,ContentType=WindowsRuntime]
$null=[Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]
$asTaskGeneric=([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {$_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'} | Select-Object -First 1)
$asTaskAction=([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {$_.Name -eq 'AsTask' -and -not $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'} | Select-Object -First 1)
function AwaitResult($operation,[type]$resultType) {
  $task=$asTaskGeneric.MakeGenericMethod($resultType).Invoke($null,@($operation))
  $task.Wait()
  return $task.Result
}
function AwaitAction($operation) {
  $task=$asTaskAction.Invoke($null,@($operation))
  $task.Wait()
}
$pdfFile=AwaitResult ([Windows.Storage.StorageFile]::GetFileFromPathAsync($renderPdf)) ([Windows.Storage.StorageFile])
$pdf=AwaitResult ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($pdfFile)) ([Windows.Data.Pdf.PdfDocument])
$folder=AwaitResult ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($OutputDirectory)) ([Windows.Storage.StorageFolder])
for($pageIndex=0;$pageIndex -lt $pdf.PageCount;$pageIndex++) {
  $page=$pdf.GetPage($pageIndex)
  $file=AwaitResult ($folder.CreateFileAsync(('page-{0}.png' -f ($pageIndex+1)),[Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
  $stream=AwaitResult ($file.OpenAsync([Windows.Storage.FileAccessMode]::ReadWrite)) ([Windows.Storage.Streams.IRandomAccessStream])
  $options=[Windows.Data.Pdf.PdfPageRenderOptions]::new()
  $options.DestinationWidth=$ImageWidth
  AwaitAction ($page.RenderToStreamAsync($stream,$options))
  $stream.Dispose()
  $page.Dispose()
}
Write-Output ('Rendered {0} pages to {1}' -f $pdf.PageCount,$OutputDirectory)
