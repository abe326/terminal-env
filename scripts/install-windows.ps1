<#
terminal-env の Windows 側を、管理者権限なしで入れる。何度実行してもよい(済んでいるものは飛ばす)。
Windows に最初から入っている PowerShell 5.1 で動く。

  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-windows.ps1          入れる・つなぐ
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-windows.ps1 -Check   確かめるだけ(何も変えない。足りなければ終了コード 1)

入れるもの(すべて自分のユーザーだけに。公式の配布物を、下に書いた sha256 で照合してから使う):
  - WezTerm(公式の zip 版)→ %LOCALAPPDATA%\Programs\WezTerm。既に PATH にあれば入れない
  - Neovim(公式の zip 版)→ %LOCALAPPDATA%\Programs\Neovim。既に PATH にあれば入れない
  - スタートメニューの WezTerm(Windows の通知を出すための登録つき。zip 版を入れたときだけ)
  - UDEV Gothic NF(公式の zip の 35NF の 4 本)→ 自分のフォント。既に入っていれば入れない
つなぐもの:
  - ユーザー環境変数 WEZTERM_CONFIG_FILE → このリポジトリの wezterm\wezterm.lua
  - %LOCALAPPDATA%\nvim → このリポジトリの nvim(ジャンクション。既にあれば nvim.bk_<日時> に名前を変えて残す)
  - wezterm\local.lua(無ければ local.example.lua を写す)
  - Neovim のプラグイン(初回の起動で lazy-lock.json の版が入る。Git が要る)
入れないもの: Git・ripgrep・lazygit(winget で入れる)、Claude Code の hook(README の手順)
#>
param([switch]$Check)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# 版と sha256(各リリースページに出ている値)。版を上げるときはここを書き換える
$WezTerm = @{ Version = '20240203-110809-5046fc22'; Sha256 = '57e5d03b585303d81e8b8e96d1230362852eb39aca92b3b29c7a42cfb82f9ac4' }
$Neovim  = @{ Version = 'v0.12.6'; Sha256 = '4e12b7103b601ffc8f25954b4da100f339faa73dccb69a5b135e897fa3d893ed' }
$Font    = @{ Version = 'v2.2.0'; Sha256 = '45faeef7b5d8bc591bcc5887a2ca0c5fb9028066f18a5a52cd6f10b7d655ba37' }

$Repo       = Split-Path -Parent $PSScriptRoot
$Apps       = Join-Path $env:LOCALAPPDATA 'Programs'
$WezTermDir = Join-Path $Apps 'WezTerm'
$NeovimDir  = Join-Path $Apps 'Neovim'
$ConfigFile = Join-Path $Repo 'wezterm\wezterm.lua'
$LocalLua   = Join-Path $Repo 'wezterm\local.lua'
$NvimSrc    = Join-Path $Repo 'nvim'
$NvimLink   = Join-Path $env:LOCALAPPDATA 'nvim'
$FontDir    = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$FontKey    = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$FontFiles  = @('UDEVGothic35NF-Regular.ttf', 'UDEVGothic35NF-Bold.ttf', 'UDEVGothic35NF-Italic.ttf', 'UDEVGothic35NF-BoldItalic.ttf')
$Shortcut   = Join-Path ([Environment]::GetFolderPath('Programs')) 'WezTerm.lnk'
# WezTerm が自分の通知に付ける名前(公式のインストーラがスタートメニューに登録するものと同じ)
$AppId      = 'org.wezfurlong.wezterm'
$Stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Missing = 0

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
namespace TenvSetup {
  [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder f, int cch, IntPtr fd, uint flags);
    void GetIDList(out IntPtr pidl);
    void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder s, int cch);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string s);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder s, int cch);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string s);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder s, int cch);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string s);
    void GetHotkey(out short k);
    void SetHotkey(short k);
    void GetShowCmd(out int c);
    void SetShowCmd(int c);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder s, int cch, out int i);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string s, int i);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string s, uint r);
    void Resolve(IntPtr hwnd, uint flags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string s);
  }
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore {
    void GetCount(out uint n);
    void GetAt(uint i, out PropertyKey k);
    void GetValue(ref PropertyKey k, IntPtr pv);
    void SetValue(ref PropertyKey k, ref PropVariant pv);
    void Commit();
  }
  [StructLayout(LayoutKind.Sequential, Pack = 4)]
  struct PropertyKey { public Guid fmtid; public uint pid; }
  // PROPVARIANT(64 ビットでは 24 バイト)。使うのは文字列(VT_LPWSTR)だけ
  [StructLayout(LayoutKind.Explicit, Size = 24)]
  struct PropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }
  [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
  class CShellLink {}

  public static class Native {
    // スタートメニューのショートカット。AppUserModelID を付けると、その名前の通知が Windows に表示される
    public static void CreateShortcut(string lnk, string target, string workdir, string appId) {
      var link = (IShellLinkW)new CShellLink();
      link.SetPath(target);
      link.SetWorkingDirectory(workdir);
      link.SetIconLocation(target, 0);
      var store = (IPropertyStore)link;
      var key = new PropertyKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
      var pv = new PropVariant { vt = 31, p = Marshal.StringToCoTaskMemUni(appId) };
      try { store.SetValue(ref key, ref pv); store.Commit(); }
      finally { Marshal.FreeCoTaskMem(pv.p); }
      ((IPersistFile)link).Save(lnk, true);
    }

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    static extern int AddFontResourceW(string file);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessageTimeoutW(IntPtr hwnd, uint msg, IntPtr w, string l, uint flags, uint timeout, out IntPtr result);
    static readonly IntPtr HWND_BROADCAST = new IntPtr(0xffff);

    // 入れたフォントを、サインインし直さなくても使えるようにする
    public static void LoadFont(string file) {
      IntPtr r;
      AddFontResourceW(file);
      SendMessageTimeoutW(HWND_BROADCAST, 0x001D, IntPtr.Zero, null, 2, 1000, out r);
    }
    // 環境変数を変えたことを知らせる(この後に起動するアプリが新しい値を読む)
    public static void BroadcastEnvironment() {
      IntPtr r;
      SendMessageTimeoutW(HWND_BROADCAST, 0x001A, IntPtr.Zero, "Environment", 2, 5000, out r);
    }
  }
}
'@

function Say([string]$state, [string]$msg) {
  $color = @{ ok = 'Green'; skip = 'DarkGray'; done = 'Cyan'; todo = 'Yellow'; ng = 'Red' }[$state]
  Write-Host ('[{0,-4}] {1}' -f $state, $msg) -ForegroundColor $color
  if ($state -in 'todo', 'ng') { $script:Missing++ }
}

function Find-Exe([string]$name) {
  $c = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return $null
}

function Same-Path([string]$a, [string]$b) {
  return ($a.TrimEnd('\') -ieq $b.TrimEnd('\'))
}

# 公式の配布物を取ってきて sha256 を照合し、zip の中のフォルダの中身を $dest に置く
function Install-Zip([string]$url, [string]$sha256, [string]$inner, [string]$dest, [string]$version) {
  $tmp = Join-Path $env:TEMP ('tenv-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'a.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    $got = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($got -ne $sha256.ToUpperInvariant()) { throw "sha256 が合いません($url)。期待 $sha256 / 実際 $got" }
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp
    if (Test-Path -LiteralPath $dest) {
      # 前の版は消さずに名前を変えて残す(使っている最中だと失敗するので、そのときは閉じてからやり直す)
      Rename-Item -LiteralPath $dest -NewName ((Split-Path -Leaf $dest) + '.bk_' + $Stamp)
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Move-Item -LiteralPath (Join-Path $tmp $inner) -Destination $dest
    Set-Content -LiteralPath (Join-Path $dest '.tenv-version') -Value $version -Encoding ascii
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Installed-Version([string]$dir) {
  $f = Join-Path $dir '.tenv-version'
  if (Test-Path -LiteralPath $f) { return (Get-Content -LiteralPath $f -TotalCount 1).Trim() }
  return $null
}

# ユーザーの PATH に足す(%USERPROFILE% などの書き方を壊さないよう、展開せずに読んで書く)
function Add-UserPath([string]$dir) {
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
  try {
    $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $parts = @($raw -split ';' | Where-Object { $_ -ne '' })
    foreach ($p in $parts) {
      if (Same-Path ([Environment]::ExpandEnvironmentVariables($p)) $dir) { return $false }
    }
    $key.SetValue('Path', (($parts + $dir) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
  } finally { $key.Close() }
  $env:Path = $env:Path.TrimEnd(';') + ';' + $dir
  return $true
}

function Step-App([string]$label, [string]$exe, [string]$dir, [string]$exeInDir, $spec, [string]$url, [string]$inner) {
  $found = Find-Exe $exe
  $ours = Join-Path $dir $exeInDir
  if ($found -and -not (Same-Path (Split-Path -Parent $found) (Split-Path -Parent $ours))) {
    Say skip "$label は既に入っている($found)。それを使う"
    return $false
  }
  if ((Installed-Version $dir) -eq $spec.Version) {
    Say ok "$label $($spec.Version)($dir)"
  } elseif ($Check) {
    Say todo "$label $($spec.Version) が入っていない"
    return $false
  } else {
    Install-Zip $url $spec.Sha256 $inner $dir $spec.Version
    Say done "$label $($spec.Version) を入れた($dir)"
  }
  $binDir = Split-Path -Parent $ours
  if ($Check) {
    if (-not $found) { Say todo "$label の場所($binDir)がユーザーの PATH に無い" }
  } elseif (Add-UserPath $binDir) {
    Say done "ユーザーの PATH に足した($binDir)"
  }
  return $true
}

Write-Host "terminal-env の Windows 側($Repo)" -ForegroundColor White
if (-not (Test-Path -LiteralPath $ConfigFile)) { throw "このリポジトリの中の scripts\install-windows.ps1 として実行してください($ConfigFile が無い)" }

# 1. WezTerm
$wzBase = "https://github.com/wezterm/wezterm/releases/download/$($WezTerm.Version)"
$ourWezTerm = Step-App 'WezTerm' 'wezterm-gui.exe' $WezTermDir 'wezterm-gui.exe' $WezTerm `
  "$wzBase/WezTerm-windows-$($WezTerm.Version).zip" "WezTerm-windows-$($WezTerm.Version)"

# 2. スタートメニューの WezTerm(zip 版を使うときだけ。通知を出すのに要る)
if ($ourWezTerm) {
  if (Test-Path -LiteralPath $Shortcut) {
    Say ok "スタートメニューの WezTerm($Shortcut)"
  } elseif ($Check) {
    Say todo 'スタートメニューの WezTerm が無い(Windows の通知が出ない)'
  } else {
    [TenvSetup.Native]::CreateShortcut($Shortcut, (Join-Path $WezTermDir 'wezterm-gui.exe'), $env:USERPROFILE, $AppId)
    Say done "スタートメニューに WezTerm を作った(タスクバーへのピン留めはここから)"
  }
}

# 3. Neovim
$nvBase = "https://github.com/neovim/neovim/releases/download/$($Neovim.Version)"
[void](Step-App 'Neovim' 'nvim.exe' $NeovimDir 'bin\nvim.exe' $Neovim "$nvBase/nvim-win64.zip" 'nvim-win64')

# 4. フォント
$fontInstalled = $FontFiles | Where-Object {
  (Test-Path -LiteralPath (Join-Path $FontDir $_)) -or (Test-Path -LiteralPath (Join-Path $env:WINDIR "Fonts\$_"))
}
if (@($fontInstalled).Count -eq $FontFiles.Count) {
  Say ok 'UDEV Gothic 35NF'
} elseif ($Check) {
  Say todo 'UDEV Gothic 35NF が入っていない'
} else {
  $tmp = Join-Path $env:TEMP ('tenv-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'font.zip'
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/yuru7/udev-gothic/releases/download/$($Font.Version)/UDEVGothic_NF_$($Font.Version).zip" -OutFile $zip
    $got = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($got -ne $Font.Sha256.ToUpperInvariant()) { throw "sha256 が合いません(UDEV Gothic)。期待 $($Font.Sha256) / 実際 $got" }
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp
    New-Item -ItemType Directory -Force -Path $FontDir | Out-Null
    if (-not (Test-Path $FontKey)) { New-Item -Path $FontKey -Force | Out-Null }
    foreach ($f in $FontFiles) {
      $dst = Join-Path $FontDir $f
      Copy-Item -LiteralPath (Join-Path $tmp "UDEVGothic_NF_$($Font.Version)\$f") -Destination $dst -Force
      $style = ($f -replace '^UDEVGothic35NF-|\.ttf$', '') -replace 'BoldItalic', 'Bold Italic'
      Set-ItemProperty -Path $FontKey -Name "UDEV Gothic 35NF $style (TrueType)" -Value $dst
      [TenvSetup.Native]::LoadFont($dst)
    }
    Say done "UDEV Gothic 35NF $($Font.Version) を自分のフォントに入れた"
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# 5. WEZTERM_CONFIG_FILE
$cur = [Environment]::GetEnvironmentVariable('WEZTERM_CONFIG_FILE', 'User')
if ($cur -and (Same-Path $cur $ConfigFile)) {
  Say ok "WEZTERM_CONFIG_FILE = $ConfigFile"
} elseif ($Check) {
  Say todo "WEZTERM_CONFIG_FILE が $ConfigFile ではない(今: $cur)"
} else {
  [Environment]::SetEnvironmentVariable('WEZTERM_CONFIG_FILE', $ConfigFile, 'User')
  Say done "WEZTERM_CONFIG_FILE = $ConfigFile$(if ($cur) { "(前: $cur)" })"
}

# 6. %LOCALAPPDATA%\nvim → このリポジトリの nvim
$item = Get-Item -LiteralPath $NvimLink -Force -ErrorAction SilentlyContinue
$linked = $false
if ($item -and $item.LinkType -eq 'Junction') {
  $t = (@($item.Target)[0]) -replace '^\\\\\?\\|^\\\?\?\\', ''
  $linked = Same-Path $t $NvimSrc
}
if ($linked) {
  Say ok "$NvimLink → $NvimSrc"
} elseif ($Check) {
  Say todo "$NvimLink がこのリポジトリの nvim を指していない"
} else {
  if ($item) {
    $bk = 'nvim.bk_' + $Stamp
    Rename-Item -LiteralPath $NvimLink -NewName $bk
    Say done "前の $NvimLink を $bk に名前を変えて残した"
  }
  # mklink /J は管理者権限が要らず、パスの [ ] もそのまま扱える
  cmd /c mklink /J "$NvimLink" "$NvimSrc" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "ジャンクションを作れませんでした($NvimLink → $NvimSrc)" }
  Say done "$NvimLink → $NvimSrc"
}

# 7. local.lua
if (Test-Path -LiteralPath $LocalLua) {
  Say ok "wezterm\local.lua がある"
} elseif ($Check) {
  Say todo 'wezterm\local.lua が無い(local.example.lua を写して書き換える)'
} else {
  Copy-Item -LiteralPath (Join-Path $Repo 'wezterm\local.example.lua') -Destination $LocalLua
  Say done 'wezterm\local.lua を見本から作った(自分の環境の値に書き換える。README の「設定」)'
}

# 8. 依存(winget で入れるもの)
foreach ($d in @(@('git.exe', 'Git(Git Bash を含む)', $true), @('rg.exe', 'ripgrep', $true), @('lazygit.exe', 'lazygit(任意)', $false))) {
  $p = Find-Exe $d[0]
  if ($p) { Say ok "$($d[1])($p)" }
  elseif ($d[2]) { Say todo "$($d[1]) が無い(README の 1. の winget で入れる)" }
  else { Say skip "$($d[1]) は入っていない" }
}

# 9. Neovim のプラグイン(lazy-lock.json の版)
$nvim = Find-Exe 'nvim.exe'
$lazyDir = Join-Path $env:LOCALAPPDATA 'nvim-data\lazy\lazy.nvim'
if (Test-Path -LiteralPath $lazyDir) {
  Say ok 'Neovim のプラグイン'
} elseif ($Check) {
  Say todo 'Neovim のプラグインが入っていない'
} elseif (-not $nvim -or -not (Find-Exe 'git.exe')) {
  Say todo 'Neovim のプラグインは、Neovim と Git がそろってからもう一度実行すると入る'
} else {
  & $nvim --headless '+qa'
  if (Test-Path -LiteralPath $lazyDir) { Say done 'Neovim のプラグインを入れた' }
  else { Say ng 'Neovim のプラグインが入らなかった(nvim を起動して :Lazy で理由を見る)' }
}

if (-not $Check) { [TenvSetup.Native]::BroadcastEnvironment() }

Write-Host ''
if ($script:Missing -gt 0) {
  Write-Host "足りないものが $($script:Missing) 件あります(上の todo / ng)" -ForegroundColor Yellow
  exit 1
}
if ($Check) {
  Write-Host 'そろっています' -ForegroundColor Green
} else {
  Write-Host 'そろいました。開いている WezTerm をすべて閉じてから、スタートメニュー(またはタスクバー)で起動し直してください' -ForegroundColor Green
}
