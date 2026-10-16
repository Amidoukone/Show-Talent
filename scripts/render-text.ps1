param(
  [Parameter(Mandatory=$true)][string]$Text,
  [Parameter(Mandatory=$true)][double]$Size,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$W = 640,
  [int]$H = 110,
  [int]$OriginX = 20,
  [int]$OriginY = 20,
  [string]$Ink = "#9BA3B0",
  [string]$Bg  = "#1A1F25",
  [string]$FontFile = "C:/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($FontFile)
$fam = $pfc.Families[0]

$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($Bg))), 0, 0, $W, $H)

$font = New-Object System.Drawing.Font($fam, $Size, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($Ink))
$fmt = [System.Drawing.StringFormat]::GenericTypographic
$g.DrawString($Text, $font, $brush, $OriginX, $OriginY, $fmt)

$bmp.Save((Join-Path (Get-Location) $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output ("rendu : " + $Out + "  famille=" + $fam.Name + "  taille=" + $Size)
