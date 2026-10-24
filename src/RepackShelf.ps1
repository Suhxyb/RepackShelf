$AppVersion = '__VERSION__'; $RepoSlug = '__REPO__'

# Optional: put your code-signing certificate thumbprint here to make updates require a valid signature from you.
$script:UpdateSignerThumbprint = ''

# ---------- single instance ----------
# A named mutex is per-user ("Local\") and is released automatically when the process exits,
# including after a crash, so a stale lock can't block the next launch.
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\RepackShelf.SingleInstance')
$script:ownsMutex = $false
try { $script:ownsMutex = $script:mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $script:ownsMutex = $true }
if (-not $script:ownsMutex) {
    # Already running: bring the existing window to the front instead of opening a second one.
    Add-Type @"
using System; using System.Runtime.InteropServices;
public static class RsFocus {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
    $h = [RsFocus]::FindWindow($null, 'Repack Shelf')
    if ($h -ne [IntPtr]::Zero) {
        if ([RsFocus]::IsIconic($h)) { [void][RsFocus]::ShowWindow($h, 9) }
        [void][RsFocus]::SetForegroundWindow($h)
    }
    exit
}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Drawing,System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Dwm { [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s); }
"@
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Media; using System.Collections.Generic;
using System.ComponentModel;
public class RsBadge { public string Text {get;set;} public string Color {get;set;} }
public class RsGame : INotifyPropertyChanged {
  public event PropertyChangedEventHandler PropertyChanged;
  void N(string p) { var h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(p)); }
  public string Key {get;set;} public string KeyPath {get;set;} public string Name {get;set;} public string Dir {get;set;}
  public string UnExe {get;set;} public string Exe {get;set;} public string Version {get;set;} public string Date {get;set;} public string Tags {get;set;}
  public object Badges {get;set;} public object Icon {get;set;} public string Accent {get;set;} public string Letter {get;set;} public string IconSrc {get;set;}
  object cover; public object Cover { get { return cover; } set { cover = value; N("Cover"); } }
  string size; public string Size { get { return size; } set { size = value; N("Meta"); N("SizeText"); } } public string SizeText { get { return size ?? "..."; } } public long Bytes {get;set;} public long DateTicks {get;set;}
  string gen; public string Genres { get { return gen; } set { gen = value; N("Genres"); N("Meta"); } }
  public long NewsDate {get;set;} public string NewsTitle {get;set;} public string NewsUrl {get;set;}
  string upd; public string UpdText { get { return upd; } set { upd = value; N("UpdText"); N("Meta"); } }
  bool hasUpd; public bool HasUpd { get { return hasUpd; } set { hasUpd = value; N("HasUpd"); } }
  bool fav; public bool Fav { get { return fav; } set { fav = value; N("Fav"); N("FavMark"); } } public string FavMark { get { return fav ? "\u2605" : ""; } }
  public string TagLine { get { return (Tags ?? "").Replace(",", "  \u00B7  "); } }
  public string Meta { get { return "Folder   " + Dir + "\nSize   " + (Size ?? "calculating...") + "\nVersion   " + (Version ?? "n/a") + "\nInstalled   " + (Date ?? "n/a") + "\nLaunches   " + (Exe ?? "no executable found - use Set .exe") + (string.IsNullOrEmpty(gen) ? "" : "\nGenres   " + gen.Replace(",", ", ")) + (string.IsNullOrEmpty(upd) ? "" : "\nNew patch notes   " + upd); } }
}

// ---- Halloween sound effects: synthesised in memory (no sound files needed) ----
public static class RsSfx {
  const int SR = 22050;
  static Dictionary<string, SoundPlayer> P = new Dictionary<string, SoundPlayer>();
  static Dictionary<string, double> Len = new Dictionary<string, double>();
  static Dictionary<string, int> Pri = new Dictionary<string, int>();
  static Random R = new Random(1031);
  static DateTime busyUntil = DateTime.MinValue; static int busyPri = 0; static DateTime lastHover = DateTime.MinValue;
  static bool ready;
  public static double Master = 0.1;
  static double[] Buf(double sec) { return new double[(int)(sec * SR)]; }
  static void Noise(double[] b, double at, double len, double lp, double gain, double decay, double modHz, double modDepth) {
    int s = (int)(at * SR), n = (int)(len * SR); double y = 0, norm = Math.Sqrt((2.0 - lp) / lp) * 0.58;
    for (int i = 0; i < n && s + i < b.Length; i++) {
      double t = (double)i / SR; y += lp * ((R.NextDouble() * 2 - 1) - y);
      double roll = 1.0 + modDepth * Math.Sin(2 * Math.PI * modHz * t);
      b[s + i] += y * norm * gain * roll * Math.Exp(-t * decay) * Math.Min(1.0, t / 0.015);
    }
  }
  static void Bell(double[] b, double at, double f, double len, double gain, double decay) {
    int s = (int)(at * SR), n = (int)(len * SR);
    for (int i = 0; i < n && s + i < b.Length; i++) {
      double t = (double)i / SR;
      double v = Math.Sin(2 * Math.PI * f * t) + 0.45 * Math.Sin(2 * Math.PI * f * 2.76 * t) * Math.Exp(-t * 2.0) + 0.25 * Math.Sin(2 * Math.PI * f * 5.4 * t) * Math.Exp(-t * 5.0);
      b[s + i] += v * gain * Math.Exp(-t * decay) * Math.Min(1.0, t / 0.002);
    }
  }
  static void Sweep(double[] b, double at, double len, double f0, double f1, double vibHz, double vibDepth, double gain) {
    int s = (int)(at * SR), n = (int)(len * SR); double ph = 0;
    for (int i = 0; i < n && s + i < b.Length; i++) {
      double t = (double)i / SR, u = t / len;
      double f = f0 + (f1 - f0) * u + vibDepth * Math.Sin(2 * Math.PI * vibHz * t);
      ph += 2 * Math.PI * f / SR;
      double env = Math.Pow(Math.Sin(Math.PI * u), 1.5);
      b[s + i] += (Math.Sin(ph) + 0.35 * Math.Sin(2 * ph) + 0.15 * Math.Sin(3 * ph)) * env * gain;
    }
  }
  static void Creak(double[] b, double at, double len, double f0, double f1, double gain) {
    int s = (int)(at * SR), n = (int)(len * SR); double ph = 0, y = 0;
    for (int i = 0; i < n && s + i < b.Length; i++) {
      double t = (double)i / SR, u = t / len;
      double f = f0 + (f1 - f0) * u + 35 * Math.Sin(2 * Math.PI * 7 * t) + 30 * (R.NextDouble() - 0.5);
      ph += f / SR; double saw = 2 * (ph - Math.Floor(ph)) - 1;
      double am = 0.55 + 0.45 * Math.Sin(2 * Math.PI * 26 * t);
      y += 0.18 * (saw - y);
      b[s + i] += y * am * Math.Sin(Math.PI * u) * gain;
    }
  }
  static void Tick(double[] b, double at, double f, double len, double gain) {
    int s = (int)(at * SR), n = (int)(len * SR);
    for (int i = 0; i < n && s + i < b.Length; i++) { double t = (double)i / SR; b[s + i] += Math.Sin(2 * Math.PI * f * t) * Math.Exp(-t * 55) * gain; }
  }
  static byte[] Wav(double[] b, double peak) {
    double m = 0; for (int i = 0; i < b.Length; i++) m = Math.Max(m, Math.Abs(b[i]));
    double k = m > 0 ? peak / m : 1; int n = b.Length;
    MemoryStream ms = new MemoryStream(44 + n * 2); BinaryWriter w = new BinaryWriter(ms);
    w.Write(new char[] { 'R', 'I', 'F', 'F' }); w.Write(36 + n * 2); w.Write(new char[] { 'W', 'A', 'V', 'E' });
    w.Write(new char[] { 'f', 'm', 't', ' ' }); w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(SR); w.Write(SR * 2); w.Write((short)2); w.Write((short)16);
    w.Write(new char[] { 'd', 'a', 't', 'a' }); w.Write(n * 2);
    for (int i = 0; i < n; i++) { double fade = Math.Min(1.0, Math.Min(i / 40.0, (n - i) / 220.0)); w.Write((short)(b[i] * k * fade * 32000 * Master)); }
    w.Flush(); return ms.ToArray();
  }
  static void Add(string name, double[] b, double peak, int pri) {
    SoundPlayer p = new SoundPlayer(new MemoryStream(Wav(b, peak))); p.Load();
    P[name] = p; Len[name] = b.Length / (double)SR; Pri[name] = pri;
  }
  public static void Init() {
    if (ready) return; ready = true; double[] b;
    b = Buf(2.6); Noise(b, 0, 2.3, 0.03, 0.9, 1.5, 2.6, 0.5); Sweep(b, 0.5, 1.7, 220, 196, 5.5, 6, 0.12); Bell(b, 1.0, 440.0, 1.6, 0.35, 2.2); Bell(b, 1.35, 311.1, 1.25, 0.3, 2.4); Add("boot", b, 0.75, 2);
    b = Buf(0.07); Tick(b, 0, 330, 0.07, 1.0); Tick(b, 0, 495, 0.07, 0.4); Add("hover", b, 0.25, 0);
    b = Buf(0.6); Bell(b, 0, 329.6, 0.6, 0.5, 6.0); Bell(b, 0, 349.2, 0.6, 0.35, 6.5); Add("select", b, 0.4, 1);
    b = Buf(0.85); Bell(b, 0, 1318.5, 0.6, 0.4, 7.0); Bell(b, 0.07, 1568.0, 0.6, 0.4, 7.0); Bell(b, 0.14, 1975.5, 0.6, 0.35, 7.0); Bell(b, 0.21, 2637.0, 0.6, 0.3, 7.0); Add("fav", b, 0.35, 1);
    b = Buf(1.8); Sweep(b, 0, 1.4, 110, 260, 5.0, 5, 0.5); Bell(b, 0.35, 82.4, 1.4, 0.9, 2.2); Bell(b, 0.35, 116.5, 1.2, 0.4, 2.6); Add("launch", b, 0.8, 2);
    b = Buf(0.8); Creak(b, 0, 0.45, 160, 380, 0.6); Creak(b, 0.42, 0.3, 300, 200, 0.4); Add("creak", b, 0.35, 1);
    b = Buf(1.9); Noise(b, 0, 1.9, 0.025, 1.0, 1.7, 3.1, 0.6); Noise(b, 0, 0.25, 0.3, 0.4, 10, 0, 0); Add("thunder", b, 0.85, 2);
    b = Buf(0.4); Noise(b, 0, 0.4, 0.35, 0.6, 5.0, 20, 0.9); Add("bat", b, 0.25, 0);
    b = Buf(0.5); Sweep(b, 0, 0.45, 1100, 330, 14, 40, 0.4); Add("spider", b, 0.22, 0);
    b = Buf(1.4); Sweep(b, 0, 1.3, 300, 240, 5.5, 10, 0.5); Sweep(b, 0, 1.3, 452, 360, 5.5, 12, 0.2); Add("ghost", b, 0.5, 2);
  }
  public static void Play(string name) {
    SoundPlayer p; if (!P.TryGetValue(name, out p)) return;
    DateTime now = DateTime.UtcNow; int pr = Pri[name];
    if (name == "hover") { if ((now - lastHover).TotalMilliseconds < 80) return; lastHover = now; }
    if (now < busyUntil && pr < busyPri) return;
    p.Play(); busyUntil = now.AddSeconds(Len[name] * 0.9); busyPri = pr;
  }
}
'@

# ---------- config ----------
$appDir = Join-Path $env:APPDATA 'RepackShelf'; $coverDir = Join-Path $appDir 'covers'
New-Item -ItemType Directory -Force $coverDir | Out-Null
$logDir = Join-Path $appDir 'logs'
function Write-Log($msg) {
    try {
        New-Item -ItemType Directory -Force $logDir | Out-Null
        $lf = Join-Path $logDir 'repackshelf.log'
        if ((Test-Path -LiteralPath $lf) -and (Get-Item -LiteralPath $lf).Length -gt 512KB) { Move-Item -LiteralPath $lf -Destination "$lf.old" -Force }
        Add-Content -LiteralPath $lf -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $msg) -Encoding UTF8
    } catch {}
}
# Writes to a temp file first, then swaps it in, so a crash mid-save can't leave a half-written file.
function Write-Atomic($path, $text) { $tmp = "$path.tmp"; Set-Content -LiteralPath $tmp -Value $text -Encoding UTF8; Move-Item -LiteralPath $tmp -Destination $path -Force }
$cfgPath = Join-Path $appDir 'config.json'
$script:cfg = @{}
if (Test-Path $cfgPath) { try { (Get-Content $cfgPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:cfg[$_.Name] = $_.Value } } catch { Write-Log "Could not read config.json: $($_.Exception.Message)" } }
function Save-Cfg { try { Write-Atomic $cfgPath ($script:cfg | ConvertTo-Json) } catch { Write-Log "Save-Cfg failed: $($_.Exception.Message)" } }
$libPath = Join-Path $appDir 'library.json'
$script:ofCache = @{}; $script:datCache = @{}; $script:exeCache = @{}; $script:fullScan = $false; $script:scanning = $false; $script:sort = 'Name'; $script:favOnly = $false; $script:updOnly = $false; $script:updDirty = $false; $script:cfgDirty = $false; $script:genres = @(); $script:genDirty = $false; $script:view = 'Grid'; $script:animK = 1.0

# ---------- helpers ----------
function Fmt($b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }
function Ask($t) { [Windows.MessageBox]::Show($t, 'Repack Shelf', 'YesNo', 'Warning') -eq 'Yes' }
function Tell($t) { [void][Windows.MessageBox]::Show($t, 'Repack Shelf', 'OK', 'Information') }
# ---------- safety helpers ----------
# Only local, fixed-drive paths are trusted (no UNC / network paths, which can leak credentials when touched).
function Test-LocalPath($p) {
    if (-not $p -or "$p" -notmatch '^[A-Za-z]:\\') { return $false }
    if (-not $script:fixedDrives) { $script:fixedDrives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' } | ForEach-Object { "$($_.Name)".Substring(0, 1).ToUpper() }) }
    $script:fixedDrives -contains "$p".Substring(0, 1).ToUpper()
}
function Test-LocalExe($p) { (Test-LocalPath $p) -and ("$p" -match '(?i)\.exe$') -and (Test-Path -LiteralPath $p -PathType Leaf) }
# Folders that must never be deleted by the app: system and personal folders, library roots and the app's own folders.
function Get-ProtectedPaths {
    $list = @($env:USERPROFILE, $env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, $env:PUBLIC,
              [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'),
              (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Games'), $appDir)
    try { $list += (Split-Path ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)) } catch {}
    foreach ($d in [IO.DriveInfo]::GetDrives()) { foreach ($n in 'Games', 'Game', 'OnlineFix', 'Downloads', 'Users', 'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData') { $list += ($d.Name + $n) } }
    $list += @($script:cfg['folders'])
    @($list | Where-Object { $_ } | ForEach-Object { "$_".TrimEnd('\') })
}
# A target is refused if it is a drive root, a UNC path, inside Windows, one of the protected folders, or a parent of one.
function Test-SafeDeleteTarget($dir) {
    try { $p = [IO.Path]::GetFullPath("$dir").TrimEnd('\') } catch { return $false }
    if ($p.Length -le 2 -or $p.StartsWith('\\')) { return $false }
    $win = "$env:WINDIR".TrimEnd('\')
    if ($win -and ($p -ieq $win -or $p.StartsWith("$win\", [StringComparison]::OrdinalIgnoreCase))) { return $false }
    foreach ($b in (Get-ProtectedPaths)) {
        if ($p -ieq $b -or $b.StartsWith("$p\", [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    $true
}
# Deletes a game folder without following junctions/symlinks (they are unlinked, never entered) and clears read-only flags first.
function Remove-GameDir($dir) {
    if (-not (Test-SafeDeleteTarget $dir)) { throw "Refusing to delete this folder: $dir" }
    $stack = New-Object 'System.Collections.Generic.Stack[string]'; $stack.Push($dir)
    while ($stack.Count) {
        $cur = $stack.Pop()
        try {
            foreach ($f in [IO.Directory]::EnumerateFiles($cur)) { try { [IO.File]::SetAttributes($f, [IO.FileAttributes]::Normal) } catch {} }
            foreach ($x in [IO.Directory]::EnumerateDirectories($cur)) { if (([IO.File]::GetAttributes($x) -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push($x) } }
        } catch {}
    }
    [IO.Directory]::Delete($dir, $true)
}
function Test-UninstallKey($kp) { "$kp" -match '^Registry::HKEY_(LOCAL_MACHINE|CURRENT_USER)\\SOFTWARE\\(WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Uninstall\\[^\\]+$' }
# Genuine Inno Setup uninstallers contain the text "Inno Setup"; anything else gets a warning before it is run.
function Test-InnoUninstaller($path) {
    try {
        $fi = Get-Item -LiteralPath $path -ErrorAction Stop
        if ($fi.Length -gt 12MB) { return $false }
        [bool]([Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($fi.FullName)) -match 'Inno Setup')
    } catch { $false }
}
# Links are only opened over HTTPS on trusted hosts; anything else falls back to a safe page or is refused.
$script:SafeHosts = @('steampowered.com', 'steamcommunity.com', 'github.com')
function Test-SafeUrl($url) {
    try { $u = [Uri]"$url" } catch { return $false }
    if (-not $u.IsAbsoluteUri -or $u.Scheme -ne 'https') { return $false }
    foreach ($h in $script:SafeHosts) { if ($u.Host -eq $h -or $u.Host.EndsWith(".$h")) { return $true } }
    $false
}
function Open-SafeUrl($url, $fallback = $null) {
    if (Test-SafeUrl $url) { Start-Process "$url"; return }
    if ($fallback -and (Test-SafeUrl $fallback)) { Start-Process "$fallback"; return }
    Tell 'That link is not on a trusted host, so it was not opened.'
}
# Downloads with a size cap and timeouts, HTTPS only, and checks the final host after redirects.
function Save-Capped($url, $dest, $max, $hostOk) {
    if ("$url" -notlike 'https://*') { throw 'Only HTTPS downloads are allowed.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $req = [Net.HttpWebRequest][Net.WebRequest]::Create($url)
    $req.UserAgent = 'RepackShelf'; $req.Timeout = 30000; $req.ReadWriteTimeout = 30000; $req.MaximumAutomaticRedirections = 5
    $resp = $req.GetResponse()
    try {
        $rh = $resp.ResponseUri.Host.ToLower(); $ok = $false
        foreach ($h in $hostOk) { if ($rh -eq $h -or $rh.EndsWith(".$h")) { $ok = $true } }
        if ($resp.ResponseUri.Scheme -ne 'https' -or -not $ok) { throw "The download was redirected to an unexpected host ($rh)." }
        if ($resp.ContentLength -gt $max) { throw 'The download is larger than expected.' }
        $in = $resp.GetResponseStream(); $out = [IO.File]::Create($dest); $n = 0L; $buf = New-Object byte[] 81920
        try {
            while (($r = $in.Read($buf, 0, $buf.Length)) -gt 0) { $n += $r; if ($n -gt $max) { throw 'The download is larger than expected.' }; $out.Write($buf, 0, $r) }
        } finally { $out.Dispose(); $in.Dispose() }
    } finally { $resp.Close() }
}
# Directory walkers that never enter junctions or symlinks.
function Get-FilesBounded($dir, $pattern, $depth) {
    try {
        foreach ($f in [IO.Directory]::EnumerateFiles($dir, $pattern)) { [IO.FileInfo]$f }
        if ($depth -gt 0) { foreach ($d in [IO.Directory]::EnumerateDirectories($dir)) { if (([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint) -eq 0) { Get-FilesBounded $d $pattern ($depth - 1) } } }
    } catch {}
}
function Get-DirSize($d) {
    $s = 0L; $stack = New-Object 'System.Collections.Generic.Stack[string]'; $stack.Push($d)
    while ($stack.Count) {
        $cur = $stack.Pop()
        try {
            foreach ($f in [IO.Directory]::EnumerateFiles($cur)) { try { $s += ([IO.FileInfo]$f).Length } catch {} }
            foreach ($x in [IO.Directory]::EnumerateDirectories($cur)) { if (([IO.File]::GetAttributes($x) -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push($x) } }
        } catch {}
    }
    $s
}
function Cache-Path($key) { Join-Path $coverDir (([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($key))) -replace '-') + '.jpg') }
function Find-OF($dir, $depth = 3) {
    try {
        if ([IO.Directory]::EnumerateFiles($dir, 'OnlineFix*').GetEnumerator().MoveNext()) { return $true }
        if ($depth -gt 0) { foreach ($d in [IO.Directory]::EnumerateDirectories($dir)) { if (([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and (Find-OF $d ($depth - 1))) { return $true } } }
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
        $recs = @($script:games | ForEach-Object { [pscustomobject]@{ Key = $_.Key; KeyPath = $_.KeyPath; Name = $_.Name; Dir = $_.Dir; UnExe = $_.UnExe; Tags = $_.Tags; Exe = $_.Exe; IconSrc = $_.IconSrc; Version = $_.Version; Date = $_.Date; Size = $_.Size; Bytes = $_.Bytes; DateTicks = $_.DateTicks } })
        $json = [pscustomobject]@{ v = 1; games = $recs; of = $script:ofCache; dat = $script:datCache } | ConvertTo-Json -Depth 4
        Write-Atomic $libPath $json
    } catch { Write-Log "Save-Library failed: $($_.Exception.Message)" }
}
function Load-Library {
    if (-not (Test-Path $libPath)) { return }
    try {
        $d = Get-Content $libPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($d.of) { foreach ($p in $d.of.PSObject.Properties) { $script:ofCache[$p.Name] = @{ T = "$($p.Value.T)"; V = [bool]$p.Value.V } } }
        if ($d.dat) { foreach ($p in $d.dat.PSObject.Properties) { $script:datCache[$p.Name] = @{ L = "$($p.Value.L)"; V = "$($p.Value.V)" } } }
        $games = @()
        foreach ($r in @($d.games)) {
            if (-not $r.Dir -or -not (Test-LocalPath $r.Dir) -or -not (Test-Path -LiteralPath $r.Dir) -or "$($r.Tags)" -eq 'Inno') { continue }
            # cached values are re-validated, never trusted blindly
            $kp = if (Test-UninstallKey $r.KeyPath) { $r.KeyPath } else { $null }
            $ue = if ($r.UnExe -and (Test-LocalPath $r.UnExe)) { $r.UnExe } else { $null }
            $ic = if ($r.IconSrc -and (Test-LocalPath $r.IconSrc)) { $r.IconSrc } else { $null }
            $script:exeCache[$r.Key] = $(if ($r.Exe -and (Test-LocalExe $r.Exe)) { $r.Exe } else { $null })
            $rec = [pscustomobject]@{ Key = $r.Key; KeyPath = $kp; Name = $r.Name; Dir = $r.Dir; UnExe = $ue; Tags = @("$($r.Tags)" -split ','); IconSrc = $ic; Version = $r.Version; Date = $r.Date; DateTicks = $r.DateTicks }
            $g = New-Game $rec
            if ($r.Size) { $g.Size = $r.Size }; $g.Bytes = [long]$r.Bytes
            $games += $g
        }
        $script:games = $games; $script:byKey = @{}
        foreach ($g in $games) { $script:byKey[$g.Key] = $g }
    } catch { Write-Log "Load-Library failed: $($_.Exception.Message)" }
}
function Get-Term($n) {
    $n = $n -replace '\[[^\]]*\]|\([^\)]*\)', ' ' -replace '[\u2122\u00AE\u00A9]', ' ' -replace '(?i)[-_. ]?online-?fix', ' ' -replace '(?i)\b(v|ver|version|build)[\s\.]?\d[\w\.]*.*$', ' ' -replace '(?i)\b(repack|fitgirl|dodi|goty|deluxe|ultimate|complete|definitive)\s*(edition)?\b', ' ' -replace '[_\.]', ' ' -replace '\s+', ' '
    $n.Trim(' ', '-')
}
function Get-Exe($dir) { try { Get-Exe2 $dir } catch { $null } }
function Get-Exe2($dir) {
    $bad = '^(unins|UnityCrash|UE4Prereq|vc_?redist|dxsetup|dotnet|CrashReport|oalinst|installer|setup)|redist|crashpad'
    Get-FilesBounded $dir '*.exe' 2 |
        Where-Object { $_.Extension -ieq '.exe' -and $_.Name -notmatch $bad -and $_.DirectoryName -notmatch 'CommonRedist|Redist|Support' } |
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
# Compares Steam's newest developer patch-note post with the date the game was installed.
# It cannot read the installed build, so this is a hint; "Dismiss update notice" clears it.
function Set-UpdState($g) {
    $g.HasUpd = $false; $g.UpdText = ''
    if ($g.NewsDate -le 0 -or $g.DateTicks -le 0) { return }
    $sk = "seen:$($g.Key)"; $seen = [long]("0" + [string]$script:cfg[$sk])
    $pd = [DateTimeOffset]::FromUnixTimeSeconds($g.NewsDate).LocalDateTime
    if ($g.NewsDate -gt $seen -and $pd.Ticks -gt ($g.DateTicks + [TimeSpan]::FromDays(1).Ticks)) {
        $g.HasUpd = $true; $g.UpdText = "$($pd.ToString('d MMM yyyy')) - $($g.NewsTitle)"
    }
}
function New-Game($r) {
    $tags = @($r.Tags)
    $g = New-Object RsGame
    $g.Key = $r.Key; $g.KeyPath = $r.KeyPath; $g.Name = $r.Name; $g.Dir = $r.Dir; $g.UnExe = $r.UnExe; $g.Version = $r.Version; $g.Date = $r.Date; $g.Tags = ($tags -join ',')
    $exe = $script:cfg["exe:$($r.Key)"]
    if (-not $exe -or -not (Test-LocalExe $exe)) { $exe = $script:exeCache[$r.Key] }
    if (-not $exe -or -not (Test-LocalExe $exe)) { $exe = Get-Exe $r.Dir }
    $script:exeCache[$r.Key] = $exe; $g.Exe = $exe
    $ico = $r.IconSrc
    if (-not $ico -or $ico -match '[<>|"*?]' -or -not (Test-LocalPath $ico) -or -not (Test-Path -LiteralPath $ico) -or $ico -match 'unins') { $ico = $exe }
    $g.IconSrc = $ico
    $g.DateTicks = [long]$r.DateTicks; $gk = "gen:$($r.Key)"; $gv = "$($script:cfg[$gk])"; if ($gv -and $gv -ne '-') { $g.Genres = $gv }; $nk = $r.Key; $g.NewsDate = [long]("0" + [string]$script:cfg["nd:$nk"]); $g.NewsTitle = [string]$script:cfg["nt:$nk"]; $g.NewsUrl = [string]$script:cfg["nu:$nk"]; Set-UpdState $g; $g.Fav = [bool]$script:cfg["fav:$($r.Key)"]
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
    $script:fixedDrives = $null
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
    $roots = @($folders | Where-Object { $_ -and ($_ -notmatch '[<>|"*?]') -and (Test-LocalPath $_) -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
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
            if ($unExe -and -not (Test-LocalPath $unExe)) { $unExe = $null }
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
            if (-not $dir -or $dir -match '[<>|"*?]' -or -not (Test-LocalPath $dir) -or -not (Test-Path -LiteralPath $dir) -or $seen[$dir.ToLower()]) { continue }
            if (Find-OFCached $dir) { $tags += 'OnlineFix' }
            $dt = $null
            if ($p.InstallDate -match '^\d{8}$') { try { $dt = [datetime]::ParseExact($p.InstallDate, 'yyyyMMdd', $null) } catch {} }
            if (-not $dt) { try { $dt = (Get-Item -LiteralPath $dir).CreationTime } catch {} }
            $date = if ($dt) { $dt.ToString('d MMM yyyy') } else { $null }; $dticks = if ($dt) { $dt.Ticks } else { 0 }
            $icoSrc = ($p.DisplayIcon -split ',')[0].Trim('"'); if (-not (Test-LocalPath $icoSrc)) { $icoSrc = $null }
            $seen[$dir.ToLower()] = 1
            $out += [pscustomobject]@{ Key = $name; KeyPath = "Registry::$($e.HiveName)\$($e.Sub)\$name"; Name = $p.DisplayName; Dir = $dir; UnExe = $unExe; Tags = $tags; IconSrc = $icoSrc; Version = $p.DisplayVersion; Date = $date; DateTicks = $dticks }
        } catch { continue }
    }

    # folder-based games (OnlineFix releases are usually extracted, not installed)
    foreach ($r in $roots) {
        $hits = @()
        foreach ($c in $kids[$r]) {
            $i++; if ($i % 6 -eq 0) { Step $i $total "Scanning game folders ($i of $total)..." }
            if (Find-OFCached $c) { $hits += $c }
        }
        foreach ($d in $hits) {
            try {
                $dl = $d.ToLower().TrimEnd('\')
                if ($seen[$dl] -or ($seen.Keys | Where-Object { $dl.StartsWith($_.TrimEnd('\') + '\') -or $_.TrimEnd('\').StartsWith($dl + '\') })) { continue }
                $seen[$dl] = 1
                $nm = ((Split-Path $d -Leaf) -replace '(?i)[-_. ]?online-?fix', '' -replace '[_\.]', ' ').Trim()
                $cd = (Get-Item -LiteralPath $d).CreationTime
                $un = Get-ChildItem -LiteralPath $d -Filter 'unins*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
                $out += [pscustomobject]@{ Key = "dir:$d"; KeyPath = $null; Name = $nm; Dir = $d; UnExe = $un; Tags = @('OnlineFix'); IconSrc = $null; Version = $null; Date = $cd.ToString('d MMM yyyy'); DateTicks = $cd.Ticks }
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
        if ($o -and $o.Dir -eq $r.Dir -and $o.Name -eq $r.Name -and $o.Tags -eq (@($r.Tags) -join ',')) { $o.DateTicks = [long]$r.DateTicks; $o } else { New-Game $r }
    }
}

# ---------- background workers (cover art + sizes) ----------
$coverSb = {
    param($jobs, $q)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $norm = { param($s) ($s -replace '[^a-zA-Z0-9]', '').ToLower() }
    $junk = '(?i)soundtrack|\bost\b|\bdlc\b|\bdemo\b|bundle|artbook|season pass|playtest|dedicated server|\bbeta\b'
    $get = {
        param($url, $out)
        try {
            $u = [Uri]"$url"
            $hostOk = ($u.Scheme -eq 'https') -and ($u.Host -like '*.steamstatic.com' -or $u.Host -like '*.akamaihd.net' -or $u.Host -like '*.steampowered.com')
            if (-not $hostOk) { return $false }
            $req = [Net.HttpWebRequest][Net.WebRequest]::Create($u); $req.Timeout = 20000; $req.ReadWriteTimeout = 20000; $req.UserAgent = 'RepackShelf'
            $resp = $req.GetResponse()
            try {
                if ($resp.ResponseUri.Scheme -ne 'https' -or $resp.ContentLength -gt 6MB) { return $false }
                $in = $resp.GetResponseStream(); $fs = [IO.File]::Create($out); $n = 0L; $buf = New-Object byte[] 65536
                try { while (($r = $in.Read($buf, 0, $buf.Length)) -gt 0) { $n += $r; if ($n -gt 6MB) { break }; $fs.Write($buf, 0, $r) } } finally { $fs.Dispose(); $in.Dispose() }
            } finally { $resp.Close() }
            $b = [IO.File]::ReadAllBytes($out)
            $img = ($b.Length -gt 2000 -and $b.Length -le 6MB) -and (($b[0] -eq 0xFF -and $b[1] -eq 0xD8) -or ($b[0] -eq 0x89 -and $b[1] -eq 0x50))
            if ($img) { $true } else { Remove-Item $out -ErrorAction SilentlyContinue; $false }
        } catch { Remove-Item $out -ErrorAction SilentlyContinue; $false }
    }
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
    $gmap = @{
        'horror'='Horror'; 'survival horror'='Horror'; 'psychological horror'='Horror'; 'action'='Action'; 'adventure'='Adventure'; 'rpg'='RPG'; 'action rpg'='RPG'; 'jrpg'='RPG'
        'strategy'='Strategy'; 'rts'='Strategy'; 'simulation'='Simulation'; 'sports'='Sports'; 'racing'='Racing'; 'driving'='Racing'; 'puzzle'='Puzzle'
        'platformer'='Platformer'; '2d platformer'='Platformer'; '3d platformer'='Platformer'; 'shooter'='Shooter'; 'fps'='Shooter'; 'third-person shooter'='Shooter'; 'first-person shooter'='Shooter'
        'survival'='Survival'; 'open world'='Open World'; 'sandbox'='Sandbox'; 'roguelike'='Roguelike'; 'roguelite'='Roguelike'; 'rogue-like'='Roguelike'; 'rogue-lite'='Roguelike'
        'fighting'='Fighting'; 'stealth'='Stealth'; 'story rich'='Story Rich'; 'casual'='Casual'; 'souls-like'='Soulslike'; 'soulslike'='Soulslike'; 'metroidvania'='Metroidvania'
        'turn-based'='Turn-Based'; 'turn-based strategy'='Turn-Based'; 'turn-based combat'='Turn-Based'; 'tower defense'='Tower Defense'; 'city builder'='Building'; 'base building'='Building'; 'building'='Building'
        'sci-fi'='Sci-fi'; 'fantasy'='Fantasy'; 'cyberpunk'='Cyberpunk'; 'zombies'='Zombies'; 'anime'='Anime'; 'visual novel'='Visual Novel'; 'hack and slash'='Hack and Slash'; 'walking simulator'='Walking Sim'
        'co-op'='Co-op'; 'online co-op'='Co-op'; 'local co-op'='Co-op'; 'co-op campaign'='Co-op'; 'lan co-op'='Co-op'; 'shared/split screen co-op'='Co-op'
        'multiplayer'='Multiplayer'; 'multi-player'='Multiplayer'; 'cross-platform multiplayer'='Multiplayer'; 'pvp'='PvP'; 'online pvp'='PvP'; 'massively multiplayer'='MMO'; 'mmorpg'='MMO'
        'singleplayer'='Singleplayer'; 'single-player'='Singleplayer'
    }
    $gfetch = {
        param($id)
        $ok = $false; $tags = @(); $more = @()
        try {
            $r = Invoke-WebRequest -Uri "https://store.steampowered.com/app/$id/?l=english" -UseBasicParsing -TimeoutSec 20
            $ok = $true
            foreach ($m in [regex]::Matches($r.Content, '(?s)class="app_tag"[^>]*>\s*([^<]+?)\s*</a>')) { $tags += [Net.WebUtility]::HtmlDecode($m.Groups[1].Value) }
        } catch {}
        if ($tags.Count -eq 0) {
            try {
                $r = Invoke-RestMethod -Uri "https://steamspy.com/api.php?request=appdetails&appid=$id" -TimeoutSec 20; $ok = $true
                if ($r.tags) { $tags += @($r.tags.PSObject.Properties | Sort-Object { [int]$_.Value } -Descending | ForEach-Object { $_.Name }) }
            } catch {}
            Start-Sleep -Milliseconds 1100
        }
        try {
            $d = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails?appids=$id&l=english" -TimeoutSec 15; $ok = $true
            $x = $d.$id.data
            if ($x) { foreach ($n in (@($x.genres) + @($x.categories))) { if ($n -and $n.description) { $more += $n.description } } }
        } catch {}
        if (-not $ok) { return $null }
        $res = @()
        foreach ($n in (@($tags | Select-Object -First 15) + $more)) {
            $c = $gmap["$n".ToLower().Trim()]
            if ($c -and $res -notcontains $c) { $res += $c }
            if ($res.Count -ge 7) { break }
        }
        ($res -join ',')
    }
    $walk = {
        param($dir, $pattern, $depth)
        try {
            foreach ($f in [IO.Directory]::EnumerateFiles($dir, $pattern)) { [IO.FileInfo]$f }
            if ($depth -gt 0) { foreach ($d in [IO.Directory]::EnumerateDirectories($dir)) { if (([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint) -eq 0) { & $walk $d $pattern ($depth - 1) } } }
        } catch {}
    }
    foreach ($j in $jobs) {
        try {
            $id = $null
            if ($j.Id) { $id = $j.Id }
            if (-not $id) { foreach ($f in @(& $walk $j.Dir 'OnlineFix*.ini' 3)) {
                if ($f.Length -lt 65536 -and (Get-Content -LiteralPath $f.FullName -Raw) -match '(?im)^\s*RealAppId\s*=\s*(\d+)') { $id = $Matches[1]; break } } }
            if (-not $id) { foreach ($f in @(& $walk $j.Dir 'steam_appid.txt' 3)) {
                $t = $(if ($f.Length -lt 1024) { (Get-Content -LiteralPath $f.FullName -Raw).Trim() } else { '' }); if ($t -match '^\d+$' -and $t -ne '480') { $id = $t; break } } }
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
            if ($id -and "$id" -notmatch '^\d+$') { $id = $null }
            $ok = $false
            if ($id -and -not $j.SkipCover) {
                $base = "https://cdn.cloudflare.steamstatic.com/steam/apps/$id/"
                foreach ($u in 'library_600x900_2x.jpg', 'library_600x900.jpg', 'header.jpg', 'capsule_616x353.jpg') { if (& $get ($base + $u) $j.Cache) { $ok = $true; break } }
                if (-not $ok) { try { $d = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails?appids=$id" -TimeoutSec 15; $img = $d.$id.data.header_image; if ($img -and (& $get $img $j.Cache)) { $ok = $true } } catch {} }
            }
            if ($j.NeedGenres) { $gl = if ($id) { & $gfetch $id } else { '' }; $q.Enqueue([pscustomobject]@{ T = 'genre'; K = $j.Key; V = $gl; Id = $id }) }
            if (-not $j.SkipCover) {
                if ($ok) { $q.Enqueue([pscustomobject]@{ T = 'cover'; K = $j.Key; V = $j.Cache; Id = $id }) }
                else { if (-not $id) { Set-Content "$($j.Cache).none" '' }; $q.Enqueue([pscustomobject]@{ T = 'miss'; K = $j.Key }) }
            }
        } catch {}
    }
}
$sizeSb = {
    param($jobs, $q)
    foreach ($j in $jobs) {
        $s = 0L; $stack = New-Object 'System.Collections.Generic.Stack[string]'; $stack.Push($j.Dir)
        while ($stack.Count) {
            $cur = $stack.Pop()
            try {
                foreach ($f in [IO.Directory]::EnumerateFiles($cur)) { try { $s += ([IO.FileInfo]$f).Length } catch {} }
                foreach ($x in [IO.Directory]::EnumerateDirectories($cur)) { if (([IO.File]::GetAttributes($x) -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push($x) } }
            } catch {}
        }
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
$script:bg = @(); $script:bgLoose = @()
function Start-Bg($sb, $jobs, $track = $true) {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($sb.ToString()).AddArgument($jobs).AddArgument($script:q)
    $item = [pscustomobject]@{ PS = $ps; RS = $rs; H = $ps.BeginInvoke() }
    if ($track) { $script:bg += $item } else { $script:bgLoose += $item }
}
function Release-Bg($b) { try { $b.PS.Dispose() } catch {}; try { $b.RS.Dispose() } catch {} }
# Frees finished runspaces so they don't pile up over a long session.
function Reap-Bg {
    $script:bgLoose = @($script:bgLoose | ForEach-Object { if ($_.H.IsCompleted) { Release-Bg $_ } else { $_ } })
    if ($script:doneMsg -and $script:bg.Count -gt 0 -and -not @($script:bg | Where-Object { -not $_.H.IsCompleted }).Count) { foreach ($b in $script:bg) { Release-Bg $b }; $script:bg = @() }
}

# ---------- update checker (Steam developer patch notes) ----------
$newsSb = {
    param($jobs, $q)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach ($j in $jobs) {
        try {
            $r = Invoke-RestMethod -Uri "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=$($j.Id)&count=25&maxlength=1&feeds=steam_community_announcements&format=json" -TimeoutSec 20
            $best = $null
            foreach ($n in @($r.appnews.newsitems)) {
                if ($n.title -match '(?i)\b(patch|hotfix|update|changelog|change log|release notes|version|build)\b|\bv?\d+\.\d+' -and $n.title -notmatch '(?i)\bsale\b|giveaway|livestream|dev stream|developer stream') {
                    if (-not $best -or [long]$n.date -gt [long]$best.date) { $best = $n }
                }
            }
            $q.Enqueue([pscustomobject]@{ T = 'news'; K = $j.Key; Ok = $true; Date = $(if ($best) { [long]$best.date } else { 0 }); Title = $(if ($best) { "$($best.title)" } else { '' }); Url = $(if ($best) { "$($best.url)" } else { '' }) })
        } catch { $q.Enqueue([pscustomobject]@{ T = 'news'; K = $j.Key; Ok = $false }) }
    }
}
function Start-NewsCheck($force = $false) {
    if ("$($script:cfg['ui:online'])" -eq 'Off') { return }
    $now = [DateTime]::UtcNow.Ticks; $jobs = @()
    foreach ($g in $script:games) {
        $id = "$($script:cfg['app:' + $g.Key])"; if ($id -notmatch '^\d+$') { continue }
        $last = [long]("0" + [string]$script:cfg["newschk:$($g.Key)"])
        if (-not $force -and $last -gt 0 -and ($now - $last) -lt [TimeSpan]::FromHours(6).Ticks) { continue }
        $jobs += [pscustomobject]@{ Key = $g.Key; Id = $id }
    }
    if ($jobs) { Start-Bg $newsSb $jobs }
}

# ---------- UI ----------
# ---------- theming (defaults = the original dark look) ----------
$Themes = @{
    Dark     = @{ Bg = '#1B1B1D'; Panel = '#242427'; Panel2 = '#2F2F34'; Card = '#2B2B2E'; Btn = '#38383C'; Hover = '#2E2E32'; Text = '#F3F3F3'; Sub = '#B4B4B8'; Muted = '#808085'; ChipText = '#DDDDDD'; Thumb = '#5A5A5F'; IsDark = $true }
    Midnight = @{ Bg = '#000000'; Panel = '#0C0C0E'; Panel2 = '#141417'; Card = '#131316'; Btn = '#1F1F23'; Hover = '#18181B'; Text = '#F3F3F3'; Sub = '#A2A2A8'; Muted = '#6F6F78'; ChipText = '#D0D0D0'; Thumb = '#3A3A40'; IsDark = $true }
    Slate    = @{ Bg = '#151A21'; Panel = '#1C232C'; Panel2 = '#232C37'; Card = '#212A35'; Btn = '#2E3846'; Hover = '#263140'; Text = '#E8EEF5'; Sub = '#A9B6C6'; Muted = '#77869A'; ChipText = '#D3DCE8'; Thumb = '#455063'; IsDark = $true }
    Haunted  = @{ Bg = '#0F0A18'; Panel = '#1A1126'; Panel2 = '#241A33'; Card = '#2A1D3D'; Btn = '#3A2754'; Hover = '#2F2145'; Text = '#F6EFFF'; Sub = '#BDAAD6'; Muted = '#8F7BAB'; ChipText = '#E6DAF5'; Thumb = '#5B4380'; IsDark = $true }
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
    $script:hw = "$($script:cfg['ui:halloween'])" -ne 'Off'; $script:hwSound = "$($script:cfg['ui:hwsound'])" -ne 'Off'
    $tn = "$($script:cfg['ui:theme'])"; if (-not $Themes.ContainsKey($tn) -or $tn -eq 'Haunted') { $tn = 'Dark' }
    if ($script:hw) { $tn = 'Haunted' }
    $t = $Themes[$tn]
    $acc = "$($script:cfg['ui:accent'])"; if ($acc -notmatch '^#[0-9A-Fa-f]{6}$') { $acc = '#60CDFF' }
    if ($script:hw) { $acc = '#FF7A1A' }
    $r = $app.Resources
    foreach ($k in 'Text', 'Sub', 'Muted', 'ChipText', 'Thumb', 'Card', 'Btn', 'Hover', 'Panel', 'Panel2') { Set-Res "Ui$k" (New-Brush $t[$k]) }
    Set-Res 'UiAccent' (New-Brush $acc)
    $c = [Windows.Media.ColorConverter]::ConvertFromString($acc)
    Set-Res 'UiAccentFg' (New-Brush $(if ((0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B) -gt 150) { '#101010' } else { '#FFFFFF' }))
    if ($script:hw -or "$($script:cfg['ui:bg'])" -eq 'Glow') {
        $gb = [Windows.Media.LinearGradientBrush]::new(); $gb.StartPoint = [Windows.Point]::new(0, 0); $gb.EndPoint = [Windows.Point]::new(1, 1)
        $f = if ($t.IsDark) { 0.22 } else { 0.14 }
        $c0 = if ($script:hw) { Mix $t.Bg '#7A2BD8' 0.32 } else { Mix $t.Bg $acc $f }
        [void]$gb.GradientStops.Add((New-Object Windows.Media.GradientStop $c0, 0.0))
        [void]$gb.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($t.Bg)), 0.62))
        if ($script:hw) { [void]$gb.GradientStops.Add((New-Object Windows.Media.GradientStop (Mix $t.Bg '#FF7A1A' 0.1), 1.0)) }
        if ("$($script:cfg['ui:anim'])" -ne 'Off') {
            $sw = New-Object Windows.Media.Animation.DoubleAnimation 0.5, 0.88, (New-Object Windows.Duration ([TimeSpan]::FromSeconds(8)))
            $sw.AutoReverse = $true; $sw.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
            $se = New-Object Windows.Media.Animation.SineEase; $se.EasingMode = 'EaseInOut'; $sw.EasingFunction = $se
            [Windows.Media.Animation.Timeline]::SetDesiredFrameRate($sw, 30)
            $gb.GradientStops[1].BeginAnimation([Windows.Media.GradientStop]::OffsetProperty, $sw)
        } else { $gb.Freeze() }
        Set-Res 'UiWinBg' $gb
    } else { Set-Res 'UiWinBg' (New-Brush $t.Bg) }
    $sz = switch ("$($script:cfg['ui:size'])") { 'Small' { 180, 270 } 'Large' { 270, 405 } default { 224, 336 } }
    Set-Res 'UiPW' ([double]$sz[0]); Set-Res 'UiPH' ([double]$sz[1])
    $lf = [double]$sz[0] / 224; Set-Res 'UiListScale' (New-Object Windows.Media.ScaleTransform -ArgumentList @($lf, $lf))
    $an = "$($script:cfg['ui:anim'])"; $script:animOn = $an -ne 'Off'; $script:animK = switch ($an) { 'Fast' { 0.6 } 'Relaxed' { 1.7 } default { 1.0 } }
    $rd = switch ("$($script:cfg['ui:round'])") { 'Sharp' { 4 } 'Round' { 18 } default { 10 } }
    Set-Res 'UiRad' ([double]$rd); Set-Res 'UiRadD' ([double]($rd + 2)); Set-Res 'UiRadB' ([Windows.CornerRadius]::new(0, 0, $rd, $rd)); Set-Res 'UiRadS' ([Windows.CornerRadius]::new($rd + 2))
    $script:themeBg = $t.Bg; $script:themeDark = [bool]$t.IsDark
    if ($script:hw) { $ge = New-Object Windows.Media.Effects.DropShadowEffect; $ge.Color = [Windows.Media.ColorConverter]::ConvertFromString('#FF7A1A'); $ge.BlurRadius = 26; $ge.ShadowDepth = 0; $ge.Opacity = 0.75; $ge.Freeze(); Set-Res 'UiHoverGlow' $ge } else { Set-Res 'UiHoverGlow' $null }
    Set-TitleBar
    if ($w) { Update-Halloween }
}
function Anim-Slide($el, $axis, $from, $ms = 350, $delay = 0) {
    if (-not $script:animOn) { $el.Opacity = 1; $el.RenderTransform = $null; return }
    if ($delay -gt 0) { $el.Opacity = 0 }
    $tt = New-Object Windows.Media.TranslateTransform; $el.RenderTransform = $tt
    $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms * $script:animK)); $ea = New-Object Windows.Media.Animation.CubicEase; $ea.EasingMode = 'EaseOut'
    $a = New-Object Windows.Media.Animation.DoubleAnimation 0, 1, $dur; $a.BeginTime = [TimeSpan]::FromMilliseconds($delay)
    $b = New-Object Windows.Media.Animation.DoubleAnimation $from, 0, $dur; $b.EasingFunction = $ea; $b.BeginTime = $a.BeginTime
    $el.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
    $prop = if ($axis -eq 'x') { [Windows.Media.TranslateTransform]::XProperty } else { [Windows.Media.TranslateTransform]::YProperty }
    $tt.BeginAnimation($prop, $b)
}
function Fade($el, $from, $ms) {
    if (-not $script:animOn) { return }
    $a = New-Object Windows.Media.Animation.DoubleAnimation $from, 1, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms * $script:animK)))
    $el.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
}
function Stagger-Detail {
    if (-not $script:animOn) { return }
    $n = 0
    foreach ($c in @($detail.Content.Children)) {
        if ($c -is [Windows.Controls.Primitives.Popup]) { continue }
        $c.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
        Anim-Slide $c 'y' 16 360 (60 + $n * 45); $n++
    }
}
$app = [Windows.Application]::Current; if (-not $app) { $app = New-Object Windows.Application }
$app.Resources = [Windows.Markup.XamlReader]::Parse(@'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <x:Null x:Key="UiHoverGlow"/>
 <Style x:Key="Btn" TargetType="Button">
  <Setter Property="Foreground" Value="{DynamicResource UiText}"/><Setter Property="Background" Value="{DynamicResource UiBtn}"/><Setter Property="Padding" Value="14,10"/>
  <Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="13.5"/><Setter Property="Margin" Value="0,0,0,8"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
   <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}" RenderTransformOrigin="0.5,0.5"><Border.RenderTransform><ScaleTransform/></Border.RenderTransform><ContentPresenter HorizontalAlignment="Center"/></Border>
   <ControlTemplate.Triggers>
    <MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="IsEnabled" Value="True"/></MultiTrigger.Conditions>
     <MultiTrigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="Opacity" To="0.82" Duration="0:0:0.12"/></Storyboard></BeginStoryboard></MultiTrigger.EnterActions>
     <MultiTrigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.2" FillBehavior="Stop"/></Storyboard></BeginStoryboard></MultiTrigger.ExitActions>
    </MultiTrigger>
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
   <Border x:Name="b" Background="{DynamicResource UiCard}" CornerRadius="15" Padding="14,6" RenderTransformOrigin="0.5,0.5"><Border.RenderTransform><ScaleTransform/></Border.RenderTransform><TextBlock x:Name="t" Text="{TemplateBinding Content}" FontSize="12.5" Foreground="{DynamicResource UiChipText}"/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
     <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.06" Duration="0:0:0.12"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.06" Duration="0:0:0.12"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
     <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.16"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.16"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
    </Trigger>
    <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource UiAccent}"/><Setter TargetName="t" Property="Foreground" Value="{DynamicResource UiAccentFg}"/>
     <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.14" Duration="0:0:0.1" AutoReverse="True"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.14" Duration="0:0:0.1" AutoReverse="True"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
    </Trigger>
   </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style TargetType="ListBoxItem">
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem">
   <Border x:Name="b" CornerRadius="{DynamicResource UiRadS}" Padding="3" Margin="5" BorderThickness="2" BorderBrush="Transparent" Background="Transparent" RenderTransformOrigin="0.5,0.5"><Border.RenderTransform><ScaleTransform/></Border.RenderTransform><ContentPresenter/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource UiHover}"/></Trigger>
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
 <Style x:Key="HeartBtn" TargetType="ToggleButton"><Setter Property="Cursor" Value="Hand"/><Setter Property="Focusable" Value="False"/><Setter Property="Background" Value="#99000000"/><Setter Property="Foreground" Value="White"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToggleButton">
   <Border x:Name="b" Width="38" Height="38" CornerRadius="19" Background="{TemplateBinding Background}" RenderTransformOrigin="0.5,0.5"><Border.RenderTransform><ScaleTransform/></Border.RenderTransform>
    <Path x:Name="h" Width="20" Height="20" Stretch="Uniform" StrokeThickness="1.7" StrokeLineJoin="Round" Stroke="{TemplateBinding Foreground}" Fill="Transparent" Data="M12,21.35 L10.55,20.03 C5.4,15.36 2,12.28 2,8.5 C2,5.42 4.42,3 7.5,3 C9.24,3 10.91,3.81 12,5.09 C13.09,3.81 14.76,3 16.5,3 C19.58,3 22,5.42 22,8.5 C22,12.28 18.6,15.36 13.45,20.04 Z"/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsChecked" Value="True"><Setter TargetName="h" Property="Fill" Value="{DynamicResource UiAccent}"/><Setter TargetName="h" Property="Stroke" Value="{DynamicResource UiAccent}"/>
     <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.45" Duration="0:0:0.13" AutoReverse="True"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.45" Duration="0:0:0.13" AutoReverse="True"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
    </Trigger>
    <Trigger Property="IsMouseOver" Value="True">
     <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.12" Duration="0:0:0.1"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.12" Duration="0:0:0.1"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
     <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.12"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.12"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
    </Trigger>
   </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style x:Key="ToggleChip" TargetType="ToggleButton"><Setter Property="Margin" Value="0,0,6,0"/><Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToggleButton">
   <Border x:Name="b" Background="{DynamicResource UiCard}" CornerRadius="15" Padding="14,6" RenderTransformOrigin="0.5,0.5"><Border.RenderTransform><ScaleTransform/></Border.RenderTransform><TextBlock x:Name="t" Text="{TemplateBinding Content}" FontSize="12.5" Foreground="{DynamicResource UiChipText}"/></Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
     <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.06" Duration="0:0:0.12"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.06" Duration="0:0:0.12"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
     <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.16"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.16"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
    </Trigger>
    <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource UiAccent}"/><Setter TargetName="t" Property="Foreground" Value="{DynamicResource UiAccentFg}"/>
     <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.14" Duration="0:0:0.1" AutoReverse="True"/><DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.14" Duration="0:0:0.1" AutoReverse="True"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
    </Trigger>
   </ControlTemplate.Triggers>
  </ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style x:Key="CoverRect" TargetType="Rectangle"><Style.Triggers><DataTrigger Binding="{Binding Cover}" Value="{x:Null}"><Setter Property="Opacity" Value="0"/>
  <DataTrigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.7"/></Storyboard></BeginStoryboard></DataTrigger.ExitActions>
 </DataTrigger></Style.Triggers></Style>
 <ItemsPanelTemplate x:Key="PanelStack"><StackPanel/></ItemsPanelTemplate>
 <DataTemplate x:Key="TplList">
  <Grid x:Name="row" Height="100" Margin="6,0" LayoutTransform="{DynamicResource UiListScale}"><Grid.RenderTransform><TranslateTransform/></Grid.RenderTransform>
   <Grid.ColumnDefinitions><ColumnDefinition Width="82"/><ColumnDefinition Width="*"/><ColumnDefinition Width="130"/><ColumnDefinition Width="150"/><ColumnDefinition Width="54"/></Grid.ColumnDefinitions>
   <Grid Width="62" Height="88" HorizontalAlignment="Left">
    <Rectangle RadiusX="8" RadiusY="8" Fill="{Binding Accent}"/>
    <TextBlock Text="{Binding Letter}" FontSize="30" FontWeight="Bold" Foreground="#44FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    <Rectangle RadiusX="8" RadiusY="8" Style="{StaticResource CoverRect}"><Rectangle.Fill><ImageBrush ImageSource="{Binding Cover}" Stretch="UniformToFill"/></Rectangle.Fill></Rectangle>
   </Grid>
   <StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock Text="{Binding Name}" FontSize="19" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/><TextBlock Text="{Binding TagLine}" FontSize="14" Foreground="{DynamicResource UiMuted}" Margin="0,5,0,0"/></StackPanel>
   <TextBlock Grid.Column="2" Text="{Binding SizeText}" VerticalAlignment="Center" Foreground="{DynamicResource UiSub}" FontSize="16"/>
   <TextBlock Grid.Column="3" Text="{Binding Date}" VerticalAlignment="Center" Foreground="{DynamicResource UiSub}" FontSize="16"/>
   <ToggleButton Grid.Column="4" Tag="heart" IsChecked="{Binding Fav, Mode=TwoWay}" Style="{StaticResource HeartBtn}" Background="{DynamicResource UiCard}" Foreground="{DynamicResource UiSub}" VerticalAlignment="Center" HorizontalAlignment="Center" ToolTip="Favourite"/>
  </Grid>
 <DataTemplate.Triggers><DataTrigger Binding="{Binding RelativeSource={RelativeSource AncestorType=ListBoxItem}, Path=IsMouseOver}" Value="True">
   <DataTrigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="row" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" To="8" Duration="0:0:0.16"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation></Storyboard></BeginStoryboard></DataTrigger.EnterActions>
   <DataTrigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="row" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" To="0" Duration="0:0:0.22"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation></Storyboard></BeginStoryboard></DataTrigger.ExitActions>
  </DataTrigger></DataTemplate.Triggers>
 </DataTemplate>
</ResourceDictionary>
'@)
Apply-Theme
$w = try { [Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="Repack Shelf" Width="1240" Height="780" MinWidth="980" MinHeight="600"
 WindowStartupLocation="CenterScreen" FontFamily="Segoe UI Variable Text, Segoe UI" UseLayoutRounding="True">
 <Window.Triggers><EventTrigger RoutedEvent="Window.Loaded"><BeginStoryboard><Storyboard>
  <DoubleAnimation Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.45"/>
  <DoubleAnimation Storyboard.TargetName="root" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" From="0.97" To="1" Duration="0:0:0.6"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation><DoubleAnimation Storyboard.TargetName="root" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" From="0.97" To="1" Duration="0:0:0.6"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
 </Storyboard></BeginStoryboard></EventTrigger></Window.Triggers>
 <Grid x:Name="root" RenderTransformOrigin="0.5,0.5"><Grid.RenderTransform><ScaleTransform/></Grid.RenderTransform>
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid Margin="24,18,24,8">
   <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="300"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,24,0">
    <TextBlock Text="Repack Shelf" FontSize="25" FontWeight="SemiBold" VerticalAlignment="Center"/>
    <Viewbox x:Name="hwPumpkin" Width="34" Height="34" Margin="10,0,0,0" Cursor="Hand" Visibility="Collapsed" ToolTip="Boo!"><Canvas Width="100" Height="100" Background="Transparent">
     <Path Fill="#5E8C31" Data="M47,24 C47,14 52,8 61,6 L63,12 C57,14 55,18 55,26 Z"/>
     <Ellipse Canvas.Left="6" Canvas.Top="22" Width="88" Height="70"><Ellipse.Fill><RadialGradientBrush GradientOrigin="0.4,0.35"><GradientStop Color="#FFB347" Offset="0"/><GradientStop Color="#F26A12" Offset="0.7"/><GradientStop Color="#C24A06" Offset="1"/></RadialGradientBrush></Ellipse.Fill></Ellipse>
     <Ellipse Canvas.Left="20" Canvas.Top="22" Width="34" Height="70" Stroke="#B8400A" StrokeThickness="2.2" Opacity="0.7"/>
     <Ellipse Canvas.Left="46" Canvas.Top="22" Width="34" Height="70" Stroke="#B8400A" StrokeThickness="2.2" Opacity="0.7"/>
     <Path Fill="#FFE27A" Data="M24,50 L40,50 L32,36 Z"/>
     <Path Fill="#FFE27A" Data="M60,50 L76,50 L68,36 Z"/>
     <Path Fill="#FFE27A" Data="M26,64 L38,72 L45,64 L50,73 L55,64 L62,72 L74,64 L70,80 L30,80 Z"/>
    </Canvas></Viewbox>
   </StackPanel>
   <Border Grid.Column="1" Background="{DynamicResource UiCard}" CornerRadius="9" Padding="12,2">
    <Grid><TextBox x:Name="search" Background="Transparent" Foreground="{DynamicResource UiText}" CaretBrush="{DynamicResource UiText}" BorderThickness="0" FontSize="14" Padding="0,7"/>
     <TextBlock x:Name="ph" Text="Search games" Foreground="{DynamicResource UiMuted}" FontSize="14" IsHitTestVisible="False" VerticalAlignment="Center"/>
     <Border IsHitTestVisible="False" Margin="-12,-2" BorderThickness="1.5" CornerRadius="9" BorderBrush="{DynamicResource UiAccent}" Opacity="0"><Border.Style><Style TargetType="Border"><Style.Triggers>
      <DataTrigger Binding="{Binding IsKeyboardFocused, ElementName=search}" Value="True">
       <DataTrigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.18"/></Storyboard></BeginStoryboard></DataTrigger.EnterActions>
       <DataTrigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.25"/></Storyboard></BeginStoryboard></DataTrigger.ExitActions>
      </DataTrigger></Style.Triggers></Style></Border.Style></Border></Grid></Border>
   <StackPanel x:Name="chips" Grid.Column="2" Orientation="Horizontal" Margin="18,0,0,0" VerticalAlignment="Center">
    <RadioButton Content="All" Tag="All" IsChecked="True" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="FitGirl" Tag="FitGirl" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="DODI" Tag="DODI" Style="{StaticResource Chip}" GroupName="f"/>
    <RadioButton Content="OnlineFix" Tag="OnlineFix" Style="{StaticResource Chip}" GroupName="f"/>
    <TextBlock x:Name="count" Foreground="{DynamicResource UiMuted}" VerticalAlignment="Center" Margin="10,0,0,0"/>
   </StackPanel>
   <StackPanel Grid.Column="3" Orientation="Horizontal">
    <Button x:Name="btnCustom" Content="Settings" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
    <Button x:Name="btnScan" Content="Rescan" Style="{StaticResource Btn}" Margin="0"/>
   </StackPanel>
  </Grid>
  <Grid Grid.Row="1" Margin="14,4,0,0">
   <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="350"/></Grid.ColumnDefinitions>
   <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <StackPanel Margin="8,0,0,6">
     <WrapPanel>
      <TextBlock Text="SORT" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}" VerticalAlignment="Center" Margin="0,0,10,6"/>
      <StackPanel x:Name="sortChips" Orientation="Horizontal" Margin="0,0,0,6"><RadioButton Content="Name" Tag="Name" GroupName="so" IsChecked="True" Style="{StaticResource Chip}"/><RadioButton Content="Size" Tag="Size" GroupName="so" Style="{StaticResource Chip}"/><RadioButton Content="Date" Tag="Date" GroupName="so" Style="{StaticResource Chip}"/></StackPanel>
      <TextBlock Text="VIEW" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}" VerticalAlignment="Center" Margin="0,0,10,6"/>
      <StackPanel x:Name="viewChips" Orientation="Horizontal" Margin="20,0,20,6"><RadioButton Content="Grid" Tag="Grid" GroupName="vw" IsChecked="True" Style="{StaticResource Chip}"/><RadioButton Content="List" Tag="List" GroupName="vw" Style="{StaticResource Chip}"/></StackPanel>
      <ToggleButton x:Name="favChip" Content="Favourites" Style="{StaticResource ToggleChip}" Margin="0,0,6,6"/>
      <ToggleButton x:Name="genreBtn" Content="Genre" Visibility="Collapsed" Style="{StaticResource ToggleChip}" Margin="0,0,6,6"/>
      <ToggleButton x:Name="updChip" Content="Updates" Visibility="Collapsed" Style="{StaticResource ToggleChip}" Margin="0,0,6,6"/>
      <Popup x:Name="genrePop" PlacementTarget="{Binding ElementName=genreBtn}" Placement="Bottom" StaysOpen="False" AllowsTransparency="True" PopupAnimation="Fade">
       <Border Margin="0,6,14,14" Width="430" Background="{DynamicResource UiPanel2}" BorderBrush="{DynamicResource UiCard}" BorderThickness="1" CornerRadius="12" Padding="14,14,14,6">
        <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="2" Opacity="0.45"/></Border.Effect>
        <StackPanel><WrapPanel x:Name="catChips"/><Button x:Name="genreClear" Content="Clear genres" Style="{StaticResource Btn}" Padding="12,6" Margin="0,2,0,8" HorizontalAlignment="Left"/></StackPanel>
       </Border></Popup>
     </WrapPanel>
    </StackPanel>
    <ListBox Grid.Row="1" x:Name="list" Foreground="{DynamicResource UiText}" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled" Margin="0,0,6,0">
    <ListBox.ItemsPanel><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></ListBox.ItemsPanel>
    <ListBox.ItemTemplate><DataTemplate>
     <Grid x:Name="card" Width="{DynamicResource UiPW}" Height="{DynamicResource UiPH}" RenderTransformOrigin="0.5,0.5"><Grid.RenderTransform><ScaleTransform/></Grid.RenderTransform>
      <Rectangle RadiusX="{DynamicResource UiRad}" RadiusY="{DynamicResource UiRad}" Fill="{Binding Accent}"/>
      <TextBlock Text="{Binding Letter}" FontSize="96" FontWeight="Bold" Foreground="#33FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-40,0,0"/>
      <Image Source="{Binding Icon}" Width="56" Height="56" Margin="0,70,0,0" Opacity="0.9"/>
      
      <Rectangle RadiusX="{DynamicResource UiRad}" RadiusY="{DynamicResource UiRad}" Style="{StaticResource CoverRect}"><Rectangle.Fill><ImageBrush ImageSource="{Binding Cover}" Stretch="UniformToFill"/></Rectangle.Fill></Rectangle>
      <Border VerticalAlignment="Bottom" Height="130" CornerRadius="{DynamicResource UiRadB}"><Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#00000000" Offset="0"/><GradientStop Color="#EE000000" Offset="1"/></LinearGradientBrush></Border.Background>
       <StackPanel VerticalAlignment="Bottom" Margin="10,0,10,9">
        <TextBlock Text="{Binding Name}" Foreground="White" TextWrapping="Wrap" MaxHeight="46" FontSize="15" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
        <TextBlock Text="{Binding SizeText}" Foreground="#CCFFFFFF" FontSize="13" Margin="0,3,0,0"/></StackPanel></Border>
      <Grid ClipToBounds="True" IsHitTestVisible="False"><Rectangle x:Name="shine" Width="90" HorizontalAlignment="Left"><Rectangle.RenderTransform><TranslateTransform X="-120"/></Rectangle.RenderTransform><Rectangle.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="1,0.12"><GradientStop Color="#00FFFFFF" Offset="0"/><GradientStop Color="#40FFFFFF" Offset="0.5"/><GradientStop Color="#00FFFFFF" Offset="1"/></LinearGradientBrush></Rectangle.Fill></Rectangle></Grid>
      <ToggleButton Tag="heart" IsChecked="{Binding Fav, Mode=TwoWay}" Style="{StaticResource HeartBtn}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,12,12,0" ToolTip="Favourite"/>
      <Border HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,56,12,0" Background="{DynamicResource UiAccent}" CornerRadius="9" Padding="8,2" ToolTip="{Binding UpdText}">
       <Border.Style><Style TargetType="Border"><Setter Property="Visibility" Value="Collapsed"/><Style.Triggers><DataTrigger Binding="{Binding HasUpd}" Value="True"><Setter Property="Visibility" Value="Visible"/>
        <DataTrigger.EnterActions><BeginStoryboard x:Name="pulse"><Storyboard Timeline.DesiredFrameRate="30"><DoubleAnimation Storyboard.TargetProperty="Opacity" From="1" To="0.55" Duration="0:0:0.9" AutoReverse="True" RepeatBehavior="Forever"/></Storyboard></BeginStoryboard></DataTrigger.EnterActions>
        <DataTrigger.ExitActions><RemoveStoryboard BeginStoryboardName="pulse"/></DataTrigger.ExitActions>
       </DataTrigger></Style.Triggers></Style></Border.Style>
       <TextBlock Text="UPDATE" FontSize="10.5" FontWeight="Bold" Foreground="{DynamicResource UiAccentFg}"/></Border>
      <ItemsControl ItemsSource="{Binding Badges}" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="8"><ItemsControl.ItemTemplate><DataTemplate>
       <Border Background="{Binding Color}" CornerRadius="9" Padding="8,2" Margin="0,0,0,4" HorizontalAlignment="Left"><TextBlock Text="{Binding Text}" FontSize="10.5" FontWeight="SemiBold" Foreground="White"/></Border>
      </DataTemplate></ItemsControl.ItemTemplate></ItemsControl>
     </Grid>
     <DataTemplate.Triggers><DataTrigger Binding="{Binding RelativeSource={RelativeSource AncestorType=ListBoxItem}, Path=IsMouseOver}" Value="True">
      <Setter TargetName="card" Property="Effect" Value="{DynamicResource UiHoverGlow}"/>
      <DataTrigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="card" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.04" Duration="0:0:0.2"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation><DoubleAnimation Storyboard.TargetName="card" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.04" Duration="0:0:0.2"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation><DoubleAnimation Storyboard.TargetName="shine" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" From="-120" To="340" Duration="0:0:0.75"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseInOut"/></DoubleAnimation.EasingFunction></DoubleAnimation></Storyboard></BeginStoryboard></DataTrigger.EnterActions>
      <DataTrigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="card" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.24"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation><DoubleAnimation Storyboard.TargetName="card" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.24"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation></Storyboard></BeginStoryboard></DataTrigger.ExitActions>
     </DataTrigger></DataTemplate.Triggers></DataTemplate></ListBox.ItemTemplate>
   </ListBox></Grid>
   <Border Grid.Column="1" Background="{DynamicResource UiPanel}" CornerRadius="14,0,0,0" Padding="26,26,26,16">
    <Grid>
     <TextBlock x:Name="empty" Text="Select a game" Foreground="{DynamicResource UiMuted}" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
     <Canvas x:Name="hwGhost" Width="80" Height="96" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,0,0,150" Cursor="Hand" Opacity="0" IsHitTestVisible="False" Visibility="{Binding Visibility, ElementName=empty}" RenderTransformOrigin="0.5,0.5">
      <Canvas.Effect><DropShadowEffect Color="#B58CFF" BlurRadius="26" ShadowDepth="0" Opacity="0.55"/></Canvas.Effect>
      <Path Fill="#F4ECFF" Opacity="0.95" Data="M6,88 L6,40 C6,6 74,6 74,40 L74,88 L63,78 L52,88 L40,78 L29,88 L17,78 Z"/>
      <Ellipse Canvas.Left="25" Canvas.Top="34" Width="9" Height="13" Fill="#2A1A3A"/>
      <Ellipse Canvas.Left="46" Canvas.Top="34" Width="9" Height="13" Fill="#2A1A3A"/>
      <Ellipse Canvas.Left="33" Canvas.Top="54" Width="14" Height="18" Fill="#2A1A3A" Opacity="0.85"/>
     </Canvas>
     <ScrollViewer x:Name="detail" Visibility="Collapsed" VerticalScrollBarVisibility="Auto"><StackPanel>
      <Grid Width="200" Height="300" Margin="0,0,0,16">
       <Rectangle RadiusX="{DynamicResource UiRadD}" RadiusY="{DynamicResource UiRadD}" Fill="{Binding Accent}"/><TextBlock Text="{Binding Letter}" FontSize="96" FontWeight="Bold" Foreground="#33FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-50,0,0"/><Image Source="{Binding Icon}" Width="64" Height="64" Margin="0,80,0,0"/>
       <Rectangle RadiusX="{DynamicResource UiRadD}" RadiusY="{DynamicResource UiRadD}" Style="{StaticResource CoverRect}"><Rectangle.Fill><ImageBrush ImageSource="{Binding Cover}" Stretch="UniformToFill"/></Rectangle.Fill></Rectangle>
      </Grid>
      <TextBlock Text="{Binding Name}" FontSize="21" FontWeight="SemiBold" TextWrapping="Wrap" HorizontalAlignment="Center" TextAlignment="Center"/>
      <ItemsControl ItemsSource="{Binding Badges}" HorizontalAlignment="Center" Margin="0,8,0,14"><ItemsControl.ItemsPanel><ItemsPanelTemplate><StackPanel Orientation="Horizontal"/></ItemsPanelTemplate></ItemsControl.ItemsPanel><ItemsControl.ItemTemplate><DataTemplate>
       <Border Background="{Binding Color}" CornerRadius="10" Padding="10,3" Margin="3,0"><TextBlock Text="{Binding Text}" FontSize="11.5" FontWeight="SemiBold" Foreground="White"/></Border>
      </DataTemplate></ItemsControl.ItemTemplate></ItemsControl>
      <TextBlock Text="{Binding Meta}" Foreground="{DynamicResource UiSub}" FontSize="12.5" LineHeight="22" TextWrapping="Wrap" Margin="0,0,0,18"/>
      <Button x:Name="btnPlay" Content="Play" Style="{StaticResource Btn}" Background="{DynamicResource UiAccent}" Foreground="{DynamicResource UiAccentFg}" FontWeight="SemiBold" FontSize="15" Padding="14,12"/>
      <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
       <Button x:Name="btnFolder" Content="Open folder" Style="{StaticResource Btn}" Margin="0,0,4,0"/>
       <Button x:Name="btnMore" Grid.Column="1" Content="More..." Style="{StaticResource Btn}" Margin="4,0,0,0"/></Grid>
      <Popup x:Name="morePop" PlacementTarget="{Binding ElementName=btnMore}" Placement="Top" StaysOpen="False" AllowsTransparency="True" PopupAnimation="Fade">
       <Border Margin="14" Width="280" Background="{DynamicResource UiPanel2}" BorderBrush="{DynamicResource UiCard}" BorderThickness="1" CornerRadius="12" Padding="12,12,12,4">
        <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="2" Opacity="0.45"/></Border.Effect>
        <StackPanel>
         <Button x:Name="btnSeen" Content="Dismiss update notice" Style="{StaticResource Btn}" Visibility="Collapsed"/>
         <Button x:Name="btnNotes" Content="Find on Steam" Style="{StaticResource Btn}"/>
         <Button x:Name="btnExe" Content="Set .exe" Style="{StaticResource Btn}"/>
         <Button x:Name="btnFind" Content="Find cover online..." Style="{StaticResource Btn}"/>
         <Button x:Name="btnCover" Content="Set cover image" Style="{StaticResource Btn}"/>
      <Button x:Name="btnUn" Content="Uninstall completely" Style="{StaticResource Btn}" Background="#C42B1C"/>
        </StackPanel></Border></Popup>
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
    <Grid><TextBlock Text="Settings" FontSize="21" FontWeight="SemiBold" VerticalAlignment="Center"/><Button x:Name="btnCloseSet" Content="Close" Style="{StaticResource Btn}" HorizontalAlignment="Right" Padding="14,6" Margin="0"/></Grid>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,18,0,0"><StackPanel>
     <TextBlock Text="LIBRARY" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><Button x:Name="btnFold" Content="Game folders..." Style="{StaticResource Btn}" Margin="0,8,0,8"/><Button x:Name="btnStor" Content="Storage dashboard..." Style="{StaticResource Btn}" Margin="0,0,0,8"/><Button x:Name="btnUpdate" Content="Check for app updates" Style="{StaticResource Btn}" Margin="0,0,0,20"/><TextBlock Text="HALLOWEEN" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optHw" Margin="0,8,0,6"><RadioButton Content="On" Tag="On" GroupName="hw" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Off" Tag="Off" GroupName="hw" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="Haunted colours, embers, bats, a spider and a ghost. Overrides the theme and accent while on; Off restores your own look." FontSize="11.5" TextWrapping="Wrap" Foreground="{DynamicResource UiMuted}" Margin="0,0,0,14"/><TextBlock Text="SPOOKY SOUNDS" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optHwSound" Margin="0,8,0,20"><RadioButton Content="On" Tag="On" GroupName="hs" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Off" Tag="Off" GroupName="hs" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="THEME" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optTheme" Margin="0,8,0,20"><RadioButton Content="Dark" Tag="Dark" GroupName="th" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Midnight" Tag="Midnight" GroupName="th" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Slate" Tag="Slate" GroupName="th" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Light" Tag="Light" GroupName="th" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="ACCENT COLOUR" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/>
     <WrapPanel x:Name="swatches" Margin="0,8,0,4"/>
     <StackPanel Orientation="Horizontal" Margin="0,0,0,20"><Border Background="{DynamicResource UiCard}" CornerRadius="8" Padding="10,2" Margin="0,0,8,0"><TextBox x:Name="hexBox" Width="96" Background="Transparent" Foreground="{DynamicResource UiText}" CaretBrush="{DynamicResource UiText}" BorderThickness="0" Padding="0,6" FontSize="13"/></Border><Button x:Name="btnHex" Content="Apply" Style="{StaticResource Btn}" Padding="14,7" Margin="0"/></StackPanel>
     <TextBlock Text="POSTER SIZE" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optSize" Margin="0,8,0,20"><RadioButton Content="Small" Tag="Small" GroupName="ps" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Medium" Tag="Medium" GroupName="ps" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Large" Tag="Large" GroupName="ps" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="BACKGROUND" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optBg" Margin="0,8,0,20"><RadioButton Content="Solid" Tag="Solid" GroupName="bg" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Glow" Tag="Glow" GroupName="bg" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="CORNERS" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optRound" Margin="0,8,0,20"><RadioButton Content="Sharp" Tag="Sharp" GroupName="rd" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Soft" Tag="Soft" GroupName="rd" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Round" Tag="Round" GroupName="rd" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="ANIMATION SPEED" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optAnim" Margin="0,8,0,20"><RadioButton Content="Off" Tag="Off" GroupName="an" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Fast" Tag="Fast" GroupName="an" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Normal" Tag="Normal" GroupName="an" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Relaxed" Tag="Relaxed" GroupName="an" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="ONLINE LOOKUPS" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource UiMuted}"/><WrapPanel x:Name="optOnline" Margin="0,8,0,6"><RadioButton Content="On" Tag="On" GroupName="ol" Style="{StaticResource Chip}" Margin="0,0,6,8"/><RadioButton Content="Off" Tag="Off" GroupName="ol" Style="{StaticResource Chip}" Margin="0,0,6,8"/></WrapPanel><TextBlock Text="Covers, genres and patch notes send game names or Steam IDs to Steam and SteamSpy. Turn off to keep everything local." FontSize="11.5" TextWrapping="Wrap" Foreground="{DynamicResource UiMuted}" Margin="0,0,0,20"/>
     <Button x:Name="btnReset" Content="Reset to default" Style="{StaticResource Btn}" Margin="0,4,0,0"/>
    </StackPanel></ScrollViewer></Grid></Border>
  <Border x:Name="storage" Grid.RowSpan="3" HorizontalAlignment="Right" Width="360" Visibility="Collapsed" Background="{DynamicResource UiPanel2}" BorderBrush="{DynamicResource UiCard}" BorderThickness="1,0,0,0" Padding="24,20,24,16">
   <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <Grid><TextBlock Text="Storage" FontSize="21" FontWeight="SemiBold" VerticalAlignment="Center"/><Button x:Name="btnCloseStor" Content="Close" Style="{StaticResource Btn}" HorizontalAlignment="Right" Padding="14,6" Margin="0"/></Grid>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,18,0,0"><StackPanel x:Name="storBody"/></ScrollViewer></Grid></Border>
  <Grid x:Name="hwLayer" Grid.RowSpan="3" IsHitTestVisible="False" ClipToBounds="True" Visibility="Collapsed">
   <Canvas x:Name="hwDyn"/>
   <Canvas x:Name="hwStatic">
    <Path Canvas.Right="0" Canvas.Top="0" Width="90" Height="90" Stroke="#FFFFFF" StrokeThickness="0.9" Opacity="0.2" StrokeLineJoin="Round"
     Data="M90,0 L0,0 M90,0 L6.8,34.4 M90,0 L26.4,63.6 M90,0 L55.6,83.2 M90,0 L90,90 M60,0 Q64.1,5.2 62.3,11.5 Q68.1,14.7 68.8,21.2 Q75.3,22 78.5,27.7 Q84.9,25.9 90,30 M35,0 Q42.5,9.4 39.2,21 Q49.8,26.9 51.1,38.9 Q63.1,40.2 69,50.8 Q80.6,47.5 90,55 M10,0 Q21,13.7 16.1,30.6 Q31.5,39.1 33.4,56.6 Q50.9,58.5 59.4,73.9 Q76.3,69 90,80"/>
    <Canvas x:Name="hwSpider" Canvas.Right="46" Canvas.Top="0" Width="24" Height="40">
     <Line X1="12" Y1="-400" X2="12" Y2="14" Stroke="#99D8C8F0" StrokeThickness="0.9"/>
     <Path Data="M12,18 L3,11 L0,14 M12,18 L2,17 L-1,21 M12,18 L3,23 L1,28 M12,18 L21,11 L24,14 M12,18 L22,17 L25,21 M12,18 L21,23 L23,28" Stroke="#9F7AEA" StrokeThickness="1.1" StrokeLineJoin="Round"/>
     <Ellipse Canvas.Left="6" Canvas.Top="13" Width="12" Height="14" Fill="#2B1B42" Stroke="#9F7AEA" StrokeThickness="0.9"/>
     <Ellipse Canvas.Left="8.5" Canvas.Top="8" Width="7" Height="7" Fill="#2B1B42" Stroke="#9F7AEA" StrokeThickness="0.9"/>
     <Ellipse Canvas.Left="9.2" Canvas.Top="10" Width="2" Height="2" Fill="#FF3B3B"/><Ellipse Canvas.Left="12.8" Canvas.Top="10" Width="2" Height="2" Fill="#FF3B3B"/>
    </Canvas>
   </Canvas>
  </Grid>
  <Rectangle x:Name="hwFlash" Grid.RowSpan="3" Fill="#E6DCFF" Opacity="0" IsHitTestVisible="False"/>
  <ProgressBar x:Name="busy" Grid.Row="2" Height="3" VerticalAlignment="Top" IsIndeterminate="True" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource UiAccent}" Visibility="Collapsed"/>
  <TextBlock x:Name="status" Grid.Row="2" Foreground="{DynamicResource UiMuted}" FontSize="12" Margin="26,6,0,10"/>
 </Grid>
</Window>
'@) } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; [void][Windows.MessageBox]::Show("Window XAML failed:`n`n$($e.Message)", 'Repack Shelf', 'OK', 'Error'); exit 1 }
$w.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'UiWinBg'); $w.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'UiText')
foreach ($n in 'optHw','optHwSound','hwLayer','hwDyn','hwStatic','hwSpider','hwFlash','hwPumpkin','hwGhost') { Set-Variable -Name $n -Value $w.FindName($n) -Scope Script }
foreach ($n in 'search','ph','chips','count','btnFold','btnScan','list','empty','detail','btnPlay','btnFolder','btnExe','btnCover','btnFind','busy','btnUpdate','btnStor','storage','storBody','btnCloseStor','updBar','updTitle','updSub','btnUpd','btnLater','btnCustom','settings','btnCloseSet','optTheme','optSize','optBg','optAnim','swatches','hexBox','btnHex','btnReset','sortChips','viewChips','favChip','updChip','genreBtn','genrePop','genreClear','catChips','btnMore','morePop','btnSeen','btnNotes','optRound','optOnline','btnUn','status') { Set-Variable -Name $n -Value $w.FindName($n) -Scope Script }
# The window icon is drawn in code, so the title bar and taskbar always show it (even if the exe's own icon is stale or missing).
function New-AppIcon {
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $grad = New-Object Windows.Media.LinearGradientBrush -ArgumentList @([Windows.Media.Color]::FromRgb(96, 205, 255), [Windows.Media.Color]::FromRgb(123, 92, 255), [double]45)
    $dc.DrawRoundedRectangle($grad, $null, [Windows.Rect]::new(8, 8, 240, 240), 56, 56)
    $tf = New-Object Windows.Media.Typeface -ArgumentList @('Segoe UI Semibold')
    $ft = New-Object Windows.Media.FormattedText -ArgumentList @('R', [Globalization.CultureInfo]::InvariantCulture, [Windows.FlowDirection]::LeftToRight, $tf, [double]150, [Windows.Media.Brushes]::White)
    $dc.DrawText($ft, [Windows.Point]::new((256 - $ft.Width) / 2, (256 - $ft.Height) / 2))
    $dc.Close()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap -ArgumentList @(256, 256, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv); $rtb.Freeze(); $rtb
}
# Which icon the window uses: your own file first (running the script from the repo), then nothing at all when running the
# compiled exe (Windows then uses the icon built into the exe), and the drawn "R" only as a last resort.
function Get-AppIcon {
    $self = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $compiled = ($self -match '(?i)\.exe$') -and ($self -notmatch '(?i)\\(powershell|pwsh|powershell_ise)\.exe$')
    if ($compiled) { return $null }
    $cands = @()
    if ($PSScriptRoot) { $cands += (Join-Path $PSScriptRoot '..\build\RepackShelf.ico'); $cands += (Join-Path $PSScriptRoot 'RepackShelf.ico'); $cands += (Join-Path $PSScriptRoot 'build\RepackShelf.ico') }
    foreach ($c in $cands) {
        if (Test-Path -LiteralPath $c) {
            try {
                $dec = [Windows.Media.Imaging.BitmapDecoder]::Create([Uri]([IO.Path]::GetFullPath($c)), [Windows.Media.Imaging.BitmapCreateOptions]::None, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
                $f = $dec.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
                if ($f) { return $f }
            } catch { Write-Log "Could not read icon $c : $($_.Exception.Message)" }
        }
    }
    New-AppIcon
}
try { $ic = Get-AppIcon; if ($ic) { $w.Icon = $ic } } catch { Write-Log "Window icon failed: $($_.Exception.Message)" }
$w.Title = if ($AppVersion.StartsWith('__')) { 'Repack Shelf (dev build)' } else { "Repack Shelf v$AppVersion" }
$script:filter = 'All'; $script:games = @(); $script:byKey = @{}

# ---------- halloween ----------
$script:rnd = New-Object Random; $script:hwBats = @(); $script:sfxReady = $false; $script:sfxDead = $false; $script:hwHover = $null
$script:hwNextBat = (Get-Date).AddSeconds(7); $script:hwNextSpider = (Get-Date).AddSeconds(16)
$script:batGeo = [Windows.Media.Geometry]::Parse('M50,22 L54,14 L56,24 C62,18 74,16 98,22 C90,26 88,32 86,40 C80,34 74,34 70,42 C66,38 60,40 56,48 L50,58 L44,48 C40,40 34,38 30,42 C26,34 20,34 14,40 C12,32 10,26 2,22 C26,16 38,18 44,24 L46,14 Z')
function Play-Sfx($n) {
    if (-not ($script:hw -and $script:hwSound) -or $script:sfxDead) { return }
    try { if (-not $script:sfxReady) { $mv = 0.0; if ([double]::TryParse("$($script:cfg['ui:hwvol'])", [ref]$mv) -and $mv -gt 0 -and $mv -le 1) { [RsSfx]::Master = $mv }; [RsSfx]::Init(); $script:sfxReady = $true }; [RsSfx]::Play($n) }
    catch { $script:sfxDead = $true; Write-Log "Sound effects disabled: $($_.Exception.Message)" }
}
function New-Dbl($from, $to, $sec, $rev = $false, $forever = $true) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation ([double]$from), ([double]$to), (New-Object Windows.Duration ([TimeSpan]::FromSeconds($sec)))
    $a.AutoReverse = $rev; if ($forever) { $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever }
    [Windows.Media.Animation.Timeline]::SetDesiredFrameRate($a, 30)
    $a
}
function New-Keys($pairs, $pct = $true) {
    $ka = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    foreach ($p in $pairs) {
        $kt = if ($pct) { [Windows.Media.Animation.KeyTime]::FromPercent([double]$p[0]) } else { [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds([double]$p[0])) }
        $kf = New-Object Windows.Media.Animation.LinearDoubleKeyFrame -ArgumentList @([double]$p[1], $kt)
        [void]$ka.KeyFrames.Add($kf)
    }
    $ka
}
function Flash-Lightning {
    if (-not ($script:hw -and $script:animOn)) { return }
    $a = New-Keys @(@(0, 0.0), @(0.04, 0.28), @(0.1, 0.06), @(0.16, 0.22), @(0.7, 0.0)) $false
    $hwFlash.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
}
function Build-Ambient {
    $hwDyn.Children.Clear(); $script:hwBats = @()
    if (-not ($script:hw -and $script:animOn)) { return }
    $cw = [Math]::Max($hwLayer.ActualWidth, 600); $ch = [Math]::Max($hwLayer.ActualHeight, 400)
    # drifting fog banks
    for ($i = 0; $i -lt 3; $i++) {
        $e = New-Object Windows.Shapes.Ellipse; $e.Width = 560; $e.Height = 220; $e.IsHitTestVisible = $false
        $rg = New-Object Windows.Media.RadialGradientBrush
        [void]$rg.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(46, 150, 95, 255)), 0.0))
        [void]$rg.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0, 150, 95, 255)), 1.0))
        $rg.Freeze(); $e.Fill = $rg
        [Windows.Controls.Canvas]::SetTop($e, $ch - 150 - $i * 55 + $script:rnd.Next(-20, 20)); [Windows.Controls.Canvas]::SetLeft($e, 0)
        $fa = New-Dbl (-320 + $i * 140) ($cw - 240 - $i * 120) (46 + $i * 13) $true
        $fa.EasingFunction = New-Object Windows.Media.Animation.SineEase
        $e.BeginAnimation([Windows.Controls.Canvas]::LeftProperty, $fa)
        [void]$hwDyn.Children.Add($e)
    }
    # rising embers
    for ($i = 0; $i -lt 26; $i++) {
        $sz = 2 + $script:rnd.NextDouble() * 3
        $e = New-Object Windows.Shapes.Ellipse; $e.Width = $sz; $e.Height = $sz; $e.IsHitTestVisible = $false; $e.Opacity = 0
        $e.Fill = New-Brush $(if ($script:rnd.Next(3) -eq 0) { '#FFD36A' } else { '#FF7A1A' })
        [Windows.Controls.Canvas]::SetLeft($e, $script:rnd.NextDouble() * $cw); [Windows.Controls.Canvas]::SetTop($e, 0)
        $tt = New-Object Windows.Media.TranslateTransform; $e.RenderTransform = $tt
        $dur = 9 + $script:rnd.NextDouble() * 9; $off = [TimeSpan]::FromSeconds(-$script:rnd.NextDouble() * $dur)
        $ry = New-Dbl ($ch + 10) (-20) $dur $false; $ry.BeginTime = $off
        $sx = New-Dbl (-25) 25 ($dur / 2.2) $true
        $oa = New-Keys @(@(0, 0.0), @(0.18, 0.9), @(0.75, 0.7), @(1, 0.0)); $oa.Duration = New-Object Windows.Duration ([TimeSpan]::FromSeconds($dur)); $oa.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever; $oa.BeginTime = $off
        $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $ry)
        $tt.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $sx)
        $e.BeginAnimation([Windows.UIElement]::OpacityProperty, $oa)
        [void]$hwDyn.Children.Add($e)
    }
}
function Fly-Bats {
    if (-not ($script:hw -and $script:animOn)) { return }
    $cw = [Math]::Max($hwLayer.ActualWidth, 600); $ch = [Math]::Max($hwLayer.ActualHeight, 400)
    $count = $script:rnd.Next(1, 4); $dir = if ($script:rnd.Next(2) -eq 0) { 1.0 } else { -1.0 }
    $baseY = 50 + $script:rnd.NextDouble() * $ch * 0.35; $dur = 5.5 + $script:rnd.NextDouble() * 2.5
    Play-Sfx 'bat'
    for ($i = 0; $i -lt $count; $i++) {
        $p = New-Object Windows.Shapes.Path; $p.Data = $script:batGeo; $p.Stretch = 'Fill'; $p.IsHitTestVisible = $false
        $p.Width = 34 + $script:rnd.NextDouble() * 30; $p.Height = $p.Width * 0.6
        $p.Fill = New-Brush '#14091F'; $p.Stroke = New-Brush '#8A63D2'; $p.StrokeThickness = 0.8; $p.Opacity = 0.9
        $p.RenderTransformOrigin = [Windows.Point]::new(0.5, 0.4)
        $st = New-Object Windows.Media.ScaleTransform -ArgumentList @($dir, 1.0); $p.RenderTransform = $st
        $delay = [TimeSpan]::FromMilliseconds($i * 450 + $script:rnd.Next(0, 200))
        $x0 = if ($dir -gt 0) { -120.0 } else { $cw + 120.0 }; $x1 = if ($dir -gt 0) { $cw + 120.0 } else { -120.0 }
        $ax = New-Dbl $x0 $x1 $dur $false $false; $ax.BeginTime = $delay
        $y0 = $baseY + $i * 26
        $ay = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames; $ay.BeginTime = $delay
        $pcts = @(0, 0.2, 0.4, 0.6, 0.8, 1.0); $offs = @(0, -40, 30, -30, 25, -10)
        for ($k = 0; $k -lt $pcts.Count; $k++) {
            $kf = New-Object Windows.Media.Animation.EasingDoubleKeyFrame -ArgumentList @(([double]($y0 + $offs[$k])), [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($dur * $pcts[$k])))
            $kf.EasingFunction = New-Object Windows.Media.Animation.SineEase; [void]$ay.KeyFrames.Add($kf)
        }
        $fl = New-Dbl 1 0.35 0.11 $true; $fl.BeginTime = [TimeSpan]::FromMilliseconds($script:rnd.Next(0, 100))
        [Windows.Controls.Canvas]::SetLeft($p, $x0); [Windows.Controls.Canvas]::SetTop($p, $y0)
        [void]$hwDyn.Children.Add($p)
        $p.BeginAnimation([Windows.Controls.Canvas]::LeftProperty, $ax)
        $p.BeginAnimation([Windows.Controls.Canvas]::TopProperty, $ay)
        $st.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $fl)
        $script:hwBats += [pscustomobject]@{ El = $p; End = (Get-Date).AddSeconds($dur + 2 + $count * 0.6) }
    }
}
function Drop-Spider {
    if (-not ($script:hw -and $script:animOn)) { return }
    $ka = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $cin = New-Object Windows.Media.Animation.CubicEase; $cin.EasingMode = 'EaseIn'; $cout = New-Object Windows.Media.Animation.CubicEase; $cout.EasingMode = 'EaseOut'
    $pts = @(@(0, -90, $null), @(1.4, 105, $cout), @(3.2, 105, $null), @(4.8, -90, $cin))
    foreach ($q in $pts) {
        $kf = New-Object Windows.Media.Animation.EasingDoubleKeyFrame -ArgumentList @([double]$q[1], [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($q[0])))
        if ($q[2]) { $kf.EasingFunction = $q[2] }; [void]$ka.KeyFrames.Add($kf)
    }
    $hwSpider.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $ka)
    Play-Sfx 'spider'
}
$script:hwTimer = New-Object Windows.Threading.DispatcherTimer; $script:hwTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:hwTimer.Add_Tick({
    if (-not ($script:hw -and $script:animOn)) { return }
    $now = Get-Date
    $dead = @($script:hwBats | Where-Object { $_.End -lt $now })
    if ($dead.Count) { foreach ($d in $dead) { $hwDyn.Children.Remove($d.El) }; $script:hwBats = @($script:hwBats | Where-Object { $_.End -ge $now }) }
    if ($now -ge $script:hwNextBat) { Fly-Bats; $script:hwNextBat = $now.AddSeconds(18 + $script:rnd.NextDouble() * 30) }
    if ($now -ge $script:hwNextSpider) { Drop-Spider; $script:hwNextSpider = $now.AddSeconds(35 + $script:rnd.NextDouble() * 50) }
})
$script:hwResize = New-Object Windows.Threading.DispatcherTimer; $script:hwResize.Interval = [TimeSpan]::FromMilliseconds(500)
$script:hwResize.Add_Tick({ $script:hwResize.Stop(); Build-Ambient })
function Update-Halloween {
    if (-not $hwLayer) { return }
    $on = [bool]$script:hw; $fx = $on -and $script:animOn
    $hwLayer.Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
    $hwPumpkin.Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
    $hwGhost.Opacity = if ($on) { 1 } else { 0 }; $hwGhost.IsHitTestVisible = $on
    if ("$($empty.Text)" -like 'Select a game*') { $empty.Text = if ($on) { 'Select a game... if you dare' } else { 'Select a game' } }
    # ghost: gentle float
    if (-not ($hwGhost.RenderTransform -is [Windows.Media.TransformGroup])) {
        $tg = New-Object Windows.Media.TransformGroup; $script:ghostS = New-Object Windows.Media.ScaleTransform; $script:ghostT = New-Object Windows.Media.TranslateTransform
        [void]$tg.Children.Add($script:ghostS); [void]$tg.Children.Add($script:ghostT); $hwGhost.RenderTransform = $tg
    }
    if ($fx) {
        $fy = New-Dbl (-9) 9 2.4 $true; $fy.EasingFunction = New-Object Windows.Media.Animation.SineEase
        $script:ghostT.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $fy)
    } else { $script:ghostT.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $null) }
    # pumpkin: candle flicker
    if ($on) {
        $pe = New-Object Windows.Media.Effects.DropShadowEffect; $pe.Color = [Windows.Media.ColorConverter]::ConvertFromString('#FF7A1A'); $pe.BlurRadius = 20; $pe.ShadowDepth = 0; $pe.Opacity = 0.8
        $hwPumpkin.Effect = $pe
        if ($fx) {
            $fk = New-Keys @(@(0, 0.9), @(0.15, 0.5), @(0.3, 0.85), @(0.45, 0.4), @(0.6, 0.95), @(0.8, 0.6), @(1, 0.9))
            $fk.Duration = New-Object Windows.Duration ([TimeSpan]::FromSeconds(2.6)); $fk.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
            [Windows.Media.Animation.Timeline]::SetDesiredFrameRate($fk, 30)
            $pe.BeginAnimation([Windows.Media.Effects.DropShadowEffect]::OpacityProperty, $fk)
        }
    } else { $hwPumpkin.Effect = $null }
    $hwSpider.RenderTransform = New-Object Windows.Media.TranslateTransform 0, -90
    if ($on) { $hwTimer.Start() } else { $hwTimer.Stop() }
    Build-Ambient
}
$hwPumpkin.Add_MouseLeftButtonUp({ Play-Sfx 'thunder'; Flash-Lightning })
$hwGhost.Add_MouseLeftButtonUp({
    Play-Sfx 'ghost'
    if ($script:animOn -and $script:ghostS) {
        $pop = New-Dbl 1 1.3 0.16 $true $false
        $script:ghostS.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $pop); $script:ghostS.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $pop)
    }
})
$hwLayer.Add_SizeChanged({ if ($script:hw) { $script:hwResize.Stop(); $script:hwResize.Start() } })
$list.Add_PreviewMouseMove({
    if (-not ($script:hw -and $script:hwSound)) { return }
    try {
        $c = [Windows.Controls.ItemsControl]::ContainerFromElement($list, [Windows.DependencyObject]$args[1].OriginalSource)
        if ($null -ne $c -and -not [object]::ReferenceEquals($c, $script:hwHover)) { Play-Sfx 'hover' }
        $script:hwHover = $c
    } catch {}
})

function Animate-In {
    if (-not $script:animOn) { return }
    $n = 0
    $ease = New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'
    $pop = New-Object Windows.Media.Animation.BackEase; $pop.EasingMode = 'EaseOut'; $pop.Amplitude = 0.45
    $s0 = if ($script:view -eq 'List') { 0.97 } else { 0.9 }
    foreach ($it in $list.Items) {
        $c = $list.ItemContainerGenerator.ContainerFromItem($it); if (-not $c) { continue }
        $st = New-Object Windows.Media.ScaleTransform $s0, $s0
        $tt = New-Object Windows.Media.TranslateTransform 0, 30
        $tg = New-Object Windows.Media.TransformGroup; [void]$tg.Children.Add($st); [void]$tg.Children.Add($tt)
        $c.RenderTransformOrigin = [Windows.Point]::new(0.5, 0.5); $c.RenderTransform = $tg; $c.Opacity = 0
        $begin = [TimeSpan]::FromMilliseconds([Math]::Min($n * 28 * $script:animK, 650))
        $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(520 * $script:animK))
        $durF = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(380 * $script:animK))
        $a = New-Object Windows.Media.Animation.DoubleAnimation 0, 1, $durF; $a.BeginTime = $begin
        $b = New-Object Windows.Media.Animation.DoubleAnimation 30, 0, $dur; $b.BeginTime = $begin; $b.EasingFunction = $ease
        $s = New-Object Windows.Media.Animation.DoubleAnimation $s0, 1, $dur; $s.BeginTime = $begin; $s.EasingFunction = $pop
        $c.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
        $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $b)
        $st.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $s)
        $st.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $s)
        $n++
    }
}
function Refresh-List($keep = $false) {
    $q = $search.Text.Trim(); $f = $script:filter; $gsel = @($script:genres)
    $v = @($script:games | Where-Object {
        $t = $_.Tags; $gg = @("$($_.Genres)" -split ',')
        (($f -eq 'All') -or (($t -split ',') -contains $f)) -and (-not $q -or $_.Name -like "*$q*" -or $_.Genres -like "*$q*") -and (-not $script:favOnly -or $_.Fav) -and (-not $script:updOnly -or $_.HasUpd) -and (@($gsel | Where-Object { $gg -notcontains $_ }).Count -eq 0)
    })
    $v = @(switch ($script:sort) { 'Size' { $v | Sort-Object { $_.Bytes } -Descending } 'Date' { $v | Sort-Object { $_.DateTicks } -Descending } default { $v | Sort-Object { $_.Name } } })
    $sel = $list.SelectedItem
    $list.ItemsSource = $v; $count.Text = "$($v.Count) game(s)"
    if ($keep -and $sel -and ($v -contains $sel)) { $list.SelectedItem = $sel; return }
    $list.UpdateLayout(); Animate-In
    if ($v.Count -eq 0) { $empty.Text = if ($script:games.Count -eq 0) { "No repack or OnlineFix games found yet.`nUse Folders to add the folder your games live in." } else { 'Nothing matches this filter' } }
    $detail.Visibility = 'Collapsed'; $empty.Visibility = 'Visible'
}
function Scan-And-Show($full = $false) {
    foreach ($p in $script:bg) { try { $p.PS.Stop() } catch {}; Release-Bg $p }; $script:bg = @(); $script:miss = 0; $script:doneMsg = $false
    if ($full) { $script:ofCache = @{}; $script:datCache = @{}; $script:exeCache = @{}; foreach ($k in @($script:cfg.Keys)) { if ($k -like 'gen:*' -and "$($script:cfg[$k])" -eq '-') { $script:cfg.Remove($k) } } }
    $script:fullScan = $full; $script:scanning = $true; $btnScan.IsEnabled = $false; $w.Cursor = 'Wait'
    $sig = { param($l) (@($l | ForEach-Object { "$($_.Key):$($_.Tags):$($_.Name):$($_.Dir)" }) -join '|') }
    $before = & $sig $script:games
    $recs = @(Scan)
    $script:games = @(Build-Games $recs); $script:byKey = @{}
    foreach ($g in $script:games) { $script:byKey[$g.Key] = $g }
    Rebuild-Cats; Refresh-UpdChip; $script:scanning = $false; $btnScan.IsEnabled = $true; $w.Cursor = $null; $busy.IsIndeterminate = $true; $busy.Visibility = 'Collapsed'
    if ($full -or $script:games.Count -eq 0 -or $before -ne (& $sig $script:games)) { Refresh-List }
    $cj = @(); $sj = @(); $online = ("$($script:cfg['ui:online'])" -ne 'Off')
    foreach ($g in $script:games) {
        $c = Cache-Path $g.Key; $none = "$c.none"
        $szk = "szat:$($g.Key)"; $szAt = [long]("0" + [string]$script:cfg[$szk])
        $stale = ([DateTime]::UtcNow.Ticks - $szAt) -gt [TimeSpan]::FromHours(12).Ticks
        $recent = $g.DateTicks -gt 0 -and ([DateTime]::Now.Ticks - $g.DateTicks) -lt [TimeSpan]::FromDays(3).Ticks
        if (-not $g.Size -or $g.Bytes -le 0 -or $full -or $script:forceSizes -or $stale -or $recent) { $sj += [pscustomobject]@{ Key = $g.Key; Dir = $g.Dir } }
        $needC = (-not (Test-Path $c)) -and -not ((Test-Path $none) -and ((Get-Item $none).LastWriteTime -gt (Get-Date).AddDays(-1)))
        $gk = "gen:$($g.Key)"; $needG = (-not $g.Genres) -and ("$($script:cfg[$gk])" -ne '-')
        if ($needC -or $needG) {
            $ak = "app:$($g.Key)"; $aid = "$($script:cfg[$ak])"
            $cj += [pscustomobject]@{ Key = $g.Key; Dir = $g.Dir; Term = (Get-Term $g.Name); Cache = $c; Id = $(if ($aid -match '^\d+$') { $aid }); SkipCover = (-not $needC); NeedGenres = $needG } }
    }
    if ($cj -and $online) { Start-Bg $coverSb $cj }
    if ($sj) { Start-Bg $sizeSb $sj }
    $script:forceSizes = $false
    Start-NewsCheck $full
    $status.Text = "Found $($script:games.Count) game(s). $(if ($cj -and $online) { 'Fetching cover art and genres in the background...' })"
    Save-Library
}
function Finish-Remove($i, $confirmed) {
    if (Test-Path -LiteralPath $i.Dir) {
        if (-not (Test-SafeDeleteTarget $i.Dir)) {
            Write-Log "Refused to delete protected folder: $($i.Dir)"
            Tell "Repack Shelf will not delete this folder because it looks like a system, personal or library folder:`n$($i.Dir)`n`nIf you are sure, delete it yourself in Explorer."
        } elseif ($confirmed -or (Ask "Leftover files remain in:`n$($i.Dir)`n`nDelete them? Anything stored there, such as saves or mods, will be lost.")) {
            try { Remove-GameDir $i.Dir } catch { Write-Log "Delete failed: $($_.Exception.Message)"; Tell "Could not delete everything: $($_.Exception.Message)`n`nTry running Repack Shelf as administrator." }
        }
    }
    if ($i.KeyPath -and (Test-UninstallKey $i.KeyPath) -and (Test-Path -LiteralPath $i.KeyPath)) { Remove-Item -LiteralPath $i.KeyPath -Recurse -Force -ErrorAction SilentlyContinue }
    Scan-And-Show
}
function Play {
    $g = $list.SelectedItem
    if (-not $g -or -not $g.Exe) { return }
    if (-not (Test-LocalExe $g.Exe)) { Tell 'That program is missing or is not on a local drive. Use Set .exe to choose it again.'; return }
    try { Start-Process -FilePath $g.Exe -WorkingDirectory (Split-Path $g.Exe); $status.Text = $(if ($script:hw) { "Summoned $($g.Name)... good luck." } else { "Launched $($g.Name)." }); Play-Sfx 'launch'; Flash-Lightning } catch { Tell "Could not launch: $($_.Exception.Message)" }
}

function Check-Update($manual) {
    if ($AppVersion.StartsWith('__') -or $RepoSlug.StartsWith('__')) { if ($manual) { Tell 'This is a development build, so update checking is turned off.' }; return }
    if ($manual) { $status.Text = 'Checking for updates...' }
    Start-Bg $updSb ([pscustomobject]@{ Slug = $RepoSlug; Manual = $manual }) $false
}
function Show-Update($m) {
    if (-not $m.Ok) { if ($m.Manual) { Tell 'Could not reach GitHub. Check your internet connection and try again.' }; return }
    if ("$($m.Tag)" -notmatch '^v?\d+(\.\d+){1,3}$') { return }
    # downloads must come from this repository's own release path
    $pref = "https://github.com/$RepoSlug/releases/download/"
    if ($m.Url -and -not "$($m.Url)".StartsWith($pref, [StringComparison]::OrdinalIgnoreCase)) { $m.Url = $null }
    if ($m.Sha -and -not "$($m.Sha)".StartsWith($pref, [StringComparison]::OrdinalIgnoreCase)) { $m.Sha = $null }
    if ($m.Page -and -not (Test-SafeUrl $m.Page)) { $m.Page = "https://github.com/$RepoSlug/releases" }
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
    $page = if ($m.Page) { $m.Page } else { "https://github.com/$RepoSlug/releases" }
    if (-not $m.Url -or -not $m.Sha -or $self -notmatch '(?i)\.exe$' -or $self -match '(?i)\\(powershell|pwsh|powershell_ise)\.exe$' -or $self -match '[%^&!"]') { Open-SafeUrl $page; return }
    $dir = Split-Path $self
    try { $t = Join-Path $dir '.rs_write_test'; Set-Content $t 'x' -ErrorAction Stop; Remove-Item $t -ErrorAction SilentlyContinue }
    catch { Tell "Repack Shelf cannot write to its own folder, so it cannot replace itself there.`nOpening the download page instead."; Open-SafeUrl $page; return }
    # stage in the app's private data folder under a random name, not next to the exe
    $stage = Join-Path $appDir 'update'; New-Item -ItemType Directory -Force $stage | Out-Null
    Get-ChildItem -LiteralPath $stage -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $tag = [guid]::NewGuid().ToString('N')
    $new = Join-Path $stage "RepackShelf-$tag.exe"; $shaTmp = Join-Path $stage "$tag.sha"
    if ($new -match '[%^&!"]') { Open-SafeUrl $page; return }
    $updTitle.Text = 'Downloading update...'; $updSub.Text = 'Please wait'; $btnUpd.IsEnabled = $false; $btnLater.IsEnabled = $false
    $w.Dispatcher.Invoke([action]{}, 'Render')
    try {
        $hosts = @('github.com', 'githubusercontent.com')
        Save-Capped $m.Url $new 150MB $hosts
        Save-Capped $m.Sha $shaTmp 4KB $hosts
        $want = ((Get-Content -LiteralPath $shaTmp -Raw).Trim() -split '\s+')[0].ToLower()
        if ($want -notmatch '^[0-9a-f]{64}$') { throw 'The checksum file is not valid, so the download could not be verified.' }
        if ((Get-FileHash -LiteralPath $new -Algorithm SHA256).Hash.ToLower() -ne $want) { throw 'Checksum mismatch, the download could not be verified.' }
        if ((Get-Item -LiteralPath $new).Length -lt 10KB) { throw 'The downloaded file looks too small.' }
        $fs = [IO.File]::OpenRead($new); $b1 = $fs.ReadByte(); $b2 = $fs.ReadByte(); $fs.Dispose()
        if ($b1 -ne 0x4D -or $b2 -ne 0x5A) { throw 'The downloaded file is not a Windows program.' }
        if ($script:UpdateSignerThumbprint) {
            $sig = Get-AuthenticodeSignature -LiteralPath $new
            if ($sig.Status -ne 'Valid' -or "$($sig.SignerCertificate.Thumbprint)" -ne $script:UpdateSignerThumbprint) { throw 'The update is not signed by the expected publisher.' }
        }
    } catch {
        Remove-Item -LiteralPath $new, $shaTmp -ErrorAction SilentlyContinue
        Write-Log "Update failed: $($_.Exception.Message)"
        Tell "Update failed: $($_.Exception.Message)"
        $updTitle.Text = 'Update failed'; $updSub.Text = 'Try again later'; $btnUpd.IsEnabled = $true; $btnLater.IsEnabled = $true; return
    }
    Remove-Item -LiteralPath $shaTmp -ErrorAction SilentlyContinue
    # the swap script re-checks the hash right before replacing the exe, and is written as UTF-8 so accented paths work
    $bat = Join-Path $stage "update-$tag.bat"
    $lines = @(
        '@echo off', 'chcp 65001 >nul', 'setlocal', 'set n=0', ':retry', 'set /a n+=1', 'ping -n 2 127.0.0.1 >nul', 'set "H="',
        "for /f `"skip=1 tokens=*`" %%h in ('certutil -hashfile `"$new`" SHA256') do if not defined H set `"H=%%h`"",
        'set "H=%H: =%"',
        "if /i not `"%H%`"==`"$want`" exit /b 1",
        "move /y `"$new`" `"$self`" >nul 2>&1",
        'if errorlevel 1 if %n% lss 30 goto retry',
        "start `"`" `"$self`"",
        'del "%~f0"')
    [IO.File]::WriteAllLines($bat, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
    Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -WindowStyle Hidden
    $w.Close()
}
$script:upd = $null
function Sync-Opts {
    $script:syncing = $true
    $def = @{ theme = 'Dark'; size = 'Medium'; bg = 'Solid'; anim = 'Normal'; round = 'Soft'; online = 'On'; halloween = 'On'; hwsound = 'On' }
    foreach ($pair in @(@($optHw, 'halloween'), @($optHwSound, 'hwsound'), @($optTheme, 'theme'), @($optSize, 'size'), @($optBg, 'bg'), @($optAnim, 'anim'), @($optRound, 'round'), @($optOnline, 'online'))) {
        $v = "$($script:cfg['ui:' + $pair[1]])"; if (-not $v) { $v = $def[$pair[1]] }; if ($v -eq 'On' -and $pair[1] -eq 'anim') { $v = 'Normal' }
        foreach ($rb in $pair[0].Children) { $rb.IsChecked = ($rb.Tag -eq $v) }
    }
    $acc = "$($script:cfg['ui:accent'])"; if (-not $acc) { $acc = '#60CDFF' }
    $hexBox.Text = $acc
    foreach ($b in $swatches.Children) { $b.BorderBrush = if ($b.Tag -eq $acc) { $app.Resources['UiText'] } else { [Windows.Media.Brushes]::Transparent } }
    $script:syncing = $false
}
function Opt-Changed($rb) {
    if ($script:syncing) { return }
    $k = switch ($rb.Parent.Name) { 'optTheme' { 'theme' } 'optSize' { 'size' } 'optBg' { 'bg' } 'optRound' { 'round' } 'optOnline' { 'online' } 'optHw' { 'halloween' } 'optHwSound' { 'hwsound' } default { 'anim' } }
    $script:cfg["ui:$k"] = $rb.Tag; Save-Cfg; Apply-Theme; Fade $w.Content 0.9 240
    if ($k -eq 'size') { $list.UpdateLayout(); Animate-In }
    if ($k -eq 'halloween' -and $rb.Tag -eq 'On') { Play-Sfx 'ghost'; Flash-Lightning }
    if ($k -eq 'online' -and $rb.Tag -eq 'On') { Scan-And-Show }
}
function Show-Settings { Sync-Opts; Play-Sfx 'creak'; $settings.Visibility = 'Visible'; Anim-Slide $settings 'x' 380 380 }
function Hide-Settings {
    if (-not $script:animOn) { $settings.Visibility = 'Collapsed'; return }
    $tt = New-Object Windows.Media.TranslateTransform; $settings.RenderTransform = $tt
    $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(260)); $ea = New-Object Windows.Media.Animation.CubicEase; $ea.EasingMode = 'EaseIn'
    $b = New-Object Windows.Media.Animation.DoubleAnimation 0, 380, $dur; $b.EasingFunction = $ea
    $b.Add_Completed({ $settings.Visibility = 'Collapsed' })
    $tt.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $b)
}
# ---------- storage dashboard ----------
$script:storSel = @{}; $script:storFreedTb = $null; $script:storDirty = $false
function Get-DriveInfo2($root) {
    try { $di = New-Object IO.DriveInfo $root; if ($di.IsReady -and $di.TotalSize -gt 0) { return [pscustomobject]@{ Total = [long]$di.TotalSize; Free = [long]$di.AvailableFreeSpace } } } catch {}
    $null
}
function Test-LowDisk($info) { [bool]($info -and (($info.Free -lt 15GB) -or (($info.Free / [double]$info.Total) -lt 0.10))) }
function Get-LowDrives {
    $out = @()
    foreach ($r in @($script:games | ForEach-Object { try { [IO.Path]::GetPathRoot($_.Dir).ToUpper() } catch {} } | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-LowDisk (Get-DriveInfo2 $r)) { $out += $r }
    }
    $out
}
function New-StorText($text, $size = 13.5, $muted = $false, $bold = $false) {
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $text; $t.FontSize = $size; $t.TextTrimming = 'CharacterEllipsis'
    if ($bold) { $t.FontWeight = 'SemiBold' }
    if ($muted) { $t.Tag = 'm' }
    $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($muted) { 'UiMuted' } else { 'UiText' }))
    $t
}
function New-StorLabel($text) { $t = New-StorText $text 11.5 $true $true; $t.Margin = [Windows.Thickness]::new(0, 18, 0, 8); $t }
function New-StorRow($left, $right, $leftBold = $false) {
    $g = New-Object Windows.Controls.Grid
    $c0 = New-Object Windows.Controls.ColumnDefinition; $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = [Windows.GridLength]::Auto
    [void]$g.ColumnDefinitions.Add($c0); [void]$g.ColumnDefinitions.Add($c1)
    $a = New-StorText $left 13.5 $false $leftBold
    $b = New-StorText $right 13 $true; $b.Margin = [Windows.Thickness]::new(10, 0, 0, 0)
    [Windows.Controls.Grid]::SetColumn($b, 1)
    [void]$g.Children.Add($a); [void]$g.Children.Add($b)
    $g
}
function New-StorCard($child) {
    $c = New-Object Windows.Controls.Border; $c.CornerRadius = [Windows.CornerRadius]::new(8); $c.Padding = [Windows.Thickness]::new(12, 10, 12, 10); $c.Margin = [Windows.Thickness]::new(0, 0, 0, 8)
    $c.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'UiCard'); $c.Child = $child; $c
}
function New-StorBar($value, $max) {
    $p = New-Object Windows.Controls.ProgressBar; $p.Height = 6; $p.Minimum = 0; $p.Maximum = [Math]::Max([double]$max, 1); $p.Value = [Math]::Min([double]$value, $p.Maximum)
    $p.BorderThickness = [Windows.Thickness]::new(0); $p.Margin = [Windows.Thickness]::new(0, 8, 0, 6)
    $p.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'UiPanel2'); $p.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'UiAccent')
    $p
}
function Set-StorRowState($row, $on) {
    $row.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $(if ($on) { 'UiAccent' } else { 'UiCard' }))
    foreach ($tb in $row.Child.Children) { $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($on) { 'UiAccentFg' } elseif ($tb.Tag -eq 'm') { 'UiMuted' } else { 'UiText' })) }
}
function Update-StorFreed {
    if (-not $script:storFreedTb) { return }
    $sel = @($script:games | Where-Object { $script:storSel.ContainsKey($_.Key) })
    $sum = [long](($sel | Measure-Object Bytes -Sum).Sum)
    $script:storFreedTb.Text = if ($sel.Count) { "Uninstalling the $($sel.Count) selected game(s) would free about $(Fmt $sum)." } else { 'Select games above to see how much space uninstalling them would free.' }
}
function Build-Storage {
    $storBody.Children.Clear()
    $games = @($script:games)
    $sized = @($games | Where-Object { $_.Bytes -gt 0 })
    $pending = $games.Count - $sized.Count
    $total = [long](($sized | Measure-Object Bytes -Sum).Sum)
    [void]$storBody.Children.Add((New-StorText (Fmt $total) 30 $false $true))
    $sub = New-StorText ("across $($games.Count) game(s)" + $(if ($pending) { " - $pending still calculating" } else { '' })) 13 $true; $sub.Margin = [Windows.Thickness]::new(0, 2, 0, 0)
    [void]$storBody.Children.Add($sub)

    [void]$storBody.Children.Add((New-StorLabel 'BY DRIVE'))
    $groups = @($sized | Group-Object { try { [IO.Path]::GetPathRoot($_.Dir).ToUpper() } catch { '?' } } | Sort-Object { ($_.Group | Measure-Object Bytes -Sum).Sum } -Descending)
    if (-not $groups) { [void]$storBody.Children.Add((New-StorText $(if ($pending) { 'Sizes are still being calculated...' } else { 'No games yet.' }) 13 $true)) }
    foreach ($gr in $groups) {
        $used = [long](($gr.Group | Measure-Object Bytes -Sum).Sum)
        $info = Get-DriveInfo2 $gr.Name
        $st = New-Object Windows.Controls.StackPanel
        [void]$st.Children.Add((New-StorRow $gr.Name "$($gr.Count) game(s)" $true))
        if ($info) {
            [void]$st.Children.Add((New-StorBar $used $info.Total))
            [void]$st.Children.Add((New-StorText "Games $(Fmt $used) - $(Fmt $info.Free) free of $(Fmt $info.Total)" 12.5 $true))
            if (Test-LowDisk $info) {
                $warn = New-Object Windows.Controls.Border; $warn.CornerRadius = [Windows.CornerRadius]::new(6); $warn.Padding = [Windows.Thickness]::new(10, 6, 10, 6); $warn.Margin = [Windows.Thickness]::new(0, 8, 0, 0); $warn.Background = New-Brush '#C42B1C'
                $wt = New-Object Windows.Controls.TextBlock; $wt.Text = "Low disk space: only $(Fmt $info.Free) free on this drive."; $wt.Foreground = [Windows.Media.Brushes]::White; $wt.FontSize = 12.5; $wt.TextWrapping = 'Wrap'
                $warn.Child = $wt; [void]$st.Children.Add($warn)
            }
        } else { [void]$st.Children.Add((New-StorText "Games $(Fmt $used)" 12.5 $true)) }
        [void]$storBody.Children.Add((New-StorCard $st))
    }

    [void]$storBody.Children.Add((New-StorLabel 'LARGEST GAMES - CLICK TO SELECT'))
    $top = @($sized | Sort-Object Bytes -Descending | Select-Object -First 12)
    $keep = @{}; foreach ($g in $top) { if ($script:storSel.ContainsKey($g.Key)) { $keep[$g.Key] = 1 } }; $script:storSel = $keep
    foreach ($g in $top) {
        $row = New-StorCard (New-StorRow $g.Name (Fmt $g.Bytes)); $row.Tag = $g.Key; $row.Cursor = 'Hand'; $row.Margin = [Windows.Thickness]::new(0, 0, 0, 6)
        Set-StorRowState $row $script:storSel.ContainsKey($g.Key)
        $row.Add_MouseLeftButtonUp({
            $r = $args[0]; $k = [string]$r.Tag
            if ($script:storSel.ContainsKey($k)) { $script:storSel.Remove($k) } else { $script:storSel[$k] = 1 }
            Set-StorRowState $r $script:storSel.ContainsKey($k); Update-StorFreed
        })
        [void]$storBody.Children.Add($row)
    }
    $tb = New-StorText '' 13.5; $tb.TextTrimming = 'None'; $tb.TextWrapping = 'Wrap'; $tb.Margin = [Windows.Thickness]::new(0, 10, 0, 0); $script:storFreedTb = $tb
    [void]$storBody.Children.Add($tb); Update-StorFreed
    $note = New-StorText 'Nothing is deleted from here. Use "Uninstall completely" on a game to remove it.' 12 $true; $note.TextTrimming = 'None'; $note.TextWrapping = 'Wrap'; $note.Margin = [Windows.Thickness]::new(0, 6, 0, 0)
    [void]$storBody.Children.Add($note)
}
function Show-Storage { Build-Storage; Play-Sfx 'creak'; $storage.Visibility = 'Visible'; Anim-Slide $storage 'x' 380 380 }
function Hide-Storage {
    if (-not $script:animOn) { $storage.Visibility = 'Collapsed'; return }
    $tt = New-Object Windows.Media.TranslateTransform; $storage.RenderTransform = $tt
    $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(260)); $ea = New-Object Windows.Media.Animation.CubicEase; $ea.EasingMode = 'EaseIn'
    $b = New-Object Windows.Media.Animation.DoubleAnimation 0, 380, $dur; $b.EasingFunction = $ea
    $b.Add_Completed({ $storage.Visibility = 'Collapsed' })
    $tt.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $b)
}
foreach ($hex in $Accents) {
    $b = New-Object Windows.Controls.Button; $b.Style = $app.Resources['Swatch']; $b.Background = New-Brush $hex; $b.Tag = $hex; $b.ToolTip = $hex
    $b.Add_Click({ $script:cfg['ui:accent'] = $args[0].Tag; Save-Cfg; Apply-Theme; Sync-Opts })
    [void]$swatches.Children.Add($b)
}
foreach ($p in $optHw, $optHwSound, $optTheme, $optSize, $optBg, $optAnim, $optRound, $optOnline) { foreach ($rb in $p.Children) { $rb.Add_Checked({ Opt-Changed $args[0] }) } }
$btnCustom.Add_Click({ if ($storage.Visibility -eq 'Visible') { Hide-Storage; Show-Settings } elseif ($settings.Visibility -eq 'Visible') { Hide-Settings } else { Show-Settings } })
$btnStor.Add_Click({ Hide-Settings; Show-Storage })
$btnCloseStor.Add_Click({ Hide-Storage })
$btnCloseSet.Add_Click({ Hide-Settings })
$btnHex.Add_Click({
    $h = $hexBox.Text.Trim(); if ($h -notmatch '^#') { $h = "#$h" }
    if ($h -notmatch '^#[0-9A-Fa-f]{6}$') { Tell 'Enter a colour like #60CDFF (six hex digits).'; return }
    $script:cfg['ui:accent'] = $h.ToUpper(); Save-Cfg; Apply-Theme; Sync-Opts
})
$btnReset.Add_Click({
    foreach ($k in 'ui:theme', 'ui:accent', 'ui:size', 'ui:bg', 'ui:anim', 'ui:round', 'ui:online', 'ui:halloween', 'ui:hwsound') { $script:cfg.Remove($k) }
    Save-Cfg; Apply-Theme; Sync-Opts; Fade $w.Content 0.9 240
})

$pump = New-Object Windows.Threading.DispatcherTimer; $pump.Interval = [TimeSpan]::FromMilliseconds(400)
$pump.Add_Tick({
    $m = $null
    while ($script:q.TryDequeue([ref]$m)) {
        if ($m.T -eq 'update') { Show-Update $m; continue }
        $g = $script:byKey[$m.K]; if (-not $g) { continue }
        if ($m.T -eq 'cover') { $g.Cover = Load-Img $m.V; if ($m.Id) { $script:cfg["app:$($m.K)"] = "$($m.Id)" } }
        elseif ($m.T -eq 'size') { $g.Bytes = [long]$m.V; $g.Size = Fmt $m.V; $script:storDirty = $true; $script:cfg["szat:$($m.K)"] = "$([DateTime]::UtcNow.Ticks)"; $script:cfgDirty = $true }
        elseif ($m.T -eq 'genre') {
            if ($m.Id) { $script:cfg["app:$($m.K)"] = "$($m.Id)" }
            if ($null -ne $m.V) { $gv = "$($m.V)"; $script:cfg["gen:$($m.K)"] = $(if ($gv) { $gv } else { '-' }); if ($gv) { $g.Genres = $gv; $script:genDirty = $true } }
        }
        elseif ($m.T -eq 'news') {
            if ($m.Ok) {
                $script:cfg["newschk:$($m.K)"] = "$([DateTime]::UtcNow.Ticks)"; $script:cfgDirty = $true
                $script:cfg["nd:$($m.K)"] = "$($m.Date)"; $script:cfg["nt:$($m.K)"] = "$($m.Title)"; $script:cfg["nu:$($m.K)"] = "$($m.Url)"
                $g.NewsDate = [long]$m.Date; $g.NewsTitle = "$($m.Title)"; $g.NewsUrl = "$($m.Url)"; Set-UpdState $g; $script:updDirty = $true
            }
        }
        else { $script:miss++ }
    }
    if ($script:storDirty) { $script:storDirty = $false; if ($storage.Visibility -eq 'Visible') { Build-Storage } }
    if ($script:updDirty) { $script:updDirty = $false; Refresh-UpdChip; if ($script:updOnly) { Refresh-List $true } }
    if ($script:genDirty) { $script:genDirty = $false; Rebuild-Cats; if ($script:genres.Count) { Refresh-List $true } }
    $run = @($script:bg | Where-Object { -not $_.H.IsCompleted }).Count -gt 0
    if (-not $script:scanning) { $busy.Visibility = if ($run) { 'Visible' } else { 'Collapsed' } }
    if (-not $run -and $script:bg.Count -gt 0 -and -not $script:doneMsg) {
        $script:doneMsg = $true; $script:cfgDirty = $false; Save-Cfg; Save-Library; if ($script:sort -eq 'Size') { Refresh-List $true }
        $status.Text = if ($script:miss) { "No cover found for $($script:miss) game(s). Select one and use Find cover online." } else { 'Covers, genres and update info loaded.' }
        $low = @(Get-LowDrives); if ($low) { $status.Text += "  Low disk space on $($low -join ', ')." }
        Start-NewsCheck $false
    }
    elseif (-not $run -and $script:cfgDirty) { $script:cfgDirty = $false; Save-Cfg }
    Reap-Bg
})
$pump.Start()

$list.Add_SelectionChanged({
    $g = $list.SelectedItem
    if (-not $g) { return }
    $detail.DataContext = $g; $empty.Visibility = 'Collapsed'; $detail.Visibility = 'Visible'
    $btnPlay.IsEnabled = [bool]$g.Exe
    $btnNotes.Content = if ($g.HasUpd -and $g.NewsUrl) { 'Read latest patch notes' } elseif ("$($script:cfg['app:' + $g.Key])" -match '^\d+$') { 'Official patch notes (Steam)' } else { 'Find on Steam' }
    $btnSeen.Visibility = if ($g.HasUpd) { 'Visible' } else { 'Collapsed' }
    $btnUn.Content = if ($g.UnExe -or $g.KeyPath) { 'Uninstall completely' } else { 'Delete game folder' }
    Anim-Slide $detail 'x' 28 330; Stagger-Detail
    if ($list.IsMouseOver -or $list.IsKeyboardFocusWithin) { Play-Sfx 'select' }
})
$list.Add_MouseDoubleClick({ Play })
$script:searchTimer = New-Object Windows.Threading.DispatcherTimer; $script:searchTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$script:searchTimer.Add_Tick({ $script:searchTimer.Stop(); Refresh-List $true })
$search.Add_TextChanged({ $ph.Visibility = if ($search.Text) { 'Collapsed' } else { 'Visible' }; $script:searchTimer.Stop(); $script:searchTimer.Start() })
foreach ($rb in $chips.Children) { if ($rb -is [Windows.Controls.RadioButton]) { $rb.Add_Checked({ $script:filter = $args[0].Tag; Refresh-List }) } }
$script:tplGrid = $list.ItemTemplate; $script:panelGrid = $list.ItemsPanel
function Set-View($v) {
    $script:view = $v
    if ($v -eq 'List') { $list.ItemsPanel = $app.Resources['PanelStack']; $list.ItemTemplate = $app.Resources['TplList'] }
    else { $list.ItemsPanel = $script:panelGrid; $list.ItemTemplate = $script:tplGrid }
    $list.UpdateLayout(); Animate-In
}
function Init-Toolbar {
    $s = "$($script:cfg['ui:sort'])"; if (@('Name', 'Size', 'Date') -notcontains $s) { $s = 'Name' }
    $script:sort = $s
    $vw = "$($script:cfg['ui:view'])"; if ($vw -ne 'List') { $vw = 'Grid' }
    $script:syncing = $true
    foreach ($rb in $sortChips.Children) { $rb.IsChecked = ($rb.Tag -eq $s) }
    foreach ($rb in $viewChips.Children) { $rb.IsChecked = ($rb.Tag -eq $vw) }
    $script:syncing = $false
    if ($vw -eq 'List') { Set-View 'List' }
}
function Update-GenreBtn {
    $n = @($script:genres).Count
    $genreBtn.Content = if ($n) { "Genre ($n)" } else { 'Genre' }; $genreBtn.IsChecked = ($n -gt 0)
}
function Refresh-UpdChip {
    $n = @($script:games | Where-Object { $_.HasUpd }).Count
    if ($n -eq 0) { $script:updOnly = $false; $updChip.IsChecked = $false }
    $updChip.Content = "Updates ($n)"; $updChip.Visibility = if ($n -gt 0) { 'Visible' } else { 'Collapsed' }
}
function Rebuild-Cats {
    $script:syncing = $true
    $freq = @{}
    foreach ($g in $script:games) { foreach ($n in @("$($g.Genres)" -split ',')) { if ($n) { $freq[$n] = 1 + [int]$freq[$n] } } }
    $script:genres = @($script:genres | Where-Object { $freq.ContainsKey($_) })
    $catChips.Children.Clear()
    foreach ($n in @($freq.Keys | Sort-Object @{ Expression = { -$freq[$_] } }, @{ Expression = { $_ } })) {
        $tb = New-Object Windows.Controls.Primitives.ToggleButton
        $tb.Content = "$n ($($freq[$n]))"; $tb.Tag = $n; $tb.Style = $app.Resources['ToggleChip']; $tb.Margin = [Windows.Thickness]::new(0, 0, 6, 8)
        $tb.IsChecked = ($script:genres -contains $n)
        $tb.Add_Click({
            $t = "$($args[0].Tag)"
            if ($args[0].IsChecked) { $script:genres = @($script:genres + $t) } else { $script:genres = @($script:genres | Where-Object { $_ -ne $t }) }
            Update-GenreBtn; Refresh-List
        })
        [void]$catChips.Children.Add($tb)
    }
    $genreBtn.Visibility = if ($freq.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    Update-GenreBtn
    $script:syncing = $false
}
foreach ($rb in $sortChips.Children) { $rb.Add_Checked({ if ($script:syncing) { return }; $script:sort = $args[0].Tag; $script:cfg['ui:sort'] = $script:sort; Save-Cfg; Refresh-List }) }
foreach ($rb in $viewChips.Children) { $rb.Add_Checked({ if ($script:syncing) { return }; $script:cfg['ui:view'] = $args[0].Tag; Save-Cfg; Set-View $args[0].Tag }) }
$favChip.Add_Click({ $script:favOnly = [bool]$favChip.IsChecked; Refresh-List })
$updChip.Add_Click({ $script:updOnly = [bool]$updChip.IsChecked; Refresh-List })
$script:popT = @{ more = (Get-Date).AddMinutes(-1); genre = (Get-Date).AddMinutes(-1) }
$genrePop.Add_Closed({ $script:popT['genre'] = Get-Date })
$morePop.Add_Closed({ $script:popT['more'] = Get-Date })
$genreBtn.Add_Click({ Update-GenreBtn; if (((Get-Date) - $script:popT['genre']).TotalMilliseconds -gt 300) { $genrePop.IsOpen = $true } })
$btnMore.Add_Click({ if (((Get-Date) - $script:popT['more']).TotalMilliseconds -gt 300) { $morePop.IsOpen = $true } })
$genreClear.Add_Click({ $script:genres = @(); Rebuild-Cats; Refresh-List })
foreach ($b in $btnNotes, $btnExe, $btnFind, $btnCover, $btnUn, $btnSeen) { $b.Add_Click({ $morePop.IsOpen = $false }) }
$btnSeen.Add_Click({
    $g = $list.SelectedItem; if (-not $g) { return }
    $script:cfg["seen:$($g.Key)"] = "$($g.NewsDate)"; Save-Cfg; Set-UpdState $g
    $btnSeen.Visibility = 'Collapsed'; $btnNotes.Content = 'Official patch notes (Steam)'; Refresh-UpdChip
    if ($script:updOnly) { Refresh-List $true }
})
function Save-Fav($g) {
    if (-not $g) { return }
    $k = "fav:$($g.Key)"; if ($g.Fav) { $script:cfg[$k] = $true; Play-Sfx 'fav' } else { $script:cfg.Remove($k) }
    Save-Cfg
    if ($script:favOnly) { Refresh-List $true }
}
$list.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    $b = $args[1].OriginalSource
    if ($b -is [Windows.Controls.Primitives.ToggleButton] -and "$($b.Tag)" -eq 'heart') { $args[1].Handled = $true; Save-Fav $b.DataContext }
})
$btnNotes.Add_Click({
    $g = $list.SelectedItem; if (-not $g) { return }
    $k = "app:$($g.Key)"; $id = "$($script:cfg[$k])"
    $hub = if ($id -match '^\d+$') { "https://store.steampowered.com/news/app/$id" } else { 'https://store.steampowered.com/search/?term=' + [uri]::EscapeDataString((Get-Term $g.Name)) }
    if ($g.HasUpd -and $g.NewsUrl) { Open-SafeUrl $g.NewsUrl $hub } else { Open-SafeUrl $hub }
})
$btnScan.ToolTip = 'Click: quick refresh. Shift+click: full rescan.'
$btnScan.Add_Click({ Play-Sfx 'thunder'; Flash-Lightning; $script:forceSizes = $true; Scan-And-Show (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift) -ne 0) })
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
        if ($d.ShowDialog() -eq 'OK') {
            $sp = "$($d.SelectedPath)"
            if (-not (Test-LocalPath $sp) -or $sp.TrimEnd('\').Length -le 2) { Tell 'Pick a folder on a local drive. A whole drive or a network location is not allowed.' }
            else { $script:cfg['folders'] = @($cur + $sp | Select-Object -Unique); Save-Cfg; Scan-And-Show }
        }
    } elseif ($r -eq 'No') { $script:cfg['folders'] = @(); Save-Cfg; Scan-And-Show }
})
$btnUn.Add_Click({
    $i = $list.SelectedItem
    if ($i.UnExe -and (Test-LocalPath $i.UnExe) -and (Test-Path -LiteralPath $i.UnExe)) {
        $warn = if (Test-InnoUninstaller $i.UnExe) { '' } else { "`n`nWARNING: this file does not look like a genuine Inno Setup uninstaller. Running it runs whatever the file contains." }
        if (-not (Ask "Uninstall $($i.Name)?`n`nUninstaller: $($i.UnExe)$warn`n`nIts own uninstaller runs first, then leftover files in`n$($i.Dir)`ncan be removed. Save games outside that folder are not touched.")) { return }
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
    } elseif (-not (Test-SafeDeleteTarget $i.Dir)) { Tell "$($i.Name) has no uninstaller, and Repack Shelf will not delete this folder because it looks like a system, personal or library folder:`n$($i.Dir)"
    } elseif (Ask "$($i.Name) has no uninstaller.`n`nPermanently delete its folder ($(Fmt (Get-DirSize $i.Dir)))?`n$($i.Dir)`n`nAnything stored inside, such as saves or mods, will be lost.") { Finish-Remove $i $true }
})

# ---------- smooth wheel scrolling ----------
function Find-ScrollViewer($el) {
    if ($el -is [Windows.Controls.ScrollViewer]) { return $el }
    for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($el); $i++) {
        $r = Find-ScrollViewer ([Windows.Media.VisualTreeHelper]::GetChild($el, $i)); if ($r) { return $r }
    }
    $null
}
$script:scrollT = 0.0; $script:scrollC = 0.0; $script:scrollSV = $null
$script:scrollTimer = New-Object Windows.Threading.DispatcherTimer; $script:scrollTimer.Interval = [TimeSpan]::FromMilliseconds(15)
$script:scrollTimer.Add_Tick({
    $sv = $script:scrollSV; if (-not $sv) { $args[0].Stop(); return }
    $script:scrollT = [Math]::Max(0, [Math]::Min($sv.ScrollableHeight, $script:scrollT))
    $d = $script:scrollT - $script:scrollC
    if ([Math]::Abs($d) -lt 0.5) { $script:scrollC = $script:scrollT; $args[0].Stop() }
    else { $script:scrollC += $d * [Math]::Min(0.5, 0.18 / $script:animK) }
    $sv.ScrollToVerticalOffset($script:scrollC)
})
$list.Add_PreviewMouseWheel({
    if (-not $script:animOn) { return }
    $sv = Find-ScrollViewer $list; if (-not $sv -or $sv.ScrollableHeight -le 0) { return }
    if (-not $script:scrollTimer.IsEnabled) { $script:scrollC = $sv.VerticalOffset; $script:scrollT = $sv.VerticalOffset }
    $script:scrollSV = $sv
    $script:scrollT = [Math]::Max(0, [Math]::Min($sv.ScrollableHeight, $script:scrollT - $args[1].Delta * 0.9))
    $args[1].Handled = $true; $script:scrollTimer.Start()
})

# ---------- fade out on close ----------
$script:closing = $false
$w.Add_Closing({
    if ($script:closing -or -not $script:animOn) { return }
    $args[1].Cancel = $true; $script:closing = $true
    $fa = New-Object Windows.Media.Animation.DoubleAnimation 1, 0, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(180)))
    $fa.Add_Completed({ $w.Close() })
    $w.BeginAnimation([Windows.UIElement]::OpacityProperty, $fa)
})

$w.Add_SourceInitialized({ Set-TitleBar })
$w.Add_ContentRendered({ if (-not $script:started) { $script:started = $true
    $n = 0; foreach ($c in $w.Content.Children[0].Children) { Anim-Slide $c 'y' -14 420 ($n * 70); $n++ }
    Init-Toolbar
    Update-Halloween; Play-Sfx 'boot'; Flash-Lightning
    Load-Library
    Rebuild-Cats; Refresh-UpdChip
    if ($script:games.Count) { Refresh-List; $status.Text = "Loaded $($script:games.Count) game(s). Checking for changes..."; $w.Dispatcher.Invoke([action]{}, 'Render') }
    Scan-And-Show; Check-Update $false } })
[void]$w.ShowDialog()
try { $script:mutex.ReleaseMutex() } catch {}
