param(
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][int]$X,
  [Parameter(Mandatory=$true)][int]$Y,
  [Parameter(Mandatory=$true)][int]$W,
  [Parameter(Mandatory=$true)][int]$H,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$Scale = 1
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile((Resolve-Path $Source).Path)
$dst = New-Object System.Drawing.Bitmap(($W * $Scale), ($H * $Scale))
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$destRect = New-Object System.Drawing.Rectangle(0, 0, ($W * $Scale), ($H * $Scale))
$g.DrawImage($src, $destRect, $X, $Y, $W, $H, [System.Drawing.GraphicsUnit]::Pixel)
$full = Join-Path (Get-Location) $Out
$dst.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $dst.Dispose(); $src.Dispose()
Write-Output ("Decoupe : " + $Out + "  (" + $W + "x" + $H + " depuis " + $X + "," + $Y + ")")
