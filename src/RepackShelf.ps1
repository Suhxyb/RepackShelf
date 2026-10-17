$AppVersion = '__VERSION__'; $RepoSlug = '__REPO__'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Drawing,System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Dwm { [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s); }
"@
Add-Type -TypeDefinition @'
using System.ComponentModel;
public class RsBadge { public string Text {get;set;} public string Color {get;set;} }
public class RsGame : INotifyPropertyChanged {
  public event PropertyChangedEventHandler PropertyChanged;
  void N(string p) { var h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(p)); }
  public string Key {get;set;} public string KeyPath {get;set;} public string Name {get;set;} public string Dir {get;set;}
  public string UnExe {get;set;} public string Exe {get;set;} public string Version {get;set;} public string Date {get;set;} public string Tags {get;set;}
  public object Badges {get;set;} public object Icon {get;set;} public string Accent {get;set;} public string Letter {get;set;} public string IconSrc {get;set;}
  object cover; public object Cover { get { return cover; } set { cover = value; N("Cover"); } }
  string size; public string Size { get { return size; } set { size = value; N("Meta"); } }
  public string Meta { get { return "Folder   " + Dir + "\nSize   " + (Size ?? "calculating...") + "\nVersion   " + (Version ?? "n/a") + "\nInstalled   " + (Date ?? "n/a") + "\nLaunches   " + (Exe ?? "no executable found - use Set .exe"); } }
}
'@

# ---------- config ----------
$appDir = Join-Path $env:APPDATA 'RepackShelf'; $coverDir = Join-Path $appDir 'covers'
New-Item -ItemType Directory -Force $coverDir | Out-Null
$cfgPath = Join-Path $appDir 'config.json'
$script:cfg = @{}
if (Test-Path $cfgPath) { try { (Get-Content $cfgPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:cfg[$_.Name] = $_.Value } } catch {} }
function Save-Cfg { $script:cfg | ConvertTo-Json | Set-Content $cfgPath }
$libPath = Join-Path $appDir 'library.json'
$script:ofCache = @{}; $script:datCache = @{}; $script:exeCache = @{}; $script:fullScan = $false; $script:scanning = $false

# ---------- helpers ----------
function Fmt($b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }
function Get-DirSize($d) { $s = 0L; try { foreach ($f in [IO.Directory]::EnumerateFiles($d, '*', [IO.SearchOption]::AllDirectories)) { try { $s += ([IO.FileInfo]$f).Length } catch {} } } catch {}; $s }
function Ask($t) { [Windows.MessageBox]::Show($t, 'Repack Shelf', 'YesNo', 'Warning') -eq 'Yes' }
function Tell($t) { [void][Windows.MessageBox]::Show($t, 'Repack Shelf', 'OK', 'Information') }
function Cache-Path($key) { Join-Path $coverDir (([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($key))) -replace '-') + '.jpg') }
function Find-OF($dir, $depth = 3) {
    try {
        if ([IO.Directory]::EnumerateFiles($dir, 'OnlineFix*').GetEnumerator().MoveNext()) { return $true }
        if ($depth -gt 0) { foreach ($d in [IO.Directory]::EnumerateDirectories($dir)) { if (Find-OF $d ($depth - 1)) { return $true } } }
    } catch {}
    $false
}
function Find-OFCached($dir) {
    $t = try { "$((Get-Item -LiteralPath $dir -ErrorAction Stop).LastWriteTimeUtc.Ticks)" } catch { '0' }
    $e = $script:ofCache[$dir]
    if (-not $script:fullScan -and $e -and $e.T -eq $t) { return [bool]$e.V }
    $v = Find-OF $dir
    $script:ofCache[$dir] = @{ T = $t; V = $v }
    $v
}
function Get-InnoTag($dat) {
    try {
        if (-not (Test-Path -LiteralPath $dat)) { return 'Inno' }
        $fi = Get-Item -LiteralPath $dat
        if ($fi.Length -ge 8MB) { return 'Inno' }
        $L = "$($fi.Length)"; $e = $script:datCache[$dat]
        if (-not $script:fullScan -and $e -and $e.L -eq $L) { return $e.V }
        $txt = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($dat)) -replace "`0", ''
        $v = if ($txt -match '(?i)fit-?girl') { 'FitGirl' } elseif ($txt -match '(?i)dodi[- ]?repack|\bdodi\b') { 'DODI' } else { 'Inno' }
        $script:datCache[$dat] = @{ L = $L; V = $v }
        $v
    } catch { 'Inno' }
}
function Step($i, $total, $text) {
    $busy.IsIndeterminate = $false; $busy.Maximum = [Math]::Max($total, 1); $busy.Value = $i; $busy.Visibility = 'Visible'
    $status.Text = $text
    $w.Dispatcher.Invoke([action]{}, 'Render')
}
function Save-Library {
    try {
        $recs = @($script:games | ForEach-Object { [pscustomobject]@{ Key = $_.Key; KeyPath = $_.KeyPath; Name = $_.Name; Dir = $_.Dir; UnExe = $_.UnExe; Tags = $_.Tags; Exe = $_.Exe; IconSrc = $_.IconSrc; Version = $_.Version; Date = $_.Date; Size = $_.Size } })
        [pscustomobject]@{ v = 1; games = $recs; of = $script:ofCache; dat = $script:datCache } | ConvertTo-Json -Depth 4 | Set-Content $libPath -Encoding UTF8
    } catch {}
}
function Load-Library {
    if (-not (Test-Path $libPath)) { return }
    try {
        $d = Get-Content $libPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($d.of) { foreach ($p in $d.of.PSObject.Properties) { $script:ofCache[$p.Name] = @{ T = "$($p.Value.T)"; V = [bool]$p.Value.V } } }
        if ($d.dat) { foreach ($p in $d.dat.PSObject.Properties) { $script:datCache[$p.Name] = @{ L = "$($p.Value.L)"; V = "$($p.Value.V)" } } }
        $games = @()
        foreach ($r in @($d.games)) {
            if (-not $r.Dir -or -not (Test-Path -LiteralPath $r.Dir) -or "$($r.Tags)" -eq 'Inno') { continue }
            $script:exeCache[$r.Key] = $r.Exe
            $rec = [pscustomobject]@{ Key = $r.Key; KeyPath = $r.KeyPath; Name = $r.Name; Dir = $r.Dir; UnExe = $r.UnExe; Tags = @("$($r.Tags)" -split ','); IconSrc = $r.IconSrc; Version = $r.Version; Date = $r.Date }
            $g = New-Game $rec
            if ($r.Size) { $g.Size = $r.Size }
            $games += $g
        }
        $script:games = $games; $script:byKey = @{}
        foreach ($g in $games) { $script:byKey[$g.Key] = $g }
    } catch {}
}
function Get-Term($n) {
    $n = $n -replace '\[[^\]]*\]|\([^\)]*\)', ' ' -replace '[\u2122\u00AE\u00A9]', ' ' -replace '(?i)[-_. ]?online-?fix', ' ' -replace '(?i)\b(v|ver|version|build)[\s\.]?\d[\w\.]*.*$', ' ' -replace '(?i)\b(repack|fitgirl|dodi|goty|deluxe|ultimate|complete|definitive)\s*(edition)?\b', ' ' -replace '[_\.]', ' ' -replace '\s+', ' '
    $n.Trim(' ', '-')
}
function Get-Exe($dir) { try { Get-Exe2 $dir } catch { $null } }
function Get-Exe2($dir) {
    $bad = '^(unins|UnityCrash|UE4Prereq|vc_?redist|dxsetup|dotnet|CrashReport|oalinst|installer|setup)|redist|crashpad'
    Get-ChildItem -LiteralPath $dir -Filter *.exe -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch $bad -and $_.DirectoryName -notmatch 'CommonRedist|Redist|Support' } |
        Sort-Object Length -Descending | Select-Object -First 1 -ExpandProperty FullName
}
function Get-Icon($path) {
    try {
        $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
        $bs = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ic.Handle, [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        $bs.Freeze(); $bs
    } catch { $null }
}
function Load-Img($path) {
    try { $b = New-Object Windows.Media.Imaging.BitmapImage; $b.BeginInit(); $b.CacheOption = 'OnLoad'; $b.DecodePixelWidth = 400; $b.UriSource = [Uri]$path; $b.EndInit(); $b.Freeze(); $b } catch { $null }
}

# ---------- detection ----------
$TagColor = @{ FitGirl = '#C2185B'; DODI = '#1976D2'; Repack = '#6A1B9A'; OnlineFix = '#2E7D32'; Inno = '#555555' }
$TagText = @{ FitGirl = 'FitGirl'; DODI = 'DODI'; Repack = 'Repack'; OnlineFix = 'OnlineFix'; Inno = 'Inno Setup' }
function New-Game($r) {
    $tags = @($r.Tags)
    $g = New-Object RsGame
    $g.Key = $r.Key; $g.KeyPath = $r.KeyPath; $g.Name = $r.Name; $g.Dir = $r.Dir; $g.UnExe = $r.UnExe; $g.Version = $r.Version; $g.Date = $r.Date; $g.Tags = ($tags -join ',')
    $exe = $script:cfg["exe:$($r.Key)"]
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { $exe = $script:exeCache[$r.Key] }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { $exe = Get-Exe $r.Dir }
    $script:exeCache[$r.Key] = $exe; $g.Exe = $exe
    $ico = $r.IconSrc
    if (-not $ico -or $ico -match '[<>|"*?]' -or -not (Test-Path -LiteralPath $ico) -or $ico -match 'unins') { $ico = $exe }
    $g.IconSrc = $ico
    if ($ico) { $g.Icon = Get-Icon $ico }
    $g.Badges = @($tags | ForEach-Object { New-Object RsBadge -Property @{ Text = $TagText[$_]; Color = $TagColor[$_] } })
    $c = Cache-Path $r.Key
    if (Test-Path $c) { $g.Cover = Load-Img $c }
    $pal = '#5B2A86', '#1F4E79', '#7A1F3D', '#1E6B52', '#8A4B08', '#2D3E8F', '#6B2D5C', '#2F5D62'
    $h = 0; foreach ($ch in "$($r.Name)".ToCharArray()) { $h = ($h * 31 + [int]$ch) % 1000003 }
    $g.Accent = $pal[$h % $pal.Count]; $g.Letter = if ($r.Name) { "$($r.Name)".Substring(0, 1).ToUpper() } else { '?' }
    $g
}
function Scan {
    $out = @(); $seen = @{}
    $fg = '(?i)fit-?girl'; $dd = '(?i)dodi[- ]?repack|\bdodi\b'
    $srcs = @(
        @([Microsoft.Win32.Registry]::LocalMachine, 'HKEY_LOCAL_MACHINE', 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'),
        @([Microsoft.Win32.Registry]::LocalMachine, 'HKEY_LOCAL_MACHINE', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'),
        @([Microsoft.Win32.Registry]::CurrentUser, 'HKEY_CURRENT_USER', 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'))
    $entries = @()
    foreach ($s in $srcs) {
        try { $rk = $s[0].OpenSubKey($s[2]); if ($rk) { foreach ($n in $rk.GetSubKeyNames()) { $entries += [pscustomobject]@{ Hive = $s[0]; HiveName = $s[1]; Sub = $s[2]; Name = $n } }; $rk.Close() } } catch {}
    }
    $folders = @($script:cfg['folders'])
    foreach ($d in [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' }) { foreach ($n in 'Games', 'Game', 'OnlineFix', 'Downloads') { $folders += ($d.Name + $n) } }
    $folders += (Join-Path $env:USERPROFILE 'Games'), (Join-Path $env:USERPROFILE 'Downloads')
    $roots = @($folders | Where-Object { $_ -and ($_ -notmatch '[<>|"*?]') -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
    $kids = @{}; $nk = 0
    foreach ($r in $roots) { $kids[$r] = @(try { [IO.Directory]::EnumerateDirectories($r) } catch { @() }); $nk += $kids[$r].Count }
    $total = $entries.Count + $nk; $i = 0

    foreach ($e in $entries) {
        $i++; if ($i % 15 -eq 0) { Step $i $total "Scanning installed programs ($i of $total)..." }
        try {
            $rk = $e.Hive.OpenSubKey("$($e.Sub)\$($e.Name)"); if (-not $rk) { continue }
            $p = @{}
            foreach ($n in 'DisplayName', 'UninstallString', 'InstallLocation', 'Publisher', 'URLInfoAbout', 'URLUpdateInfo', 'HelpLink', 'Comments', 'DisplayIcon', 'DisplayVersion', 'InstallDate', 'SystemComponent') { $p[$n] = "$($rk.GetValue($n))" }
            $rk.Close()
            if (-not $p.DisplayName -or -not $p.UninstallString -or $p.SystemComponent -eq '1') { continue }
            $name = $e.Name; $un = $p.UninstallString.Trim()
            $unExe = if ($un -match '(?i)([a-z]:\\[^"<>|*?]*?\.exe)') { $Matches[1] } else { $null }
            $blob = "$($p.DisplayName) $($p.Publisher) $($p.URLInfoAbout) $($p.URLUpdateInfo) $($p.HelpLink) $($p.Comments) $($p.InstallLocation)"
            $inno = ($name -like '*_is1') -or ($unExe -and $unExe -match 'unins\d{3}\.exe$')
            $tags = @()
            if ($blob -match $fg) { $tags = @('FitGirl') } elseif ($blob -match $dd) { $tags = @('DODI') }
            elseif ($inno) {
                $dat = if ($unExe) { Join-Path (Split-Path $unExe -Parent) ([IO.Path]::GetFileNameWithoutExtension($unExe) + '.dat') } else { $null }
                $t = if ($dat) { Get-InnoTag $dat } else { 'Inno' }
                if ($t -eq 'Inno') { if ($script:cfg["tag:$name"]) { $tags = @('Repack') } else { continue } } else { $tags = @($t) }
            }
            if (-not $tags) { continue }
            $dir = $p.InstallLocation.Trim('"', ' ', '\')
            if (-not $dir -and $unExe) { $dir = Split-Path $unExe -Parent }
            if ($dir) { $dir = $dir.Trim() }
            if (-not $dir -or $dir -match '[<>|"*?]' -or -not (Test-Path -LiteralPath $dir) -or $seen[$dir.ToLower()]) { continue }
            if (Find-OFCached $dir) { $tags += 'OnlineFix' }
            $date = $null
            if ($p.InstallDate -match '^\d{8}$') { $date = [datetime]::ParseExact($p.InstallDate, 'yyyyMMdd', $null).ToString('d MMM yyyy') }
            $seen[$dir.ToLower()] = 1
            $out += [pscustomobject]@{ Key = $name; KeyPath = "Registry::$($e.HiveName)\$($e.Sub)\$name"; Name = $p.DisplayName; Dir = $dir; UnExe = $unExe; Tags = $tags; IconSrc = ($p.DisplayIcon -split ',')[0].Trim('"'); Version = $p.DisplayVersion; Date = $date }
        } catch { continue }
    }

    # folder-based games (OnlineFix releases are usually extracted, not installed)
    $userRoots = @($script:cfg['folders'])
    foreach ($r in $roots) {
        $hits = @()
        foreach ($c in $kids[$r]) {
            $i++; if ($i % 6 -eq 0) { Step $i $total "Scanning game folders ($i of $total)..." }
            if (Find-OFCached $c) { $hits += $c }
        }
        if (-not $hits -and ($userRoots -contains $r) -and (Find-OFCached $r)) { $hits = @($r) }
        foreach ($d in $hits) {
            try {
                $dl = $d.ToLower().TrimEnd('\')
                if ($seen[$dl] -or ($seen.Keys | Where-Object { $dl.StartsWith($_.TrimEnd('\') + '\') -or $_.TrimEnd('\').StartsWith($dl + '\') })) { continue }
                $seen[$dl] = 1
                $nm = ((Split-Path $d -Leaf) -replace '(?i)[-_. ]?online-?fix', '' -replace '[_\.]', ' ').Trim()
                $un = Get-ChildItem -LiteralPath $d -Filter 'unins*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
                $out += [pscustomobject]@{ Key = "dir:$d"; KeyPath = $null; Name = $nm; Dir = $d; UnExe = $un; Tags = @('OnlineFix'); IconSrc = $null; Version = $null; Date = (Get-Item -LiteralPath $d).CreationTime.ToString('d MMM yyyy') }
            } catch { continue }
        }
    }
    Step $total $total 'Finishing...'
    $out | Sort-Object Name
}
function Build-Games($recs) {
    $old = @{}
    foreach ($g in $script:games) { $old[$g.Key] = $g }
    foreach ($r in $recs) {
        $o = $old[$r.Key]
        if ($o -and $o.Dir -eq $r.Dir -and $o.Name -eq $r.Name -and $o.Tags -eq (@($r.Tags) -join ',')) { $o } else { New-Game $r }
    }
}

# ---------- background workers (cover art + sizes) ----------
$coverSb = {
    param($jobs, $q)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $norm = { param($s) ($s -replace '[^a-zA-Z0-9]', '').ToLower() }
    $junk = '(?i)soundtrack|\bost\b|\bdlc\b|\bdemo\b|bundle|artbook|season pass|playtest|dedicated server|\bbeta\b'
    $get = { param($url, $out) try { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec 20; if ((Get-Item $out).Length -gt 2000) { $true } else { Remove-Item $out -ErrorAction SilentlyContinue; $false } } catch { Remove-Item $out -ErrorAction SilentlyContinue; $false } }
    $search = {
        param($term, $loose)
        $c = @()
        try { $r = Invoke-RestMethod -Uri ('https://store.steampowered.com/api/storesearch/?l=english&cc=US&term=' + [uri]::EscapeDataString($term)) -TimeoutSec 15; foreach ($i in $r.items) { $c += [pscustomobject]@{ Id = "$($i.id)"; Name = $i.name } } } catch {}
        try { $r = Invoke-RestMethod -Uri ('https://steamcommunity.com/actions/SearchApps/' + [uri]::EscapeDataString($term)) -TimeoutSec 15; foreach ($i in $r) { $c += [pscustomobject]@{ Id = "$($i.appid)"; Name = $i.name } } } catch {}
        $c = @($c | Where-Object { $_.Name -and $_.Name -notmatch $junk })
        $n = & $norm $term
        $hit = $c | Where-Object { (& $norm $_.Name) -eq $n } | Select-Object -First 1
        if (-not $hit -and $n.Length -ge 3) { $hit = $c | Where-Object { $m = & $norm $_.Name; $m.Length -ge 3 -and ($m.StartsWith($n) -or $n.StartsWith($m)) } | Select-Object -First 1 }
        if (-not $hit -and $loose) { $hit = $c | Select-Object -First 1 }
        if ($hit) { $hit.Id }
    }
    foreach ($j in $jobs) {
        try {
            $id = $null
            if ($j.Id) { $id = $j.Id }
            if (-not $id) { foreach ($f in @(Get-ChildItem -LiteralPath $j.Dir -Filter 'OnlineFix*.ini' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue)) {
                if ((Get-Content $f.FullName -Raw) -match '(?im)^\s*RealAppId\s*=\s*(\d+)') { $id = $Matches[1]; break } } }
            if (-not $id) { foreach ($f in @(Get-ChildItem -LiteralPath $j.Dir -Filter 'steam_appid.txt' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue)) {
                $t = (Get-Content $f.FullName -Raw).Trim(); if ($t -match '^\d+$' -and $t -ne '480') { $id = $t; break } } }
            if (-not $id -and $j.Term) {
                $t = $j.Term
                $vars = @($t, ($t -creplace '([a-z])([A-Z])', '$1 $2' -creplace '([A-Za-z])(\d)', '$1 $2'), ($t -split '\s[-:]\s|:\s')[0], (($t -replace '(?i)\b(remastered|remake|enhanced|special|anniversary|director.s cut|edition|the)\b', ' ') -replace '\s+', ' ').Trim())
                $words = @($t -split ' ')
                if ($words.Count -gt 3) { $vars += ($words[0..2] -join ' ') }
                if ($words.Count -gt 2) { $vars += ($words[0..1] -join ' ') }
                $vars = @($vars | Where-Object { $_ -and $_.Length -ge 3 } | Select-Object -Unique)
                foreach ($v in $vars) { $id = & $search $v $false; if ($id) { break } }
                if (-not $id -and $vars) { $id = & $search $vars[0] $true }
            }
            $ok = $false
            if ($id) {
                $base = "https://cdn.cloudflare.steamstatic.com/steam/apps/$id/"
                foreach ($u in 'library_600x900_2x.jpg', 'library_600x900.jpg', 'header.jpg', 'capsule_616x353.jpg') { if (& $get ($base + $u) $j.Cache) { $ok = $true; break } }
                if (-not $ok) { try { $d = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails?appids=$id" -TimeoutSec 15; $img = $d.$id.data.header_image; if ($img -and (& $get $img $j.Cache)) { $ok = $true } } catch {} }
            }
            if ($ok) { $q.Enqueue([pscustomobject]@{ T = 'cover'; K = $j.Key; V = $j.Cache }) }
            else { if (-not $id) { Set-Content "$($j.Cache).none" '' }; $q.Enqueue([pscustomobject]@{ T = 'miss'; K = $j.Key }) }
        } catch {}
    }
}
$sizeSb = {
    param($jobs, $q)
    foreach ($j in $jobs) {
        $s = 0L
        try { foreach ($f in [IO.Directory]::EnumerateFiles($j.Dir, '*', [IO.SearchOption]::AllDirectories)) { try { $s += ([IO.FileInfo]$f).Length } catch {} } } catch {}
        $q.Enqueue([pscustomobject]@{ T = 'size'; K = $j.Key; V = $s })
    }
}
$updSb = {
    param($job, $q)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$($job.Slug)/releases/latest" -Headers @{ 'User-Agent' = 'RepackShelf' } -TimeoutSec 15
        $exe = $r.assets | Where-Object { $_.name -eq 'RepackShelf.exe' } | Select-Object -First 1
        $sha = $r.assets | Where-Object { $_.name -eq 'RepackShelf.exe.sha256' } | Select-Object -First 1
        $q.Enqueue([pscustomobject]@{ T = 'update'; Ok = $true; Manual = $job.Manual; Tag = $r.tag_name; Url = $exe.browser_download_url; Sha = $sha.browser_download_url; Page = $r.html_url })
    } catch { $q.Enqueue([pscustomobject]@{ T = 'update'; Ok = $false; Manual = $job.Manual }) }
}
$script:q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$script:bg = @()
function Start-Bg($sb, $jobs, $track = $true) {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($sb.ToString()).AddArgument($jobs).AddArgument($script:q)
    if ($track) { $script:bg += [pscustomobject]@{ PS = $ps; H = $ps.BeginInvoke() } } else { [void]$ps.BeginInvoke() }
}

# ---------- UI ----------
# ---------- theming (defaults = the original dark look) ----------
$Themes = @{
    Dark     = @{ Bg = '#1B1B1D'; Panel = '#242427'; Panel2 = '#2F2F34'; Card = '#2B2B2E'; Btn = '#38383C'; Hover = '#2E2E32'; Text = '#F3F3F3'; Sub = '#B4B4B8'; Muted = '#808085'; ChipText = '#DDDDDD'; Thumb = '#5A5A5F'; IsDark = $true }
    Midnight = @{ Bg = '#000000'; Panel = '#0C0C0E'; Panel2 = '#141417'; Card = '#131316'; Btn = '#1F1F23'; Hover = '#18181B'; Text = '#F3F3F3'; Sub = '#A2A2A8'; Muted = '#6F6F78'; ChipText = '#D0D0D0'; Thumb = '#3A3A40'; IsDark = $true }
    Slate    = @{ Bg = '#151A21'; Panel = '#1C232C'; Panel2 = '#232C37'; Card = '#212A35'; Btn = '#2E3846'; Hover = '#263140'; Text = '#E8EEF5'; Sub = '#A9B6C6'; Muted = '#77869A'; ChipText = '#D3DCE8'; Thumb = '#455063'; IsDark = $true }
    Light    = @{ Bg = '#F1F1F5'; Panel = '#FFFFFF'; Panel2 = '#FFFFFF'; Card = '#E4E4EA'; Btn = '#D9D9E0'; Hover = '#E8E8EE'; Text = '#1B1B1D'; Sub = '#55555C'; Muted = '#7B7B84'; ChipText = '#33333A'; Thumb = '#B5B5BC'; IsDark = $false }
}
$Accents = '#60CDFF', '#7C83FF', '#C77DFF', '#FF6B9D', '#FF8A4C', '#FFC83D', '#3DDC97', '#2DD4BF'
$script:animOn = $true; $script:syncing = $false
function New-Brush($hex) { $c = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex); $b = [Windows.Media.SolidColorBrush]::new($c); $b.Freeze(); $b }
function Set-Res($k, $v) { $o = $v; if ($o -is [psobject] -and $o.psobject.BaseObject) { $o = $o.psobject.BaseObject }; $script:app.Resources.set_Item([string]$k, [object]$o) }
function Mix($a, $b, $f) {
    $x = [Windows.Media.ColorConverter]::ConvertFromString($a); $y = [Windows.Media.ColorConverter]::ConvertFromString($b)
    [Windows.Media.Color]::FromRgb([byte][Math]::Round($x.R + ($y.R - $x.R) * $f), [byte][Math]::Round($x.G + ($y.G - $x.G) * $f), [byte][Math]::Round($x.B + ($y.B - $x.B) * $f))
}
function Set-TitleBar {
    if (-not $w) { return }
    $h = (New-Object Windows.Interop.WindowInteropHelper $w).Handle
    if ($h -eq [IntPtr]::Zero) { return }
    $v = if ($script:themeDark) { 1 } else { 0 }; [void][Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)
    $col = [Windows.Media.ColorConverter]::ConvertFromString($script:themeBg); $c = [int]$col.R + ([int]$col.G * 256) + ([int]$col.B * 65536)
    [void][Dwm]::DwmSetWindowAttribute($h, 35, [ref]$c, 4)
}
function Apply-Theme {
    $tn = "$($script:cfg['ui:theme'])"; if (-not $Themes.ContainsKey($tn)) { $tn = 'Dark' }
    $t = $Themes[$tn]
    $acc = "$($script:cfg['ui:accent'])"; if ($acc -notmatch '^#[0-9A-Fa-f]{6}$') { $acc = '#60CDFF' }
    $r = $app.Resources
    foreach ($k in 'Text', 'Sub', 'Muted', 'ChipText', 'Thumb', 'Card', 'Btn', 'Hover', 'Panel', 'Panel2') { Set-Res "Ui$k" (New-Brush $t[$k]) }
    Set-Res 'UiAccent' (New-Brush $acc)
    $c = [Windows.Media.ColorConverter]::ConvertFromString($acc)
    Set-Res 'UiAccentFg' (New-Brush $(if ((0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B) -gt 150) { '#101010' } else { '#FFFFFF' }))
    if ("$($script:cfg['ui:bg'])" -eq 'Glow') {
        $gb = [Windows.Media.LinearGradientBrush]::new(); $gb.StartPoint = '0,0'; $gb.EndPoint = '1,1'
        $f = if ($t.IsDark) { 0.22 } else { 0.14 }
        [void]$gb.GradientStops.Add((New-Object Windows.Media.GradientStop (Mix $t.Bg $acc $f), 0.0))
        [void]$gb.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($t.Bg)), 0.62))
        $gb.Freeze(); Set-Res 'UiWinBg' $gb
    } else { Set-Res 'UiWinBg' (New-Brush $t.Bg) }
    $sz = switch ("$($script:cfg['ui:size'])") { 'Small' { 140, 210 } 'Large' { 212, 318 } default { 172, 258 } }
    Set-Res 'UiPW' ([double]$sz[0]); Set-Res 'UiPH' ([double]$sz[1])
    $script:animOn = "$($script:cfg['ui:anim'])" -ne 'Off'
    $script:themeBg = $t.Bg; $script:themeDark = [bool]$t.IsDark
    Set-TitleBar
}
function Anim-Slide($el, $axis, $from, $ms = 350, $delay = 0) {
    if (-not $script:animOn) { $el.Opacity = 1; $el.RenderTransform = $null; return }
    if ($delay -gt 0) { $el.Opacity = 0 }
    $tt = New-Object Windows.Media.TranslateTransform; $el.RenderTransform = $tt
    $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms)); $ea = New-Object Windows.Media.Animation.CubicEase; $ea.EasingMode = 'EaseOut'
    $a = New-Object Windows.Media.Animation.DoubleAnimation 0, 1, $dur; $a.BeginTime = [TimeSpan]::FromMilliseconds($delay)
    $b = New-Object Windows.Media.Animation.DoubleAnimation $from, 0, $dur; $b.EasingFunction = $ea; $b.BeginTime = $a.BeginTime
    $el.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
    $prop = if ($axis -eq 'x') { [Windows.Media.TranslateTransform]::XProperty } else { [Windows.Media.TranslateTransform]::YProperty }
    $tt.BeginAnimation($prop, $b)
}
function Fade($el, $from, $ms) {
    if (-not $script:animOn) { return }
    $a = New-Object Windows.Media.Animation.DoubleAnimation $from, 1, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms)))
    $el.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
}
$app = [Windows.Application]::Current; if (-not $app) { $app = New-Object Windows.Application }
$app.Resources = [Windows.Markup.XamlReader]::Parse(@'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <Style x:Key="Btn" TargetType="Button">
  <Setter Property="Foreground" Value="{DynamicResource UiText}"/><Setter Property="Background" Value="{DynamicResource UiBtn}"/><Setter Property="Padding" Value="14,10"/>
  <Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="13.5"/><Setter Property="Margin" Value="0,0,0,8"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
   <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}" RenderTransformOrigin="0.5,0.5"><Border.RenderTransform><ScaleTransform/></Border.RenderTransform><ContentPresenter HorizontalAlignment="Center"/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.82"/></Trigger>
    <Trigger Property="IsPressed" Value="True">
     <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="0.95" Duration="0:0:0.08"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="0.95" Duration="0:0:0.08"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
     <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.16"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.16"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
    </Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.35"/></Trigger>
   </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style x:Key="Chip" TargetType="RadioButton">
  <Setter Property="Margin" Value="0,0,6,0"/><Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
   <Border x:Name="b" Background="{DynamicResource UiCard}" CornerRadius="15" Padding="14,6"><TextBlock x:Name="t" Text="{TemplateBinding Content}" FontSize="12.5" Foreground="{DynamicResource UiChipText}"/></Border>
   <ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource UiAccent}"/><Setter TargetName="t" Property="Foreground" Value="{DynamicResource UiAccentFg}"/></Trigger></ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style TargetType="ListBoxItem">
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem">
   <Border x:Name="b" CornerRadius="12" Padding="3" Margin="5" BorderThickness="2" BorderBrush="Transparent" Background="Transparent" RenderTransformOrigin="0.5,0.5"><Border.RenderTransform><ScaleTransform/></Border.RenderTransform><ContentPresenter/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource UiHover}"/>
    <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.045" Duration="0:0:0.14"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.045" Duration="0:0:0.14"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
    <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.18"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.18"/></Storyboard></BeginStoryboard></Trigger.ExitActions></Trigger>
    <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource UiAccent}"/></Trigger>
   </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style TargetType="ScrollBar"><Setter Property="Width" Value="10"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
  <Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="True"><Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="{DynamicResource UiThumb}" CornerRadius="4" Margin="2"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track></Grid>
 </ControlTemplate></Setter.Value></Setter></Style>
 <Style x:Key="Swatch" TargetType="Button"><Setter Property="Width" Value="30"/><Setter Property="Height" Value="30"/><Setter Property="Margin" Value="0,0,8,8"/><Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
   <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="2" CornerRadius="15" RenderTransformOrigin="0.5,0.5"><Border.RenderTransform><ScaleTransform/></Border.RenderTransform></Border>
   <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True">
    <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.2" Duration="0:0:0.12"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.2" Duration="0:0:0.12"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
    <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.15"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.15"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
   </Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style x:Key="CoverRect" TargetType="Rectangle"><Style.Triggers><DataTrigger Binding="{Binding Cover}" Value="{x:Null}"><Setter Property="Opacity" Value="0"/>
  <DataTrigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.7"/></Storyboard></BeginStoryboard></DataTrigger.ExitActions>
 </DataTrigger></Style.Triggers></Style>
</ResourceDictionary>
'@)
Apply-Theme
$w = try { [Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="Repack Shelf" Width="1240" Height="780" MinWidth="980" MinHeight="600"
 WindowStartupLocation="CenterScreen" FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True">
 <Window.Triggers><EventTrigger RoutedEvent="Window.Loaded"><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.45"/></Storyboard></BeginStoryboard></EventTrigger></Window.Triggers>
 <Grid>
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid Margin="24,18,24,8">
   <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="300"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <TextBlock Text="Repack Shelf" FontSize="25" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,24,0"/>
   <Border Grid.Column="1" Background="{DynamicResource UiCard}" CornerRadius="9" Padding="12,2">
    <Grid><TextBox x:Name="search" Background="Transparent" Foreground="{DynamicResource UiText}" CaretBrush="{DynamicResource UiText}" BorderThickness="0" FontSize="14" Padding="0,7"/>
     <TextBlock x:Name="ph" Text="Search games" Foreground="{DynamicResource UiMuted}" FontSize="14" IsHitTestVisible="False" VerticalAlignment="Center"/></Grid></Border>
   <StackPanel x:Name="chips" Grid.Column="2" Orientation="Horizontal" Margin="18,0,0,0" VerticalAlignment="Center">
    <RadioButton Content="All" Tag="All" IsChecked="True" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="FitGirl" Tag="FitGirl" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="DODI" Tag="DODI" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="OnlineFix" Tag="OnlineFix" Style="{StaticResource Chip}" GroupName="f"/>
    <TextBlock x:Name="count" Foreground="{DynamicResource UiMuted}" VerticalAlignment="Center" Margin="10,0,0,0"/>
   </StackPanel>
   <StackPanel Grid.Column="3" Orientation="Horizontal">
    <Button x:Name="btnCustom" Content="Customise" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
    <Button x:Name="btnUpdate" Content="Updates" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
    <Button x:Name="btnFold" Content="Folders" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
    <Button x:Name="btnScan" Content="Rescan" Style="{StaticResource Btn}" Margin="0"/>
   </StackPanel>
  </Grid>
  <Grid Grid.Row="1" Margin="14,4,0,0">
   <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="350"/></Grid.ColumnDefinitions>
   <ListBox x:Name="list" Foreground="{DynamicResource UiText}" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled" Margin="0,0,6,0">
    <ListBox.ItemsPanel><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></ListBox.ItemsPanel>
    <ListBox.ItemTemplate><DataTemplate>
     <Grid Width="{DynamicResource UiPW}" Height="{DynamicResource UiPH}">
      <Rectangle RadiusX="10" RadiusY="10" Fill="{Binding Accent}"/>
      <TextBlock Text="{Binding Letter}" FontSize="76" FontWeight="Bold" Foreground="#33FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-40,0,0"/>
      <Image Source="{Binding Icon}" Width="48" Height="48" Margin="0,60,0,0" Opacity="0.9"/>
      
      <Rectangle RadiusX="10" RadiusY="10" Style="{StaticResource CoverRect}"><Rectangle.Fill><ImageBrush ImageSource="{Binding Cover}" Stretch="UniformToFill"/></Rectangle.Fill></Rectangle>
      <Border VerticalAlignment="Bottom" Height="96" CornerRadius="0,0,10,10"><Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#00000000" Offset="0"/><GradientStop Color="#E8000000" Offset="1"/></LinearGradientBrush></Border.Background>
       <TextBlock Text="{Binding Name}" Foreground="White" VerticalAlignment="Bottom" Margin="10,0,10,9" TextWrapping="Wrap" MaxHeight="38" FontSize="13" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/></Border>
      <ItemsControl ItemsSource="{Binding Badges}" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="8"><ItemsControl.ItemTemplate><DataTemplate>
       <Border Background="{Binding Color}" CornerRadius="9" Padding="8,2" Margin="0,0,0,4" HorizontalAlignment="Left"><TextBlock Text="{Binding Text}" FontSize="10.5" FontWeight="SemiBold" Foreground="White"/></Border>
      </DataTemplate></ItemsControl.ItemTemplate></ItemsControl>
     </Grid></DataTemplate></ListBox.ItemTemplate>
   </ListBox>
   <Border Grid.Column="1" Background="{DynamicResource UiPanel}" CornerRadius="14,0,0,0" Padding="26,26,26,16">
    <Grid>
     <TextBlock x:Name="empty" Text="Select a game" Foreground="{DynamicResource UiMuted}" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
     <ScrollViewer x:Name="detail" Visibility="Collapsed" VerticalScrollBarVisibility="Auto"><StackPanel>
      <Grid Width="200" Height="300" Margin="0,0,0,16">
       <Rectangle RadiusX="12" RadiusY="12" Fill="{Binding Accent}"/><TextBlock Text="{Binding Letter}" FontSize="96" FontWeight="Bold" Foreground="#33FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-50,0,0"/><Image Source="{Binding Icon}" Width="64" Height="64" Margin="0,80,0,0"/>
       <Rectangle RadiusX="12" RadiusY="12" Style="{StaticResource CoverRect}"><Rectangle.Fill><ImageBrush ImageSource="{Binding Cover}" Stretch="UniformToFill"/></Rectangle.Fill></Rectangle>
      </Grid>
      <TextBlock Text="{Binding Name}" FontSize="21" FontWeight="SemiBold" TextWrapping="Wrap" HorizontalAlignment="Center" TextAlignment="Center"/>
      <ItemsControl ItemsSource="{Binding Badges}" HorizontalAlignment="Center" Margin="0,8,0,14"><ItemsControl.ItemsPanel><ItemsPanelTemplate><StackPanel Orientation="Horizontal"/></ItemsPanelTemplate></ItemsControl.ItemsPanel><ItemsControl.ItemTemplate><DataTemplate>
       <Border Background="{Binding Color}" CornerRadius="10" Padding="10,3" Margin="3,0"><TextBlock Text="{Binding Text}" FontSize="11.5" FontWeight="SemiBold" Foreground="White"/></Border>
      </DataTemplate></ItemsControl.ItemTemplate></ItemsControl>
      <TextBlock Text="{Binding Meta}" Foreground="{DynamicResource UiSub}" FontSize="12.5" LineHeight="22" TextWrapping="Wrap" Margin="0,0,0,18"/>
      <Button x:Name="btnPlay" Content="Play" Style="{StaticResource Btn}" Background="{DynamicResource UiAccent}" Foreground="{DynamicResource UiAccentFg}" FontWeight="SemiBold" FontSize="15" Padding="14,12"/>
      <Button x:Name="btnFolder" Content="Open folder" Style="{StaticResource Btn}"/>
      <Button x:Name="btnExe" Content="Set .exe" Style="{StaticResource Btn}"/>
      <Button x:Name="btnFind" Content="Find cover online..." Style="{StaticResource Btn}"/>
      <Button x:Name="btnCover" Content="Set cover image" Style="{StaticResource Btn}"/>
      <Button x:Name="btnUn" Content="Uninstall completely" Style="{StaticResource Btn}" Background="#C42B1C"/>
     </StackPanel></ScrollViewer>
    </Grid>
   </Border>
  </Grid>
  <Border x:Name="updBar" Grid.RowSpan="3" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,48" Background="{DynamicResource UiPanel2}" BorderBrush="{DynamicResource UiAccent}" BorderThickness="1" CornerRadius="12" Padding="18,12" Visibility="Collapsed">
   <StackPanel Orientation="Horizontal">
    <StackPanel Margin="0,0,20,0" VerticalAlignment="Center"><TextBlock x:Name="updTitle" FontWeight="SemiBold" FontSize="14"/><TextBlock x:Name="updSub" Foreground="{DynamicResource UiSub}" FontSize="12"/></StackPanel>
    <Button x:Name="btnUpd" Content="Update now" Style="{StaticResource Btn}" Background="{DynamicResource UiAccent}" Foreground="{DynamicResource UiAccentFg}" Margin="0,0,8,0" Padding="16,8"/>
    <Button x:Name="btnLater" Content="Later" Style="{StaticResource Btn}" Margin="0" Padding="14,8"/>
   </StackPanel></Border>
  <Border x:Name="settings" Grid.RowSpan="3" HorizontalAlignment="Right" Width="360" Visibility="Collapsed" Background="{DynamicResource UiPanel2}" BorderBrush="{DynamicResource UiCard}" BorderThickness="1,0,0,0" Padding="24,20,24,16">
   <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <Grid><TextBlock Text="Customise" FontSize="21" FontWeight="SemiBold" VerticalAlignment="Center"/><Button x:Name="btnCloseSet" Content="Close" Style="{StaticResource Btn}" HorizontalAlignment="Right" Padding="14,6" Margin="0"/></Grid>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,18,0,0"><StackPanel>
     <TextBlock Text="THEME" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optTheme" Margin="0,8,0,20"><RadioButton Content="Dark" Tag="Dark" GroupName="th" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Midnight" Tag="Midnight" GroupName="th" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Slate" Tag="Slate" GroupName="th" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Light" Tag="Light" GroupName="th" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="ACCENT COLOUR" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/>
     <WrapPanel x:Name="swatches" Margin="0,8,0,4"/>
     <StackPanel Orientation="Horizontal" Margin="0,0,0,20"><Border Background="{DynamicResource UiCard}" CornerRadius="8" Padding="10,2" Margin="0,0,8,0"><TextBox x:Name="hexBox" Width="96" Background="Transparent" Foreground="{DynamicResource UiText}" CaretBrush="{DynamicResource UiText}" BorderThickness="0" Padding="0,6" FontSize="13"/></Border><Button x:Name="btnHex" Content="Apply" Style="{StaticResource Btn}" Padding="14,7" Margin="0"/></StackPanel>
     <TextBlock Text="POSTER SIZE" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optSize" Margin="0,8,0,20"><RadioButton Content="Small" Tag="Small" GroupName="ps" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Medium" Tag="Medium" GroupName="ps" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Large" Tag="Large" GroupName="ps" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="BACKGROUND" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optBg" Margin="0,8,0,20"><RadioButton Content="Solid" Tag="Solid" GroupName="bg" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Glow" Tag="Glow" GroupName="bg" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="ENTRANCE ANIMATIONS" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optAnim" Margin="0,8,0,20"><RadioButton Content="On" Tag="On" GroupName="an" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Off" Tag="Off" GroupName="an" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel>
     <Button x:Name="btnReset" Content="Reset to default" Style="{StaticResource Btn}" Margin="0,4,0,0"/>
    </StackPanel></ScrollViewer></Grid></Border>
  <ProgressBar x:Name="busy" Grid.Row="2" Height="3" VerticalAlignment="Top" IsIndeterminate="True" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource UiAccent}" Visibility="Collapsed"/>
  <TextBlock x:Name="status" Grid.Row="2" Foreground="{DynamicResource UiMuted}" FontSize="12" Margin="26,6,0,10"/>
 </Grid>
</Window>
'@) } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; [void][Windows.MessageBox]::Show("Window XAML failed:`n`n$($e.Message)", 'Repack Shelf', 'OK', 'Error'); exit 1 }
$w.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'UiWinBg'); $w.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'UiText')
foreach ($n in 'search','ph','chips','count','btnFold','btnScan','list','empty','detail','btnPlay','btnFolder','btnExe','btnCover','btnFind','busy','btnUpdate','updBar','updTitle','updSub','btnUpd','btnLater','btnCustom','settings','btnCloseSet','optTheme','optSize','optBg','optAnim','swatches','hexBox','btnHex','btnReset','btnUn','status') { Set-Variable -Name $n -Value $w.FindName($n) -Scope Script }
$w.Title = if ($AppVersion.StartsWith('__')) { 'Repack Shelf (dev build)' } else { "Repack Shelf v$AppVersion" }
$script:filter = 'All'; $script:games = @(); $script:byKey = @{}

function Animate-In {
    if (-not $script:animOn) { return }
    $n = 0; $ease = New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'
    foreach ($it in $list.Items) {
        $c = $list.ItemContainerGenerator.ContainerFromItem($it); if (-not $c) { continue }
        $tt = New-Object Windows.Media.TranslateTransform 0, 26
        $c.RenderTransform = $tt; $c.Opacity = 0
        $begin = [TimeSpan]::FromMilliseconds([Math]::Min($n * 30, 600)); $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(420))
        $a = New-Object Windows.Media.Animation.DoubleAnimation 0, 1, $dur; $a.BeginTime = $begin
        $b = New-Object Windows.Media.Animation.DoubleAnimation 26, 0, $dur; $b.BeginTime = $begin; $b.EasingFunction = $ease
        $c.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
        $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $b)
        $n++
    }
}
function Refresh-List {
    $q = $search.Text.Trim(); $f = $script:filter
    $v = @($script:games | Where-Object {
        $t = $_.Tags
        (($f -eq 'All') -or (($t -split ',') -contains $f)) -and (-not $q -or $_.Name -like "*$q*")
    })
    $list.ItemsSource = $v; $count.Text = "$($v.Count) game(s)"; $list.UpdateLayout(); Animate-In
    if ($v.Count -eq 0) { $empty.Text = if ($script:games.Count -eq 0) { "No repack or OnlineFix games found yet.`nUse Folders to add the folder your games live in." } else { 'Nothing matches this filter' } }
    $detail.Visibility = 'Collapsed'; $empty.Visibility = 'Visible'
}
function Scan-And-Show($full = $false) {
    foreach ($p in $script:bg) { try { $p.PS.Stop() } catch {} }; $script:bg = @(); $script:miss = 0; $script:doneMsg = $false
    if ($full) { $script:ofCache = @{}; $script:datCache = @{}; $script:exeCache = @{} }
    $script:fullScan = $full; $script:scanning = $true; $btnScan.IsEnabled = $false; $w.Cursor = 'Wait'
    $sig = { param($l) (@($l | ForEach-Object { "$($_.Key):$($_.Tags):$($_.Name):$($_.Dir)" }) -join '|') }
    $before = & $sig $script:games
    $recs = @(Scan)
    $script:games = @(Build-Games $recs); $script:byKey = @{}
    foreach ($g in $script:games) { $script:byKey[$g.Key] = $g }
    $script:scanning = $false; $btnScan.IsEnabled = $true; $w.Cursor = $null; $busy.IsIndeterminate = $true; $busy.Visibility = 'Collapsed'
    if ($full -or $script:games.Count -eq 0 -or $before -ne (& $sig $script:games)) { Refresh-List }
    $cj = @(); $sj = @()
    foreach ($g in $script:games) {
        $c = Cache-Path $g.Key; $none = "$c.none"
        if (-not $g.Size -or $full) { $sj += [pscustomobject]@{ Key = $g.Key; Dir = $g.Dir } }
        if (-not (Test-Path $c) -and -not ((Test-Path $none) -and ((Get-Item $none).LastWriteTime -gt (Get-Date).AddDays(-1)))) {
            $cj += [pscustomobject]@{ Key = $g.Key; Dir = $g.Dir; Term = (Get-Term $g.Name); Cache = $c } }
    }
    if ($cj) { Start-Bg $coverSb $cj }
    if ($sj) { Start-Bg $sizeSb $sj }
    $status.Text = "Found $($script:games.Count) game(s). $(if ($cj) { 'Fetching cover art in the background...' })"
    Save-Library
}
function Finish-Remove($i, $confirmed) {
    if (Test-Path -LiteralPath $i.Dir) {
        if ($confirmed -or (Ask "Leftover files remain in:`n$($i.Dir)`n`nDelete them?")) {
            try { Remove-Item -LiteralPath $i.Dir -Recurse -Force -ErrorAction Stop } catch { Tell "Could not delete everything: $($_.Exception.Message)`n`nTry running Repack Shelf as administrator." }
        }
    }
    if ($i.KeyPath -and (Test-Path -LiteralPath $i.KeyPath)) { Remove-Item -LiteralPath $i.KeyPath -Recurse -Force -ErrorAction SilentlyContinue }
    Scan-And-Show
}
function Play {
    $g = $list.SelectedItem
    if ($g -and $g.Exe) { try { Start-Process -FilePath $g.Exe -WorkingDirectory (Split-Path $g.Exe); $status.Text = "Launched $($g.Name)." } catch { Tell "Could not launch: $($_.Exception.Message)" } }
}

function Check-Update($manual) {
    if ($AppVersion.StartsWith('__') -or $RepoSlug.StartsWith('__')) { if ($manual) { Tell 'This is a development build, so update checking is turned off.' }; return }
    if ($manual) { $status.Text = 'Checking for updates...' }
    Start-Bg $updSb ([pscustomobject]@{ Slug = $RepoSlug; Manual = $manual }) $false
}
function Show-Update($m) {
    if (-not $m.Ok) { if ($m.Manual) { Tell 'Could not reach GitHub. Check your internet connection and try again.' }; return }
    $newV = $null; $curV = $null
    try { $newV = [version]($m.Tag.TrimStart('v')); $curV = [version]$AppVersion } catch {}
    if ($newV -and $curV -and $newV -gt $curV) {
        $script:upd = $m
        $updTitle.Text = "Update available: v$newV"; $updSub.Text = "You are on v$curV"
        $btnUpd.IsEnabled = $true; $btnLater.IsEnabled = $true; $updBar.Visibility = 'Visible'
        Anim-Slide $updBar 'y' 40 450
    } elseif ($m.Manual) { $status.Text = "You are on the latest version (v$AppVersion)." }
}
function Install-Update {
    $m = $script:upd
    $self = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if (-not $m.Url -or $self -notmatch '(?i)\.exe$' -or $self -match '(?i)\\(powershell|pwsh|powershell_ise)\.exe$') { Start-Process $m.Page; return }
    $dir = Split-Path $self; $new = Join-Path $dir 'RepackShelf.update.exe'
    try { $t = Join-Path $dir '.rs_write_test'; Set-Content $t 'x' -ErrorAction Stop; Remove-Item $t -ErrorAction SilentlyContinue }
    catch { Tell "Repack Shelf cannot write to its own folder, so it cannot replace itself there.`nOpening the download page instead."; Start-Process $m.Page; return }
    $updTitle.Text = 'Downloading update...'; $updSub.Text = 'Please wait'; $btnUpd.IsEnabled = $false; $btnLater.IsEnabled = $false
    $w.Dispatcher.Invoke([action]{}, 'Render')
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'RepackShelf'
        $wc.DownloadFile($m.Url, $new)
        if ($m.Sha) {
            $want = ($wc.DownloadString($m.Sha).Trim() -split '\s+')[0].ToLower()
            if ((Get-FileHash $new -Algorithm SHA256).Hash.ToLower() -ne $want) { throw 'Checksum mismatch, the download could not be verified.' }
        }
        if ((Get-Item $new).Length -lt 10KB) { throw 'The downloaded file looks too small.' }
    } catch {
        Remove-Item $new -ErrorAction SilentlyContinue
        Tell "Update failed: $($_.Exception.Message)"
        $updTitle.Text = 'Update failed'; $updSub.Text = 'Try again later'; $btnUpd.IsEnabled = $true; $btnLater.IsEnabled = $true; return
    }
    $bat = Join-Path $env:TEMP 'rs_update.bat'
    $lines = '@echo off', 'set n=0', ':retry', 'set /a n+=1', 'ping -n 2 127.0.0.1 >nul', "move /y `"$new`" `"$self`" >nul 2>&1", 'if errorlevel 1 if %n% lss 30 goto retry', "start `"`" `"$self`"", 'del "%~f0"'
    Set-Content $bat $lines -Encoding ASCII
    Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -WindowStyle Hidden
    $w.Close()
}
$script:upd = $null
function Sync-Opts {
    $script:syncing = $true
    $def = @{ theme = 'Dark'; size = 'Medium'; bg = 'Solid'; anim = 'On' }
    foreach ($pair in @(@($optTheme, 'theme'), @($optSize, 'size'), @($optBg, 'bg'), @($optAnim, 'anim'))) {
        $v = "$($script:cfg['ui:' + $pair[1]])"; if (-not $v) { $v = $def[$pair[1]] }
        foreach ($rb in $pair[0].Children) { $rb.IsChecked = ($rb.Tag -eq $v) }
    }
    $acc = "$($script:cfg['ui:accent'])"; if (-not $acc) { $acc = '#60CDFF' }
    $hexBox.Text = $acc
    foreach ($b in $swatches.Children) { $b.BorderBrush = if ($b.Tag -eq $acc) { $app.Resources['UiText'] } else { [Windows.Media.Brushes]::Transparent } }
    $script:syncing = $false
}
function Opt-Changed($rb) {
    if ($script:syncing) { return }
    $k = switch ($rb.Parent.Name) { 'optTheme' { 'theme' } 'optSize' { 'size' } 'optBg' { 'bg' } default { 'anim' } }
    $script:cfg["ui:$k"] = $rb.Tag; Save-Cfg; Apply-Theme; Fade $w.Content 0.9 240
    if ($k -eq 'size') { $list.UpdateLayout(); Animate-In }
}
function Show-Settings { Sync-Opts; $settings.Visibility = 'Visible'; Anim-Slide $settings 'x' 380 380 }
function Hide-Settings {
    if (-not $script:animOn) { $settings.Visibility = 'Collapsed'; return }
    $tt = New-Object Windows.Media.TranslateTransform; $settings.RenderTransform = $tt
    $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(260)); $ea = New-Object Windows.Media.Animation.CubicEase; $ea.EasingMode = 'EaseIn'
    $b = New-Object Windows.Media.Animation.DoubleAnimation 0, 380, $dur; $b.EasingFunction = $ea
    $b.Add_Completed({ $settings.Visibility = 'Collapsed' })
    $tt.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $b)
}
foreach ($hex in $Accents) {
    $b = New-Object Windows.Controls.Button; $b.Style = $app.Resources['Swatch']; $b.Background = New-Brush $hex; $b.Tag = $hex; $b.ToolTip = $hex
    $b.Add_Click({ $script:cfg['ui:accent'] = $args[0].Tag; Save-Cfg; Apply-Theme; Sync-Opts })
    [void]$swatches.Children.Add($b)
}
foreach ($p in $optTheme, $optSize, $optBg, $optAnim) { foreach ($rb in $p.Children) { $rb.Add_Checked({ Opt-Changed $args[0] }) } }
$btnCustom.Add_Click({ if ($settings.Visibility -eq 'Visible') { Hide-Settings } else { Show-Settings } })
$btnCloseSet.Add_Click({ Hide-Settings })
$btnHex.Add_Click({
    $h = $hexBox.Text.Trim(); if ($h -notmatch '^#') { $h = "#$h" }
    if ($h -notmatch '^#[0-9A-Fa-f]{6}$') { Tell 'Enter a colour like #60CDFF (six hex digits).'; return }
    $script:cfg['ui:accent'] = $h.ToUpper(); Save-Cfg; Apply-Theme; Sync-Opts
})
$btnReset.Add_Click({
    foreach ($k in 'ui:theme', 'ui:accent', 'ui:size', 'ui:bg', 'ui:anim') { $script:cfg.Remove($k) }
    Save-Cfg; Apply-Theme; Sync-Opts; Fade $w.Content 0.9 240
})

$pump = New-Object Windows.Threading.DispatcherTimer; $pump.Interval = [TimeSpan]::FromMilliseconds(400)
$pump.Add_Tick({
    $m = $null
    while ($script:q.TryDequeue([ref]$m)) {
        if ($m.T -eq 'update') { Show-Update $m; continue }
        $g = $script:byKey[$m.K]; if (-not $g) { continue }
        if ($m.T -eq 'cover') { $g.Cover = Load-Img $m.V } elseif ($m.T -eq 'size') { $g.Size = Fmt $m.V } else { $script:miss++ }
    }
    $run = @($script:bg | Where-Object { -not $_.H.IsCompleted }).Count -gt 0
    if (-not $script:scanning) { $busy.Visibility = if ($run) { 'Visible' } else { 'Collapsed' } }
    if (-not $run -and $script:bg.Count -gt 0 -and -not $script:doneMsg) {
        $script:doneMsg = $true; Save-Library
        $status.Text = if ($script:miss) { "No cover found for $($script:miss) game(s). Select one and use Find cover online." } else { 'All covers loaded.' }
    }
})
$pump.Start()

$list.Add_SelectionChanged({
    $g = $list.SelectedItem
    if (-not $g) { return }
    $detail.DataContext = $g; $empty.Visibility = 'Collapsed'; $detail.Visibility = 'Visible'
    $btnPlay.IsEnabled = [bool]$g.Exe
    $btnUn.Content = if ($g.UnExe -or $g.KeyPath) { 'Uninstall completely' } else { 'Delete game folder' }
    Anim-Slide $detail 'x' 28 330
})
$list.Add_MouseDoubleClick({ Play })
$search.Add_TextChanged({ $ph.Visibility = if ($search.Text) { 'Collapsed' } else { 'Visible' }; Refresh-List })
foreach ($rb in $chips.Children) { if ($rb -is [Windows.Controls.RadioButton]) { $rb.Add_Checked({ $script:filter = $args[0].Tag; Refresh-List }) } }
$btnScan.ToolTip = 'Click: quick refresh. Shift+click: full rescan.'
$btnScan.Add_Click({ Scan-And-Show (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift) -ne 0) })
$btnUpdate.Add_Click({ Check-Update $true })
$btnUpd.Add_Click({ Install-Update })
$btnLater.Add_Click({ $updBar.Visibility = 'Collapsed' })
$btnPlay.Add_Click({ Play })
$btnFolder.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($list.SelectedItem.Dir)`"" })
$btnExe.Add_Click({
    $g = $list.SelectedItem
    $d = New-Object System.Windows.Forms.OpenFileDialog; $d.InitialDirectory = $g.Dir; $d.Filter = 'Programs (*.exe)|*.exe'
    if ($d.ShowDialog() -eq 'OK') { $script:cfg["exe:$($g.Key)"] = $d.FileName; Save-Cfg; $g.Exe = $d.FileName; $g.Icon = Get-Icon $d.FileName; $detail.DataContext = $null; $detail.DataContext = $g; $btnPlay.IsEnabled = $true }
})
$btnCover.Add_Click({
    $g = $list.SelectedItem
    $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Images|*.jpg;*.jpeg;*.png;*.webp;*.bmp'
    if ($d.ShowDialog() -eq 'OK') { $c = Cache-Path $g.Key; Copy-Item $d.FileName $c -Force; Remove-Item "$c.none" -ErrorAction SilentlyContinue; $g.Cover = Load-Img $c }
})
$btnFind.Add_Click({
    $g = $list.SelectedItem
    Add-Type -AssemblyName Microsoft.VisualBasic
    $in = ([Microsoft.VisualBasic.Interaction]::InputBox("Game name to search on Steam, or a Steam App ID (the number in the store page URL):", 'Find cover', (Get-Term $g.Name))).Trim()
    if (-not $in) { return }
    $c = Cache-Path $g.Key; Remove-Item $c, "$c.none" -ErrorAction SilentlyContinue
    $job = [pscustomobject]@{ Key = $g.Key; Dir = $g.Dir; Term = $in; Cache = $c; Id = $(if ($in -match '^\d+$') { $in }) }
    $g.Cover = $null; $script:miss = 0; $script:doneMsg = $false
    Start-Bg $coverSb @($job); $status.Text = 'Searching for cover...'
})
$btnFold.Add_Click({
    $cur = @($script:cfg['folders'])
    $r = [Windows.MessageBox]::Show("Extra folders scanned for games (besides any 'Games' folder at a drive root):`n`n$(if ($cur) { $cur -join "`n" } else { '(none)' })`n`nYes = add a folder    No = clear this list    Cancel = close", 'Library folders', 'YesNoCancel', 'Question')
    if ($r -eq 'Yes') {
        $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = 'Pick the folder that contains your game folders'
        if ($d.ShowDialog() -eq 'OK') { $script:cfg['folders'] = @($cur + $d.SelectedPath | Select-Object -Unique); Save-Cfg; Scan-And-Show }
    } elseif ($r -eq 'No') { $script:cfg['folders'] = @(); Save-Cfg; Scan-And-Show }
})
$btnUn.Add_Click({
    $i = $list.SelectedItem
    if ($i.UnExe -and (Test-Path -LiteralPath $i.UnExe)) {
        if (-not (Ask "Uninstall $($i.Name)?`n`nIts own uninstaller runs first, then leftover files in`n$($i.Dir)`ncan be removed. Save games outside that folder are not touched.")) { return }
        Start-Process -FilePath $i.UnExe -WorkingDirectory (Split-Path $i.UnExe)
        $status.Text = 'Waiting for the uninstaller to finish...'
        $script:unI = $i; $script:unT0 = Get-Date
        $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(2)
        $t.Add_Tick({
            $i = $script:unI
            $done = if ($i.KeyPath) { -not (Test-Path -LiteralPath $i.KeyPath) } else { -not (Test-Path -LiteralPath $i.UnExe) }
            if ($done) { $args[0].Stop(); Finish-Remove $i $false }
            elseif (((Get-Date) - $script:unT0).TotalMinutes -gt 30) { $args[0].Stop(); $status.Text = 'Uninstall did not complete.' }
        })
        $t.Start()
    } elseif (Ask "$($i.Name) has no uninstaller.`n`nPermanently delete its folder ($(Fmt (Get-DirSize $i.Dir)))?`n$($i.Dir)") { Finish-Remove $i $true }
})

$w.Add_SourceInitialized({ Set-TitleBar })
$w.Add_ContentRendered({ if (-not $script:started) { $script:started = $true
    $n = 0; foreach ($c in $w.Content.Children[0].Children) { Anim-Slide $c 'y' -14 420 ($n * 70); $n++ }
    Load-Library
    if ($script:games.Count) { Refresh-List; $status.Text = "Loaded $($script:games.Count) game(s). Checking for changes..."; $w.Dispatcher.Invoke([action]{}, 'Render') }
    Scan-And-Show; Check-Update $false } })
[void]$w.ShowDialog()
