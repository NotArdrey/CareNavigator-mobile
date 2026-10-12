param([string]$OriginalDirectory,[string]$RevisedDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
function CropHash([string]$file){
  $image=[System.Drawing.Bitmap]::new($file)
  $crop=$image.Clone([System.Drawing.Rectangle]::new(125,150,1030,1300),[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $stream=[System.IO.MemoryStream]::new();$crop.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png)
  $hasher=[System.Security.Cryptography.SHA256]::Create();$hash=[BitConverter]::ToString($hasher.ComputeHash($stream.ToArray()))
  $hasher.Dispose();$stream.Dispose();$crop.Dispose();$image.Dispose();return $hash
}
$pairs=@(@(1,1),@(4,5),@(5,6),@(6,7),@(7,8),@(8,9),@(9,10),@(11,12),@(12,13),@(13,14),@(14,15),@(15,16),@(16,17),@(17,18),@(18,19),@(19,20),@(20,21),@(21,22),@(22,23),@(24,26),@(25,27),@(26,28),@(27,29),@(28,30))
$results=foreach($pair in $pairs){
  $old=Join-Path $OriginalDirectory ('page-'+$pair[0]+'.png');$new=Join-Path $RevisedDirectory ('page-'+$pair[1]+'.png')
  [pscustomobject]@{originalPage=$pair[0];revisedPage=$pair[1];identicalBody=((CropHash $old) -eq (CropHash $new))}
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'retained-page-comparison.json') -Encoding UTF8
$results | Format-Table -AutoSize
