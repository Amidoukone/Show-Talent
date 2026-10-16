# Compose la feature graphic 1024x500 de la fiche Play a partir du logo et de
# la palette reelle de l'application (lib/theme/ad_colors.dart).
param(
  [string]$LogoPath   = "assets\logo.png",
  [string]$OutputPath = "artifacts\store\android\feature-graphic-1024x500.png"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$W = 1024
$H = 500

$surface   = [System.Drawing.ColorTranslator]::FromHtml("#0E1114")
$brand     = [System.Drawing.ColorTranslator]::FromHtml("#2ED573")
$onSurface = [System.Drawing.ColorTranslator]::FromHtml("#EDEDED")
$muted     = [System.Drawing.ColorTranslator]::FromHtml("#B5C7C7")

$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# Fond
$bg = New-Object System.Drawing.SolidBrush($surface)
$g.FillRectangle($bg, 0, 0, $W, $H)

# Halo vert discret derriere la tuile du logo
$halo = New-Object System.Drawing.Drawing2D.GraphicsPath
$halo.AddEllipse(40, 60, 420, 420)
$haloBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($halo)
$haloBrush.CenterColor = [System.Drawing.Color]::FromArgb(46, 46, 213, 115)
$haloBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 46, 213, 115))
$g.FillPath($haloBrush, $halo)

# Tuile blanche arrondie contenant le logo
function New-RoundedPath([int]$x, [int]$y, [int]$w, [int]$h, [int]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x,               $y,               $d, $d, 180, 90)
  $p.AddArc($x + $w - $d,     $y,               $d, $d, 270, 90)
  $p.AddArc($x + $w - $d,     $y + $h - $d,     $d, $d, 0,   90)
  $p.AddArc($x,               $y + $h - $d,     $d, $d, 90,  90)
  $p.CloseFigure()
  return $p
}

$tileX = 96; $tileY = 110; $tileS = 280
$tile  = New-RoundedPath $tileX $tileY $tileS $tileS 56
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$g.FillPath($white, $tile)

$logo = [System.Drawing.Image]::FromFile((Resolve-Path $LogoPath).Path)
$pad  = 26
$inner = $tileS - ($pad * 2)
$scale = [Math]::Min($inner / $logo.Width, $inner / $logo.Height)
$lw = [int]($logo.Width  * $scale)
$lh = [int]($logo.Height * $scale)
$lx = $tileX + [int](($tileS - $lw) / 2)
$ly = $tileY + [int](($tileS - $lh) / 2)
$g.DrawImage($logo, $lx, $ly, $lw, $lh)
$logo.Dispose()

# Textes
$textX = 440
$fTitle = New-Object System.Drawing.Font("Segoe UI", 58, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fBody  = New-Object System.Drawing.Font("Segoe UI", 30, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fTag   = New-Object System.Drawing.Font("Segoe UI", 25, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)

$bTitle = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$bBody  = New-Object System.Drawing.SolidBrush($onSurface)
$bTag   = New-Object System.Drawing.SolidBrush($brand)
$bMuted = New-Object System.Drawing.SolidBrush($muted)

$g.DrawString("Adfoot",                               $fTitle, $bTitle, $textX, 132)
$g.DrawString("Profils, vidéos et mises en relation", $fBody,  $bBody,  $textX, 222)
$g.DrawString("pour le football malien",              $fBody,  $bMuted, $textX, 264)

# Filet vert
$pen = New-Object System.Drawing.Pen($brand, 4)
$g.DrawLine($pen, $textX, 322, $textX + 96, 322)

$g.DrawString("Joueurs  ·  Clubs  ·  Recruteurs  ·  Agents", $fTag, $bTag, $textX, 344)

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
$bmp.Save((Join-Path (Get-Location) $OutputPath), [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose(); $bmp.Dispose()
Write-Output ("Ecrit : " + $OutputPath)
