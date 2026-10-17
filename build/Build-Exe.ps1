param(
    [string]$Version = '0.0.0',
    [string]$Root = (Split-Path $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe
Add-Type -AssemblyName System.Drawing

$dist = Join-Path $Root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

$ico = Join-Path $PSScriptRoot 'RepackShelf.ico'

if (-not (Test-Path $ico)) {
    throw "Icon file not found: $ico"
}

$fv = '0.0.0.0'
try { $v = [version]$Version; $fv = '{0}.{1}.{2}.0' -f $v.Major, $v.Minor, [Math]::Max($v.Build, 0) } catch {}
$out = Join-Path $dist 'RepackShelf.exe'
Invoke-ps2exe -inputFile (Join-Path $Root 'src\RepackShelf.ps1') -outputFile $out -iconFile (Resolve-Path $ico).Path -noConsole -STA -x64 `
    -title 'Repack Shelf' -product 'Repack Shelf' -description 'Game library manager' -version $fv
if (-not (Test-Path $out)) { throw 'Build failed.' }
Write-Host "Built $out" -ForegroundColor Green
