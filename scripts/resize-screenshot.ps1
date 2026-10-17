param(
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$W = 1179,
  [int]$H = 2556
)
# Porte une capture iPhone 12 (1170x2532) aux dimensions exigees par
# App Store Connect (1179x2556). Le rapport des deux formats est identique
# a 0,04 % pres, donc l agrandissement ne deforme pas : il rajoute 9 px de
# large et 24 px de haut, soit moins de 1 %.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile((Resolve-Path $Source).Path)
$dst = New-Object System.Drawing.Bitmap($W, $H)
$dst.SetResolution($src.HorizontalResolution, $src.VerticalResolution)

$g = [System.Drawing.Graphics]::FromImage($dst)
$g.CompositingMode    = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$attr = New-Object System.Drawing.Imaging.ImageAttributes
$attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
$rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
$g.DrawImage($src, $rect, 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)

$dst.Save((Join-Path (Get-Location) $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $dst.Dispose(); $src.Dispose()
Write-Output ("redimensionne : " + $Out + "  -> " + $W + "x" + $H)
