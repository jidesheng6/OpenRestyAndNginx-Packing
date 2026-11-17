param(
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
if (-not ("IconNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class IconNative {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr handle);
}
"@
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) "installer\assets"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function New-RoundedRectPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-BaseBitmap {
    $size = 256
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)

    $rect = New-Object System.Drawing.Rectangle(8, 8, 240, 240)
    $path = New-RoundedRectPath 8 8 240 240 52
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(255, 12, 43, 31),
        [System.Drawing.Color]::FromArgb(255, 16, 163, 90),
        45.0)
    $g.FillPath($brush, $path)

    $ring = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 255, 255, 255), 4)
    $g.DrawEllipse($ring, 34, 34, 188, 188)

    $font = New-Object System.Drawing.Font("Segoe UI", 92, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.DrawString("OR", $font, $textBrush, (New-Object System.Drawing.RectangleF(0, 0, 256, 256)), $format)

    $font.Dispose(); $format.Dispose(); $textBrush.Dispose(); $ring.Dispose(); $brush.Dispose(); $path.Dispose(); $g.Dispose()
    return $bmp
}

function Add-Badge([System.Drawing.Bitmap]$bmp, [string]$Kind) {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    $colors = @{
        start   = [System.Drawing.Color]::FromArgb(255, 34, 197, 94)
        stop    = [System.Drawing.Color]::FromArgb(255, 239, 68, 68)
        restart = [System.Drawing.Color]::FromArgb(255, 59, 130, 246)
        web     = [System.Drawing.Color]::FromArgb(255, 14, 165, 233)
    }
    $cx = 206; $cy = 206; $radius = 44
    $border = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 6)
    $fill = New-Object System.Drawing.SolidBrush($colors[$Kind])
    $g.FillEllipse($fill, $cx - $radius, $cy - $radius, $radius * 2, $radius * 2)
    $g.DrawEllipse($border, $cx - $radius, $cy - $radius, $radius * 2, $radius * 2)

    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    switch ($Kind) {
        "start" {
            $points = @(
                [System.Drawing.PointF]::new([single]($cx - 14), [single]($cy - 20)),
                [System.Drawing.PointF]::new([single]($cx - 14), [single]($cy + 20)),
                [System.Drawing.PointF]::new([single]($cx + 22), [single]($cy))
            )
            $g.FillPolygon($white, $points)
        }
        "stop" {
            $g.FillRectangle($white, $cx - 16, $cy - 16, 32, 32)
        }
        "restart" {
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 8)
            $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawArc($pen, $cx - 20, $cy - 20, 40, 40, 40, 285)
            $arrow = @(
                [System.Drawing.PointF]::new([single]($cx + 20), [single]($cy - 4)),
                [System.Drawing.PointF]::new([single]($cx + 34), [single]($cy - 16)),
                [System.Drawing.PointF]::new([single]($cx + 36), [single]($cy + 4))
            )
            $g.FillPolygon($white, $arrow)
            $pen.Dispose()
        }
        "web" {
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 5)
            $g.DrawEllipse($pen, $cx - 22, $cy - 22, 44, 44)
            $g.DrawLine($pen, $cx - 22, $cy, $cx + 22, $cy)
            $g.DrawEllipse($pen, $cx - 10, $cy - 22, 20, 44)
            $pen.Dispose()
        }
    }

    $white.Dispose(); $fill.Dispose(); $border.Dispose(); $g.Dispose()
}

function Save-Ico([System.Drawing.Bitmap]$Source, [string]$Path) {
    $hIcon = $Source.GetHicon()
    try {
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
        $fs = [System.IO.File]::Create($Path)
        $icon.Save($fs)
        $fs.Close()
        $icon.Dispose()
    }
    finally {
        [IconNative]::DestroyIcon($hIcon) | Out-Null
    }
}

$base = New-BaseBitmap
Save-Ico $base (Join-Path $OutDir "openresty.ico")
$base.Dispose()

foreach ($kind in @("start", "stop", "restart", "web")) {
    $bmp = New-BaseBitmap
    Add-Badge $bmp $kind
    Save-Ico $bmp (Join-Path $OutDir "openresty-$kind.ico")
    $bmp.Dispose()
}

Get-ChildItem $OutDir -Filter *.ico | Select-Object Name, Length
