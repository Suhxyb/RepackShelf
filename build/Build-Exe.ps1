param(
    [string]$Version = '0.0.0',
    [string]$Root = (Split-Path $PSScriptRoot),
    # Pin the compiler version for reproducible, reviewable builds (see README: repository variable PS2EXE_VERSION).
    [string]$Ps2exeVersion = ''
)
$ErrorActionPreference = 'Stop'
$pin = @{}; if ($Ps2exeVersion) { $pin = @{ RequiredVersion = $Ps2exeVersion } }
if (-not (Get-Module -ListAvailable -Name ps2exe | Where-Object { -not $Ps2exeVersion -or $_.Version -eq [version]$Ps2exeVersion })) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber @pin
}
Import-Module ps2exe @pin
Write-Host ("Using ps2exe {0}" -f (Get-Module ps2exe).Version)
Add-Type -AssemblyName System.Drawing

$dist = Join-Path $Root 'dist'; New-Item -ItemType Directory -Force $dist | Out-Null
$ico = Join-Path $env:TEMP 'RepackShelf.ico'
$bmp = New-Object Drawing.Bitmap 64, 64
$g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
$p = New-Object Drawing.Drawing2D.GraphicsPath; $r = 14; $s = 62
$p.AddArc(1, 1, $r * 2, $r * 2, 180, 90); $p.AddArc($s - $r * 2, 1, $r * 2, $r * 2, 270, 90)
$p.AddArc($s - $r * 2, $s - $r * 2, $r * 2, $r * 2, 0, 90); $p.AddArc(1, $s - $r * 2, $r * 2, $r * 2, 90, 90); $p.CloseFigure()
$br = New-Object Drawing.Drawing2D.LinearGradientBrush ((New-Object Drawing.Point 0, 0), (New-Object Drawing.Point 64, 64), [Drawing.Color]::FromArgb(96, 205, 255), [Drawing.Color]::FromArgb(123, 92, 255))
$g.FillPath($br, $p)
$f = New-Object Drawing.StringFormat; $f.Alignment = 'Center'; $f.LineAlignment = 'Center'
$g.DrawString('R', (New-Object Drawing.Font 'Segoe UI', 34, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)), [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, 2, 64, 64), $f)
$fs = [IO.File]::Create($ico); [Drawing.Icon]::FromHandle($bmp.GetHicon()).Save($fs); $fs.Close()

$fv = '0.0.0.0'
try { $v = [version]$Version; $fv = '{0}.{1}.{2}.0' -f $v.Major, $v.Minor, [Math]::Max($v.Build, 0) } catch {}
$out = Join-Path $dist 'RepackShelf.exe'
Invoke-ps2exe -inputFile (Join-Path $Root 'src\RepackShelf.ps1') -outputFile $out -iconFile $ico -noConsole -STA -x64 `
    -title 'Repack Shelf' -product 'Repack Shelf' -description 'Game library manager' -version $fv
Remove-Item $ico -ErrorAction SilentlyContinue
if (-not (Test-Path $out)) { throw 'Build failed.' }
Write-Host "Built $out" -ForegroundColor Green
