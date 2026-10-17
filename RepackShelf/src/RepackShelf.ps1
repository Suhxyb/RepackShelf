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
  public object Badges {get;set;} public object Icon {get;set;} public string Accent {get;set;} public string Letter {get;set;}
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

# ---------- helpers ----------
function Fmt($b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }
function Get-DirSize($d) { $s = 0L; try { foreach ($f in [IO.Directory]::EnumerateFiles($d, '*', [IO.SearchOption]::AllDirectories)) { try { $s += ([IO.FileInfo]$f).Length } catch {} } } catch {}; $s }
function Ask($t) { [Windows.MessageBox]::Show($t, 'Repack Shelf', 'YesNo', 'Warning') -eq 'Yes' }
function Tell($t) { [void][Windows.MessageBox]::Show($t, 'Repack Shelf', 'OK', 'Information') }
function Cache-Path($key) { Join-Path $coverDir (([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($key))) -replace '-') + '.jpg') }
function Find-OF($dir) { try { foreach ($f in [IO.Directory]::EnumerateFiles($dir, 'OnlineFix*', [IO.SearchOption]::AllDirectories)) { return $true } } catch {}; $false }
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
function New-Game($key, $keyPath, $name, $dir, $unExe, $tags, $icoSrc, $ver, $date) {
    $g = New-Object RsGame
    $g.Key = $key; $g.KeyPath = $keyPath; $g.Name = $name; $g.Dir = $dir; $g.UnExe = $unExe; $g.Version = $ver; $g.Date = $date; $g.Tags = ($tags -join ',')
    $exe = $script:cfg["exe:$key"]
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { $exe = Get-Exe $dir }
    $g.Exe = $exe
    if (-not $icoSrc -or -not (Test-Path -LiteralPath $icoSrc) -or $icoSrc -match 'unins') { $icoSrc = $exe }
    if ($icoSrc) { $g.Icon = Get-Icon $icoSrc }
    $g.Badges = @($tags | ForEach-Object { New-Object RsBadge -Property @{ Text = $TagText[$_]; Color = $TagColor[$_] } })
    $c = Cache-Path $key
    if (Test-Path $c) { $g.Cover = Load-Img $c }
    $pal = '#5B2A86', '#1F4E79', '#7A1F3D', '#1E6B52', '#8A4B08', '#2D3E8F', '#6B2D5C', '#2F5D62'
    $h = 0; foreach ($ch in $name.ToCharArray()) { $h = ($h * 31 + [int]$ch) % 1000003 }
    $g.Accent = $pal[$h % $pal.Count]; $g.Letter = if ($name) { $name.Substring(0, 1).ToUpper() } else { '?' }
    $g
}
function Scan {
    $out = @(); $seen = @{}
    $roots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $fg = '(?i)fit-?girl'; $dd = '(?i)dodi[- ]?repack|\bdodi\b'
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        foreach ($k in Get-ChildItem $r -ErrorAction SilentlyContinue) {
            try {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DisplayName -or -not $p.UninstallString -or $p.SystemComponent -eq 1) { continue }
            $name = $k.PSChildName; $un = "$($p.UninstallString)".Trim()
            $unExe = if ($un -match '(?i)([a-z]:\\[^"<>|*?]*?\.exe)') { $Matches[1] } else { $null }
            $dir = "$($p.InstallLocation)".Trim('"', ' ', '\')
            if (-not $dir -and $unExe) { $dir = Split-Path $unExe -Parent }
            if ($dir) { $dir = $dir.Trim() }
            if (-not $dir -or $dir -match '[<>|"*?]' -or -not (Test-Path -LiteralPath $dir) -or $seen[$dir.ToLower()]) { continue }
            $inno = ($name -like '*_is1') -or ($unExe -and $unExe -match 'unins\d{3}\.exe$')
            $blob = "$($p.DisplayName) $($p.Publisher) $($p.URLInfoAbout) $($p.URLUpdateInfo) $($p.HelpLink) $($p.Comments) $($p.InstallLocation)"
            $tags = @()
            if ($blob -match $fg) { $tags = @('FitGirl') } elseif ($blob -match $dd) { $tags = @('DODI') }
            elseif ($inno) {
                $tags = @('Inno')
                $dat = if ($unExe) { Join-Path (Split-Path $unExe -Parent) ([IO.Path]::GetFileNameWithoutExtension($unExe) + '.dat') } else { $null }
                try {
                    if ($dat -and (Test-Path -LiteralPath $dat) -and (Get-Item -LiteralPath $dat).Length -lt 8MB) {
                        $txt = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($dat)) -replace "`0", ''
                        if ($txt -match $fg) { $tags = @('FitGirl') } elseif ($txt -match $dd) { $tags = @('DODI') }
                    }
                } catch {}
                if ($tags[0] -eq 'Inno' -and $script:cfg["tag:$name"]) { $tags = @('Repack') }
            }
            $of = Find-OF $dir
            if ($of) { $tags += 'OnlineFix' }
            if (-not $tags) { continue }
            $date = $null
            if ("$($p.InstallDate)" -match '^\d{8}$') { $date = [datetime]::ParseExact($p.InstallDate, 'yyyyMMdd', $null).ToString('d MMM yyyy') }
            $seen[$dir.ToLower()] = 1
            $out += New-Game $name $k.PSPath $p.DisplayName $dir $unExe $tags ("$($p.DisplayIcon)" -split ',')[0].Trim('"') $p.DisplayVersion $date
            } catch { continue }
        }
    }
    # folder-based games (OnlineFix releases are usually extracted, not installed)
    $folders = @($script:cfg['folders'])
    foreach ($d in [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' }) { foreach ($n in 'Games', 'Game', 'OnlineFix', 'Downloads') { $folders += ($d.Name + $n) } }
    $folders += (Join-Path $env:USERPROFILE 'Games'), (Join-Path $env:USERPROFILE 'Downloads')
    foreach ($root in $folders | Where-Object { $_ -and ($_ -notmatch '[<>|"*?]') -and (Test-Path -LiteralPath $_) } | Select-Object -Unique) {
        $hits = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { Find-OF $_.FullName } | ForEach-Object { $_.FullName })
        if (-not $hits -and (Find-OF $root)) { $hits = @($root) }
        foreach ($d in $hits) {
            try {
            $dl = $d.ToLower().TrimEnd('\')
            if ($seen[$dl] -or ($seen.Keys | Where-Object { $dl.StartsWith($_.TrimEnd('\') + '\') -or $_.TrimEnd('\').StartsWith($dl + '\') })) { continue }
            $seen[$dl] = 1
            $nm = ((Split-Path $d -Leaf) -replace '(?i)[-_. ]?online-?fix', '' -replace '[_\.]', ' ').Trim()
            $un = Get-ChildItem -LiteralPath $d -Filter 'unins*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
            $out += New-Game "dir:$d" $null $nm $d $un @('OnlineFix') $null $null (Get-Item -LiteralPath $d).CreationTime.ToString('d MMM yyyy')
            } catch { continue }
        }
    }
    $out | Sort-Object Name
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
$app = New-Object Windows.Application
$app.Resources = [Windows.Markup.XamlReader]::Parse(@'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <Style x:Key="Btn" TargetType="Button">
  <Setter Property="Foreground" Value="#F3F3F3"/><Setter Property="Background" Value="#38383C"/><Setter Property="Padding" Value="14,10"/>
  <Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="13.5"/><Setter Property="Margin" Value="0,0,0,8"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
   <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center"/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.82"/></Trigger>
    <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.35"/></Trigger>
   </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style x:Key="Chip" TargetType="RadioButton">
  <Setter Property="Margin" Value="0,0,6,0"/><Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
   <Border x:Name="b" Background="#2B2B2E" CornerRadius="15" Padding="14,6"><TextBlock x:Name="t" Text="{TemplateBinding Content}" FontSize="12.5" Foreground="#DDDDDD"/></Border>
   <ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="#60CDFF"/><Setter TargetName="t" Property="Foreground" Value="#101010"/></Trigger></ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style TargetType="ListBoxItem">
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem">
   <Border x:Name="b" CornerRadius="12" Padding="3" Margin="5" BorderThickness="2" BorderBrush="Transparent" Background="Transparent" RenderTransformOrigin="0.5,0.5"><Border.RenderTransform><ScaleTransform/></Border.RenderTransform><ContentPresenter/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#2E2E32"/>
    <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.045" Duration="0:0:0.14"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.045" Duration="0:0:0.14"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
    <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.18"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.18"/></Storyboard></BeginStoryboard></Trigger.ExitActions></Trigger>
    <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#60CDFF"/></Trigger>
   </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style TargetType="ScrollBar"><Setter Property="Width" Value="10"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
  <Grid Background="Transparent"><Track x:Name="PART_Track" IsDirectionReversed="True"><Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="#5A5A5F" CornerRadius="4" Margin="2"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb></Track></Grid>
 </ControlTemplate></Setter.Value></Setter></Style>
 <Style x:Key="CoverRect" TargetType="Rectangle"><Style.Triggers><DataTrigger Binding="{Binding Cover}" Value="{x:Null}"><Setter Property="Opacity" Value="0"/>
  <DataTrigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.7"/></Storyboard></BeginStoryboard></DataTrigger.ExitActions>
 </DataTrigger></Style.Triggers></Style>
</ResourceDictionary>
'@)
$w = [Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="Repack Shelf" Width="1240" Height="780" MinWidth="980" MinHeight="600" Background="#1B1B1D" Foreground="#F3F3F3"
 WindowStartupLocation="CenterScreen" FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True">
 <Window.Triggers><EventTrigger RoutedEvent="Window.Loaded"><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.45"/></Storyboard></BeginStoryboard></EventTrigger></Window.Triggers>
 <Grid>
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid Margin="24,18,24,8">
   <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="300"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <TextBlock Text="Repack Shelf" FontSize="25" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,24,0"/>
   <Border Grid.Column="1" Background="#2B2B2E" CornerRadius="9" Padding="12,2">
    <Grid><TextBox x:Name="search" Background="Transparent" Foreground="#F3F3F3" CaretBrush="#F3F3F3" BorderThickness="0" FontSize="14" Padding="0,7"/>
     <TextBlock x:Name="ph" Text="Search games" Foreground="#777777" FontSize="14" IsHitTestVisible="False" VerticalAlignment="Center"/></Grid></Border>
   <StackPanel x:Name="chips" Grid.Column="2" Orientation="Horizontal" Margin="18,0,0,0" VerticalAlignment="Center">
    <RadioButton Content="All" Tag="All" IsChecked="True" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="FitGirl" Tag="FitGirl" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="DODI" Tag="DODI" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="OnlineFix" Tag="OnlineFix" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="Other Inno" Tag="Other" Style="{StaticResource Chip}" GroupName="f"/>
    <TextBlock x:Name="count" Foreground="#888888" VerticalAlignment="Center" Margin="10,0,0,0"/>
   </StackPanel>
   <StackPanel Grid.Column="3" Orientation="Horizontal">
    <Button x:Name="btnUpdate" Content="Updates" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
    <Button x:Name="btnFold" Content="Folders" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
    <Button x:Name="btnScan" Content="Rescan" Style="{StaticResource Btn}" Margin="0"/>
   </StackPanel>
  </Grid>
  <Grid Grid.Row="1" Margin="14,4,0,0">
   <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="350"/></Grid.ColumnDefinitions>
   <ListBox x:Name="list" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled" Margin="0,0,6,0">
    <ListBox.ItemsPanel><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></ListBox.ItemsPanel>
    <ListBox.ItemTemplate><DataTemplate>
     <Grid Width="172" Height="258">
      <Rectangle RadiusX="10" RadiusY="10" Fill="{Binding Accent}"/>
      <TextBlock Text="{Binding Letter}" FontSize="76" FontWeight="Bold" Foreground="#33FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-40,0,0"/>
      <Image Source="{Binding Icon}" Width="48" Height="48" Margin="0,60,0,0" Opacity="0.9"/>
      
      <Rectangle RadiusX="10" RadiusY="10" Style="{StaticResource CoverRect}"><Rectangle.Fill><ImageBrush ImageSource="{Binding Cover}" Stretch="UniformToFill"/></Rectangle.Fill></Rectangle>
      <Border VerticalAlignment="Bottom" Height="96" CornerRadius="0,0,10,10"><Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#00000000" Offset="0"/><GradientStop Color="#E8000000" Offset="1"/></LinearGradientBrush></Border.Background>
       <TextBlock Text="{Binding Name}" VerticalAlignment="Bottom" Margin="10,0,10,9" TextWrapping="Wrap" MaxHeight="38" FontSize="13" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/></Border>
      <ItemsControl ItemsSource="{Binding Badges}" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="8"><ItemsControl.ItemTemplate><DataTemplate>
       <Border Background="{Binding Color}" CornerRadius="9" Padding="8,2" Margin="0,0,0,4" HorizontalAlignment="Left"><TextBlock Text="{Binding Text}" FontSize="10.5" FontWeight="SemiBold" Foreground="White"/></Border>
      </DataTemplate></ItemsControl.ItemTemplate></ItemsControl>
     </Grid></DataTemplate></ListBox.ItemTemplate>
   </ListBox>
   <Border Grid.Column="1" Background="#242427" CornerRadius="14,0,0,0" Padding="26,26,26,16">
    <Grid>
     <TextBlock x:Name="empty" Text="Select a game" Foreground="#777777" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
     <ScrollViewer x:Name="detail" Visibility="Collapsed" VerticalScrollBarVisibility="Auto"><StackPanel>
      <Grid Width="200" Height="300" Margin="0,0,0,16">
       <Rectangle RadiusX="12" RadiusY="12" Fill="{Binding Accent}"/><TextBlock Text="{Binding Letter}" FontSize="96" FontWeight="Bold" Foreground="#33FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-50,0,0"/><Image Source="{Binding Icon}" Width="64" Height="64" Margin="0,80,0,0"/>
       <Rectangle RadiusX="12" RadiusY="12" Style="{StaticResource CoverRect}"><Rectangle.Fill><ImageBrush ImageSource="{Binding Cover}" Stretch="UniformToFill"/></Rectangle.Fill></Rectangle>
      </Grid>
      <TextBlock Text="{Binding Name}" FontSize="21" FontWeight="SemiBold" TextWrapping="Wrap" HorizontalAlignment="Center" TextAlignment="Center"/>
      <ItemsControl ItemsSource="{Binding Badges}" HorizontalAlignment="Center" Margin="0,8,0,14"><ItemsControl.ItemsPanel><ItemsPanelTemplate><StackPanel Orientation="Horizontal"/></ItemsPanelTemplate></ItemsControl.ItemsPanel><ItemsControl.ItemTemplate><DataTemplate>
       <Border Background="{Binding Color}" CornerRadius="10" Padding="10,3" Margin="3,0"><TextBlock Text="{Binding Text}" FontSize="11.5" FontWeight="SemiBold" Foreground="White"/></Border>
      </DataTemplate></ItemsControl.ItemTemplate></ItemsControl>
      <TextBlock Text="{Binding Meta}" Foreground="#B4B4B8" FontSize="12.5" LineHeight="22" TextWrapping="Wrap" Margin="0,0,0,18"/>
      <Button x:Name="btnPlay" Content="Play" Style="{StaticResource Btn}" Background="#60CDFF" Foreground="#101010" FontWeight="SemiBold" FontSize="15" Padding="14,12"/>
      <Button x:Name="btnFolder" Content="Open folder" Style="{StaticResource Btn}"/>
      <Button x:Name="btnExe" Content="Set .exe" Style="{StaticResource Btn}"/>
      <Button x:Name="btnFind" Content="Find cover online..." Style="{StaticResource Btn}"/>
      <Button x:Name="btnCover" Content="Set cover image" Style="{StaticResource Btn}"/>
      <Button x:Name="btnMark" Content="Mark as repack" Style="{StaticResource Btn}" Visibility="Collapsed"/>
      <Button x:Name="btnUn" Content="Uninstall completely" Style="{StaticResource Btn}" Background="#C42B1C"/>
     </StackPanel></ScrollViewer>
    </Grid>
   </Border>
  </Grid>
  <Border x:Name="updBar" Grid.RowSpan="3" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,48" Background="#2F2F34" BorderBrush="#60CDFF" BorderThickness="1" CornerRadius="12" Padding="18,12" Visibility="Collapsed">
   <StackPanel Orientation="Horizontal">
    <StackPanel Margin="0,0,20,0" VerticalAlignment="Center"><TextBlock x:Name="updTitle" FontWeight="SemiBold" FontSize="14"/><TextBlock x:Name="updSub" Foreground="#A8A8AD" FontSize="12"/></StackPanel>
    <Button x:Name="btnUpd" Content="Update now" Style="{StaticResource Btn}" Background="#60CDFF" Foreground="#101010" Margin="0,0,8,0" Padding="16,8"/>
    <Button x:Name="btnLater" Content="Later" Style="{StaticResource Btn}" Margin="0" Padding="14,8"/>
   </StackPanel></Border>
  <ProgressBar x:Name="busy" Grid.Row="2" Height="3" VerticalAlignment="Top" IsIndeterminate="True" Background="Transparent" BorderThickness="0" Foreground="#60CDFF" Visibility="Collapsed"/>
  <TextBlock x:Name="status" Grid.Row="2" Foreground="#808085" FontSize="12" Margin="26,6,0,10"/>
 </Grid>
</Window>
'@)
foreach ($n in 'search','ph','chips','count','btnFold','btnScan','list','empty','detail','btnPlay','btnFolder','btnExe','btnCover','btnFind','busy','btnUpdate','updBar','updTitle','updSub','btnUpd','btnLater','btnMark','btnUn','status') { Set-Variable -Name $n -Value $w.FindName($n) -Scope Script }
$w.Title = if ($AppVersion.StartsWith('__')) { 'Repack Shelf (dev build)' } else { "Repack Shelf v$AppVersion" }
$script:filter = 'All'; $script:games = @(); $script:byKey = @{}

function Animate-In {
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
        (($f -eq 'All' -and $t -ne 'Inno') -or ($f -eq 'Other' -and $t -eq 'Inno') -or ($f -notin 'All', 'Other' -and (($t -split ',') -contains $f))) -and (-not $q -or $_.Name -like "*$q*")
    })
    $list.ItemsSource = $v; $count.Text = "$($v.Count) game(s)"; $list.UpdateLayout(); Animate-In
    if ($v.Count -eq 0) { $empty.Text = if ($script:games.Count -eq 0) { "No repack or OnlineFix games found yet.`nUse Folders to add the folder your games live in." } else { 'Nothing matches this filter' } }
    $detail.Visibility = 'Collapsed'; $empty.Visibility = 'Visible'
}
function Scan-And-Show {
    foreach ($p in $script:bg) { try { $p.PS.Stop() } catch {} }; $script:bg = @(); $script:miss = 0; $script:doneMsg = $false
    $w.Cursor = 'Wait'; $status.Text = 'Scanning...'; $w.Dispatcher.Invoke([action]{}, 'Render')
    $script:games = @(Scan); $script:byKey = @{}
    foreach ($g in $script:games) { $script:byKey[$g.Key] = $g }
    $w.Cursor = $null; Refresh-List
    $cj = @(); $sj = @()
    foreach ($g in $script:games) {
        $c = Cache-Path $g.Key; $none = "$c.none"
        $sj += [pscustomobject]@{ Key = $g.Key; Dir = $g.Dir }
        if (-not (Test-Path $c) -and -not ((Test-Path $none) -and ((Get-Item $none).LastWriteTime -gt (Get-Date).AddDays(-1)))) {
            $cj += [pscustomobject]@{ Key = $g.Key; Dir = $g.Dir; Term = (Get-Term $g.Name); Cache = $c } }
    }
    if ($cj) { Start-Bg $coverSb $cj }
    if ($sj) { Start-Bg $sizeSb $sj }
    $status.Text = "Found $($script:games.Count) game(s). $(if ($cj) { 'Fetching cover art in the background...' })"
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
        $tt = New-Object Windows.Media.TranslateTransform 0, 40; $updBar.RenderTransform = $tt
        $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(450)); $ea = New-Object Windows.Media.Animation.CubicEase; $ea.EasingMode = 'EaseOut'
        $a = New-Object Windows.Media.Animation.DoubleAnimation 0, 1, $dur
        $b = New-Object Windows.Media.Animation.DoubleAnimation 40, 0, $dur; $b.EasingFunction = $ea
        $updBar.BeginAnimation([Windows.UIElement]::OpacityProperty, $a); $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $b)
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
$pump = New-Object Windows.Threading.DispatcherTimer; $pump.Interval = [TimeSpan]::FromMilliseconds(400)
$pump.Add_Tick({
    $m = $null
    while ($script:q.TryDequeue([ref]$m)) {
        if ($m.T -eq 'update') { Show-Update $m; continue }
        $g = $script:byKey[$m.K]; if (-not $g) { continue }
        if ($m.T -eq 'cover') { $g.Cover = Load-Img $m.V } elseif ($m.T -eq 'size') { $g.Size = Fmt $m.V } else { $script:miss++ }
    }
    $run = @($script:bg | Where-Object { -not $_.H.IsCompleted }).Count -gt 0
    $busy.Visibility = if ($run) { 'Visible' } else { 'Collapsed' }
    if (-not $run -and $script:bg.Count -gt 0 -and -not $script:doneMsg) {
        $script:doneMsg = $true
        $status.Text = if ($script:miss) { "No cover found for $($script:miss) game(s). Select one and use Find cover online." } else { 'All covers loaded.' }
    }
})
$pump.Start()

$list.Add_SelectionChanged({
    $g = $list.SelectedItem
    if (-not $g) { return }
    $detail.DataContext = $g; $empty.Visibility = 'Collapsed'; $detail.Visibility = 'Visible'
    $btnPlay.IsEnabled = [bool]$g.Exe
    $btnMark.Visibility = if (($g.Tags -match 'Inno') -and ($g.Tags -notmatch 'FitGirl|DODI|Repack')) { 'Visible' } else { 'Collapsed' }
    $btnUn.Content = if ($g.UnExe -or $g.KeyPath) { 'Uninstall completely' } else { 'Delete game folder' }
    $tt = New-Object Windows.Media.TranslateTransform 28, 0; $detail.RenderTransform = $tt
    $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(320)); $ea = New-Object Windows.Media.Animation.CubicEase; $ea.EasingMode = 'EaseOut'
    $a = New-Object Windows.Media.Animation.DoubleAnimation 0, 1, $dur
    $b = New-Object Windows.Media.Animation.DoubleAnimation 28, 0, $dur; $b.EasingFunction = $ea
    $detail.BeginAnimation([Windows.UIElement]::OpacityProperty, $a); $tt.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $b)
})
$list.Add_MouseDoubleClick({ Play })
$search.Add_TextChanged({ $ph.Visibility = if ($search.Text) { 'Collapsed' } else { 'Visible' }; Refresh-List })
foreach ($rb in $chips.Children) { if ($rb -is [Windows.Controls.RadioButton]) { $rb.Add_Checked({ $script:filter = $args[0].Tag; Refresh-List }) } }
$btnScan.Add_Click({ Scan-And-Show })
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
$btnMark.Add_Click({ $script:cfg["tag:$($list.SelectedItem.Key)"] = 'Repack'; Save-Cfg; Scan-And-Show })
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
        $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(2); $t0 = Get-Date
        $t.Add_Tick({
            $done = if ($i.KeyPath) { -not (Test-Path -LiteralPath $i.KeyPath) } else { -not (Test-Path -LiteralPath $i.UnExe) }
            if ($done) { $t.Stop(); Finish-Remove $i $false }
            elseif (((Get-Date) - $t0).TotalMinutes -gt 30) { $t.Stop(); $status.Text = 'Uninstall did not complete.' }
        }.GetNewClosure())
        $t.Start()
    } elseif (Ask "$($i.Name) has no uninstaller.`n`nPermanently delete its folder ($(Fmt (Get-DirSize $i.Dir)))?`n$($i.Dir)") { Finish-Remove $i $true }
})

$w.Add_SourceInitialized({
    $h = (New-Object Windows.Interop.WindowInteropHelper $w).Handle
    $v = 1; [void][Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)
    $c = 0x1D1B1B; [void][Dwm]::DwmSetWindowAttribute($h, 35, [ref]$c, 4)
})
$w.Add_ContentRendered({ if (-not $script:started) { $script:started = $true; Scan-And-Show; Check-Update $false } })
[void]$w.ShowDialog()
