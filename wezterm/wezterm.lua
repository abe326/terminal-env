-- terminal-env: WezTerm の設定(Windows 用)
--
-- キーは tmux 側(tmux/terminal-env.conf)と同じ Shift+Alt 系。
--   ssh でリモートにつないでいる pane では、tmux 用のキーをそのまま tmux へ流す。
--   ローカルの pane では、同じキーで WezTerm 自身の pane を操作する。
--
-- 環境ごとの値(接続先・パスの対応表など)は、同じフォルダの local.lua に書く(local.example.lua を参照)。

local wezterm = require("wezterm")
local act = wezterm.action
local nf = wezterm.nerdfonts
local config = wezterm.config_builder()

----------------------------------------------------------------
-- 環境ごとの設定(既定値。local.lua で上書きする)
----------------------------------------------------------------
local S = {
  -- 基本(Windows だけで使う場合も、ここだけで動く)
  -- ローカルの pane のシェル。nil なら PowerShell 7(pwsh.exe)が PATH にあればそれ、無ければ Windows に最初から入っている
  -- PowerShell 5.1(powershell.exe)
  shell = nil,
  -- Shift+Alt+P で一覧するローカルのフォルダ(文字列か、複数なら配列)。nil ならホーム
  local_projects_root = nil,
  -- フォルダを開いたとき、右の pane で起動するコマンド。false ならシェルのまま
  start_command = "claude",
  -- フォルダを開いたとき、左にツリーを出すか
  open_with_tree = true,
  -- WezTerm を起動した最初の画面にも、左にツリーを出すか(場所は local_projects_root の先頭、無ければホーム)
  tree_on_startup = true,
  -- ツリーの幅(桁数)。開くときはいつもこの幅
  tree_width = 34,
  -- true: 窓の大きさを変えてもツリーの幅を保つ(境目をドラッグして変えた幅も保つ。開き直すと tree_width に戻る)
  -- false: 窓の大きさに合わせて伸び縮みする
  tree_width_fixed = true,
  -- 前の作業を再開(Claude Code の会話を、場所ごとのタブで再開する。Shift+Alt+R・タブバーの「＋」)。false で使わない
  claude_resume = true,
  -- WezTerm を起動したとき、前回開いていた作業があれば、再開の画面を出すか
  claude_resume_on_startup = true,
  -- WezTerm を起動したとき、フォルダを開く画面(Shift+Alt+O と同じ一覧)を出すか。
  -- 再開の画面と同じ画面に出し、Tab で切り替える(前回開いていた作業があれば、再開の方を先に出す)
  open_on_startup = true,
  -- 再開の画面に出す会話: この日数以内に使ったもの
  claude_resume_days = 3,

  -- リモート(ssh でつなぐ Linux 機)。使わないなら空のまま。項目は local.example.lua を参照
  remotes = {},
  -- リモートから頼まれて、この PC の新しいタブで Claude Code を起動する(wopen --claude <ファイル>)。使わないなら nil。
  -- 項目は local.example.lua を参照
  ask_claude = nil,

  -- 見た目
  -- 起動した最初の窓の大きさ(画面に対する割合。中央に置く)。nil なら WezTerm の既定
  window_scale = 0.7,
  default_theme = 1,
  opacity = 0.9,
  -- 文字
  font_family = "UDEV Gothic 35NF",
  font_size = 12.5,       -- 本文(ターミナル・ツリー)
  tab_font_size = 10.5,   -- タブと右上の表示
  palette_font_size = 13, -- コマンドパレット・選択画面
  line_height = 1.08,
  -- 文字の配色。テーマの上に重ねる(書いた項目だけ変わる)
  --   colors: 本文の色。foreground / background / cursor_bg / selection_bg / ansi / brights など(WezTerm の colors と同じ)
  --   theme_colors: タブや右上の色。accent(選択中のタブ)/ accent2(リモートのタブ)/ bar / surface / fg / dim / ok
  colors = {},
  theme_colors = {},
}

local LOCAL_FILE = wezterm.config_dir .. "/local.lua"
do
  local ok, user = pcall(dofile, LOCAL_FILE)
  if ok and type(user) == "table" then
    for k, v in pairs(user) do S[k] = v end
  elseif not ok and not tostring(user):find("No such file") and not tostring(user):find("cannot open") then
    wezterm.log_error("local.lua の読み込みに失敗: " .. tostring(user))
  end
  wezterm.add_to_config_reload_watch_list(LOCAL_FILE)
end

-- 以前の書き方(remote_host などを直に書く)も、リモート 1 台として受け付ける
if S.remote_host and #S.remotes == 0 then
  S.remotes = { {
    name = S.remote_label, host = S.remote_host, projects_root = S.remote_projects_root,
    attach_with = S.remote_attach_with, path_map = S.path_map, fallback_root = S.fallback_root,
    open_allowed = S.open_allowed, open_command = S.open_command,
  } }
end
-- 1 つだけなら配列でなくてもよい
local function as_list(v)
  if v == nil then return {} end
  return type(v) == "table" and v or { v }
end
for _, r in ipairs(S.remotes) do
  r.name = r.name or r.host
  r.projects_root = as_list(r.projects_root or "~")
  r.path_map = r.path_map or {}
  r.mutagen = as_list(r.mutagen)
end
S.local_projects_root = as_list(S.local_projects_root)

local function on_path(exe)
  for dir in (os.getenv("PATH") or ""):gmatch("[^;]+") do
    local f = io.open(dir:gsub('"', ""):gsub("[\\/]$", "") .. "\\" .. exe, "rb")
    if f then f:close() return true end
  end
  return false
end
local SHELL = S.shell or (on_path("pwsh.exe") and "pwsh.exe" or "powershell.exe")

local function remote_by_host(host)
  for _, r in ipairs(S.remotes) do
    if r.host == host then return r end
  end
end

----------------------------------------------------------------
-- 合言葉(トークン)。リモートからの合図(開く・送る・Claude Code の状態)が、本物の wopen / tenv-cc-state から
-- 来たものかを確かめる。端末に流れただけの文字列(cat したファイル・ログ・AI の出力など)は合言葉を知らないので、
-- 偽の合図は捨てられる。
--   ・この PC だけで読める場所(%LOCALAPPDATA%\tenv\token)に一度だけ作り、どの WezTerm も同じものを使う
--   ・リモートでフォルダを開くとき(tenv-open -k)に、リモートの自分だけが読めるファイル
--     (~/.local/state/tenv/tokens)に書く。tmux を起動し直しても残る。複数の PC からつなぐときは PC ごとに 1 行
--   ・合図には、リモートが知っている合言葉をすべて(, 区切り)付けてくる。どれか 1 つが合えば受け付ける
----------------------------------------------------------------
local TOKEN_FILE = (os.getenv("LOCALAPPDATA") or wezterm.home_dir) .. "\\tenv\\token"
local function read_token()
  local f = io.open(TOKEN_FILE, "r")
  if not f then return nil end
  local t = (f:read("*l") or ""):match("^(%x+)%s*$")
  f:close()
  return t and #t >= 32 and t or nil
end
local TOKEN = read_token()
if not TOKEN then
  -- 暗号用の乱数で作る(.NET の GUID は暗号用の乱数から作られる)
  pcall(wezterm.run_child_process, { "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
    "$f = '" .. TOKEN_FILE:gsub("'", "''") .. "'; New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null; "
      .. "if (-not (Test-Path $f)) { ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')) "
      .. "| Set-Content -NoNewline -Encoding ascii $f }" })
  TOKEN = read_token()
end

local function token_ok(list)
  if not TOKEN or not list then return false end
  for t in list:gmatch("[^,]+") do
    if t == TOKEN then return true end
  end
  return false
end

-- 設定(local.lua)を新しいタブの nvim で開く。無ければ見本から作る
local function open_settings(window)
  local f = io.open(LOCAL_FILE, "r")
  if f then
    f:close()
  else
    local src = io.open(wezterm.config_dir .. "/local.example.lua", "r")
    local dst = io.open(LOCAL_FILE, "w")
    if src and dst then dst:write(src:read("*a")) end
    if src then src:close() end
    if dst then dst:close() end
  end
  local tab = window:mux_window():spawn_tab({ cwd = wezterm.config_dir, args = { "nvim", LOCAL_FILE } })
  tab:set_title("設定")
end

local THEME_FILE = wezterm.home_dir .. "/.wezterm-theme"

----------------------------------------------------------------
-- テーマ(Shift+Alt+T で切り替え。選んだものは ~/.wezterm-theme に残る)
----------------------------------------------------------------
local THEMES = {
  { name = "Tokyo Night", scheme = "Tokyo Night",
    bg = "#1a1b26", bg2 = "#1f2335", bar = "#13141c", surface = "#292e42",
    fg = "#c0caf5", dim = "#565f89", accent = "#7aa2f7", accent2 = "#bb9af7", ok = "#9ece6a", warn = "#ff9e64" },
  { name = "Catppuccin Mocha", scheme = "Catppuccin Mocha",
    bg = "#1e1e2e", bg2 = "#232136", bar = "#11111b", surface = "#313244",
    fg = "#cdd6f4", dim = "#6c7086", accent = "#cba6f7", accent2 = "#89b4fa", ok = "#a6e3a1", warn = "#fab387" },
  { name = "Kanagawa", scheme = "Kanagawa (Gogh)",
    bg = "#1f1f28", bg2 = "#252535", bar = "#16161d", surface = "#2a2a37",
    fg = "#dcd7ba", dim = "#727169", accent = "#7e9cd8", accent2 = "#e6c384", ok = "#98bb6c", warn = "#ffa066" },
  { name = "Rosé Pine", scheme = "rose-pine",
    bg = "#191724", bg2 = "#1f1d2e", bar = "#12101a", surface = "#26233a",
    fg = "#e0def4", dim = "#6e6a86", accent = "#ebbcba", accent2 = "#c4a7e7", ok = "#9ccfd8", warn = "#f6c177" },
}

local function load_theme_index()
  local f = io.open(THEME_FILE, "r")
  if not f then return THEMES[S.default_theme] and S.default_theme or 1 end
  local n = tonumber(f:read("*l") or "")
  f:close()
  if n and THEMES[n] then return n end
  return 1
end

local theme_index = load_theme_index()
local T = {}
for k, v in pairs(THEMES[theme_index]) do T[k] = v end
for k, v in pairs(S.theme_colors or {}) do T[k] = v end

----------------------------------------------------------------
-- 見た目
----------------------------------------------------------------
config.automatically_reload_config = true
config.default_prog = { SHELL, "-NoLogo" }
-- ツリーの「設定」が開くファイル(Windows の nvim が読む)
-- (今のフォルダの git.exe などを動かさない設定は、ツリーとエディタの nvim の中だけで行う。
--  pane のシェル全体にかけると、cmd で今のフォルダのプログラムを名前だけで起動できなくなるため)
config.set_environment_variables = { TENV_SETTINGS = LOCAL_FILE }
config.use_ime = true
config.initial_cols = 120
config.initial_rows = 32
config.max_fps = 120
config.animation_fps = 60
config.audible_bell = "Disabled"
config.exit_behavior = "CloseOnCleanExit"
config.status_update_interval = 1000

config.font = wezterm.font_with_fallback({
  { family = S.font_family, weight = "Regular" },
  "UDEV Gothic 35NF",
  "Hack Nerd Font",
})
config.font_size = S.font_size
config.line_height = S.line_height
config.harfbuzz_features = { "calt=1", "liga=1" }

if wezterm.color.get_builtin_schemes()[T.scheme] then
  config.color_scheme = T.scheme
end

-- 半透明 + Windows 11 のアクリル(背景がほんのり透ける)。文字の背景は不透明のままにして読みやすさを保つ
config.window_background_opacity = S.opacity
config.win32_system_backdrop = "Acrylic"
config.text_background_opacity = 1.0
config.window_background_gradient = {
  orientation = { Linear = { angle = -45.0 } },
  colors = { T.bg, T.bg2 },
  interpolation = "Linear",
  blend = "Rgb",
}

config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.integrated_title_button_style = "Windows"
config.integrated_title_button_color = T.dim
config.window_padding = { left = 14, right = 14, top = 10, bottom = 6 }

-- 非アクティブな pane は少し暗く(今どこにいるかが一目で分かる)
config.inactive_pane_hsb = { saturation = 0.8, brightness = 0.62 }

config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 600
config.cursor_blink_ease_in = "EaseOut"
config.cursor_blink_ease_out = "EaseOut"
config.visual_bell = {
  fade_in_function = "EaseIn", fade_in_duration_ms = 60,
  fade_out_function = "EaseOut", fade_out_duration_ms = 160,
  target = "CursorColor",
}

-- タブバー: 各タブに × が付く形(fancy)。窓のボタン(最小化・最大化・閉じる)もここに並ぶ
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false -- 右上に接続先と時刻を出すので常に表示
-- 「＋」: 新しいタブ・フォルダを開く・前の作業を再開・タブを選ぶ を選ぶ(new-tab-button-click)
config.show_new_tab_button_in_tab_bar = true
config.tab_max_width = 40
config.window_frame = {
  font = wezterm.font({ family = S.font_family, weight = "Bold" }),
  font_size = S.tab_font_size,
  active_titlebar_bg = T.bar,
  inactive_titlebar_bg = T.bar,
  active_titlebar_fg = T.fg,
  inactive_titlebar_fg = T.dim,
  button_fg = T.dim,
  button_bg = T.bar,
  button_hover_fg = T.fg,
  button_hover_bg = T.surface,
}

-- 閉じるときの確認: タブの × は 1 つずつ必ず確認する(中で何が動いていても)。
-- 窓の × は、中のタブをまとめて 1 回だけ確認して閉じる(window_close_confirmation の既定)
config.skip_close_confirmation_for_processes_named = {}
config.window_close_confirmation = "AlwaysPrompt"

-- エクスプローラーからドロップしたファイルは "C:\..." の形で貼り付ける(ツリーはこれを受けて配置する)
config.quote_dropped_files = "WindowsAlwaysQuoted"

config.colors = {
  split = T.surface,
  cursor_bg = T.accent,
  cursor_border = T.accent,
  -- 選んだ範囲(ドラッグ / Shift+ドラッグ)。背景と近い色だと選べているか分からないので、はっきりした青にする
  selection_bg = "#3d59a1",
  selection_fg = "#ffffff",
  tab_bar = {
    background = T.bar,
    inactive_tab_edge = T.bar,
    active_tab = { bg_color = T.accent, fg_color = T.bar, intensity = "Bold" },
    inactive_tab = { bg_color = T.surface, fg_color = T.dim },
    inactive_tab_hover = { bg_color = T.surface, fg_color = T.fg },
  },
  visual_bell = T.surface,
}
for k, v in pairs(S.colors or {}) do config.colors[k] = v end

config.command_palette_bg_color = T.bar
config.command_palette_fg_color = T.fg
config.command_palette_font_size = S.palette_font_size
config.char_select_font_size = S.palette_font_size
config.char_select_bg_color = T.bar
config.char_select_fg_color = T.fg

----------------------------------------------------------------
-- タブ: 番号 + 実行中のもののアイコン + 題名。リモートのタブは別の色
----------------------------------------------------------------
local LEFT = nf.ple_left_half_circle_thick
local RIGHT = nf.ple_right_half_circle_thick

local function basename(s)
  return (s or ""):gsub("(.*[/\\])(.*)", "%2"):lower()
end

local ICONS = {
  ["ssh.exe"] = nf.md_server_network,
  ["ssh"] = nf.md_server_network,
  ["pwsh.exe"] = nf.md_powershell,
  ["powershell.exe"] = nf.md_powershell,
  ["cmd.exe"] = nf.md_console,
  ["nvim.exe"] = nf.custom_vim,
  ["nvim"] = nf.custom_vim,
  ["claude.exe"] = nf.md_robot_outline,
  ["node.exe"] = nf.md_nodejs,
  ["wsl.exe"] = nf.cod_terminal_linux,
}

-- 作業フォルダの名前(cwd は版によって Url か文字列)
local function folder_name(cwd)
  if not cwd then return nil end
  local p = type(cwd) == "userdata" and cwd.file_path or tostring(cwd)
  p = p:gsub("^file://[^/]*", ""):gsub("[/\\]+$", "")
  local name = p:match("([^/\\]+)$")
  return name and name ~= "" and name or nil
end

local function is_remote_name(name)
  local b = basename(name)
  return b == "ssh.exe" or b == "ssh"
end

-- pane の中で動いているプログラム名。Windows では問い合わせのたびに全プロセスを調べて重いので、2 秒だけ覚えておく
-- (1 秒ごとの処理とタブの描き直しで、pane の数だけ何度も問い合わせるため)
local FG = {}
local function fg_name(pane)
  local id, now = pane:pane_id(), os.time()
  local c = FG[id]
  if not c or now - c.t >= 2 then
    c = { name = pane:get_foreground_process_name() or "", t = now }
    FG[id] = c
  end
  return c.name
end

-- pane がつないでいるリモート(ssh の引数の接続先から探す)。
-- 見つかったものは pane ごとに覚える。見つからなかったときは 10 秒だけ覚える(後で ssh したときに分かるように)
local REMOTE_OF = {}
local function remote_of(pane)
  local id, now = pane:pane_id(), os.time()
  local c = REMOTE_OF[id]
  if c and (c.r or now - c.t < 10) then return c.r end
  local found
  local info = pane:get_foreground_process_info()
  if info and is_remote_name(info.executable) then
    for _, a in ipairs(info.argv or {}) do
      local r = remote_by_host(a)
      if r then found = r break end
    end
  end
  REMOTE_OF[id] = { r = found, t = now }
  return found
end

----------------------------------------------------------------
-- Claude Code の状態(bin/tenv-cc-state が hook から送ってくる)
--   リモート: ssh の pane のユーザー変数 tenv_cc = "<状態> <数>"(tmux のセッション全体で一番目立つもの)
--   ローカル: %LOCALAPPDATA%\tenv\cc\<pane 番号> = "<状態> <時刻>"
----------------------------------------------------------------
local STATE_HOME = (os.getenv("LOCALAPPDATA") or wezterm.home_dir) .. "\\tenv"
-- pane 番号は WezTerm のプロセスごとに振られるので、プロセスごとのフォルダに分ける
local CC_DIR = STATE_HOME .. "\\cc\\" .. tostring(wezterm.procinfo.pid()) .. "\\"
local CC_RANK = { waiting = 3, done = 2, working = 1 }
local CC_LOCAL = {} -- pane 番号 → 状態(update-status で読み直す)
local TAB_CC = {} -- タブ番号 → { 状態, 数 }(update-status で読み直す。タブの幅の割り振りに使う)

local function read_local_cc(id)
  local f = io.open(CC_DIR .. id, "r")
  if not f then return nil end
  local s = (f:read("*l") or ""):match("^(%a+)")
  f:close()
  return CC_RANK[s] and s or nil
end

-- pane の状態と、その状態の Claude Code の数
--   リモートは、pane に残っているユーザー変数 tenv_cc = "<状態> <数> <合言葉>" を、合言葉を確かめて読む
--   (毎回 pane から読むので、設定を読み直したりテーマを替えたりしても印が消えない)
local function pane_cc(pane)
  local v = pane:get_user_vars().tenv_cc
  if v and v ~= "" and is_remote_name(fg_name(pane)) then
    local s, n, t = v:match("^(%a+) (%d%d?%d?) ([%x,]+)$")
    if CC_RANK[s] and token_ok(t) then return s, tonumber(n) end
    return nil, 0
  end
  local s = CC_LOCAL[pane:pane_id()]
  return s, s and 1 or 0
end

-- タブの状態: タブの中の全 pane のうち一番目立つもの(確認待ち > 完了 > 作業中)と、その数
local function tab_cc(mux_tab)
  local best, count = nil, 0
  for _, p in ipairs(mux_tab:panes()) do
    local s, n = pane_cc(p)
    if s then
      if not best or CC_RANK[s] > CC_RANK[best] then best, count = s, n
      elseif s == best then count = count + n end
    end
  end
  return best, count
end

local CC_LOOK = {
  working = { icon = nf.md_progress_clock, color = "accent2", label = "作業中" },
  waiting = { icon = nf.md_bell_ring, color = "warn", label = "確認待ち" },
  done = { icon = nf.md_check_circle, color = "ok", label = "完了" },
}

-- タブのアイコンと題名
local function tab_label(tab)
  local pane = tab.active_pane
  local icon = ICONS[basename(pane.foreground_process_name)] or nf.md_console_line
  -- タブ名は開いているフォルダ名(設定・操作一覧・Git などは付けた題名のまま)。
  -- リモートは tmux が題名にフォルダ名を出す(terminal-env.conf の set-titles-string)
  local title
  if tab.tab_title ~= "" then
    title = tab.tab_title
  elseif is_remote_name(pane.foreground_process_name) then
    title = pane.title
  else
    title = folder_name(pane.current_working_dir) or pane.title
  end
  title = title:gsub("^Administrator: ", "")
  -- ツリーから開いたタブ(題名を付けてある)は中身のアイコンにする
  if title:find("^Git: ") then icon = nf.dev_git
  elseif title:find("^編集: ") then icon = nf.custom_vim
  elseif pane.title:find("^ツリー: ") then icon = "󰙅"
  elseif title == "設定" then icon = nf.md_cog
  elseif title == "操作一覧" then icon = nf.md_keyboard end
  return icon, title
end

local function cc_mark(state, count)
  return state and (" " .. CC_LOOK[state].icon .. (count > 1 and tostring(count) or "")) or ""
end

----------------------------------------------------------------
-- タブの幅: 右上の表示と窓のボタンの幅を先に取り、残りにタブを収める。
--   WezTerm はタブが入りきらないと、題名を途中で切ったタブを右上の表示に重ねて描くので、ここで縮める。
--   縮める順: ほかのタブの題名を「…」で短く → 選んでいるタブの題名も短く(12 桁まで)
--            → ほかのタブを番号と印だけに → 選んでいるタブの題名も消す
--   幅は WezTerm 20240203 で測った値(96dpi のとき): タブ 1 つの余白と × = 文字 1 桁 + 16px(タブの間 2px)、
--   左端の印 = 5 桁、「＋」= 22px、窓のボタン = 138px。
--   また WezTerm は、タブ 1 つの幅を「窓の幅 ÷ (タブの数 + 1) − 1.5 桁」までで切る(タブが多いと、選んでいるタブも
--   題名を出せない)
----------------------------------------------------------------
local TITLE_MAX = 30 -- 題名の上限(桁)
local TITLE_MIN = 6 -- 短くした題名がこれより短くなるなら、題名を出さない
-- 窓 → { w = 窓の幅(px), cell = タブの文字 1 桁の幅(px), scale = dpi / 96, status = 右上の桁数 }
-- (設定を読み直した直後のタブも正しい幅で描けるよう、読み直しても覚えておく)
wezterm.GLOBAL.tabbar = wezterm.GLOBAL.tabbar or {}

local function measure_tabbar(window, status_cols)
  local ok, dim, size = pcall(function() return window:get_dimensions(), window:active_tab():get_size() end)
  if not ok or not dim or not size or size.cols == 0 then return false end
  local dpi = dim.dpi or 96
  -- タブの文字 1 桁 = 文字の大きさ(px)× 半角の縦横比 を四捨五入した px。小さく見積もると右上に重なるので、
  -- 縦横比が分からないフォントは、端末の文字の幅(四捨五入された値)から考えられる一番大きい値にする
  local px = S.tab_font_size * dpi / 72
  local aspect = 0.6 -- UDEV Gothic 35(半角:全角 = 3:5)
  if not S.font_family:find("UDEV Gothic 35") then
    aspect = (size.pixel_width / size.cols + 0.5) / (S.font_size * dpi / 72)
  end
  local m = { w = dim.pixel_width, scale = dpi / 96, cell = math.floor(px * aspect + 0.55), status = status_cols }
  local key = tostring(window:window_id())
  local old = wezterm.GLOBAL.tabbar[key]
  if old and old.w == m.w and old.cell == m.cell and old.status == m.status and old.scale == m.scale then return false end
  wezterm.GLOBAL.tabbar[key] = m
  return true
end

-- 各タブの題名に使う桁数(tabs の並び順)。0 = 題名なし、-1 = アイコンも出さない。nil = まだ測っていない
local function tab_widths(tabs, window_id)
  local tb = wezterm.GLOBAL.tabbar[tostring(window_id)]
  if not tb then return nil end
  local n, a = #tabs, 1
  local edge = tb.cell + 16 * tb.scale -- タブ 1 つの余白と ×
  local avail = tb.w - (5 + tb.status + 1) * tb.cell - (22 + 138 + 4) * tb.scale
  local budget = math.floor((avail - n * (edge + 2 * tb.scale)) / tb.cell)
  -- WezTerm が切る幅に収まる桁数
  local cap = math.floor((tb.w / (n + 1) - 1.5 * tb.cell - 2 * tb.scale - edge) / tb.cell)
  local l1, l2, want, num_only = {}, {}, {}, {}
  for i, t in ipairs(tabs) do
    if t.is_active then a = i end
    local icon, title = tab_label(t)
    local c = TAB_CC[t.tab_id]
    local num = " " .. tostring(t.tab_index + 1) .. cc_mark(c and c[1], c and c[2] or 0)
    l1[i] = wezterm.column_width(num .. " ")
    l2[i] = wezterm.column_width(num .. "  " .. icon .. " ")
    num_only[i] = l2[i] > cap
    local tw = wezterm.column_width(title)
    want[i] = math.max(math.min(tw, TITLE_MAX, cap - l2[i] - 2), 0)
    if want[i] < tw and want[i] < TITLE_MIN then want[i] = 0 end
  end
  local function full(i, k) return k > 0 and l2[i] + k + 2 or l2[i] end
  local function others(f)
    local s = 0
    for i = 1, n do if i ~= a then s = s + f(i) end end
    return s
  end
  local res = {}
  local function done()
    for i = 1, n do if num_only[i] then res[i] = -1 end end
    return res
  end
  if full(a, want[a]) + others(function(i) return full(i, want[i]) end) <= budget then
    for i = 1, n do res[i] = want[i] end
    return done()
  end
  -- ほかのタブの題名を、長いものから同じ桁に揃えて短くする(TITLE_MIN より短くなるものは題名を消す)
  local rest = budget - full(a, want[a]) - others(function(i) return l2[i] end)
  if rest >= 0 then
    local function cost(k) return k > 0 and k + 2 or 0 end
    local function cut(i, level)
      local k = math.min(want[i], level)
      return (k < want[i] and k < TITLE_MIN) and 0 or k
    end
    local level = 0
    for L = TITLE_MAX, 1, -1 do
      if others(function(i) return cost(cut(i, L)) end) <= rest then level = L break end
    end
    for i = 1, n do res[i] = cut(i, level) end
    res[a] = want[a]
    -- 余った分で、題名を消したタブにも題名を出す(題名の短いタブから)
    local left = rest - others(function(i) return cost(res[i]) end)
    local order = {}
    for i = 1, n do if i ~= a and res[i] < want[i] then table.insert(order, i) end end
    table.sort(order, function(x, y) return want[x] < want[y] end)
    for _, i in ipairs(order) do
      local k = math.min(want[i], left + cost(res[i]) - 2)
      if k > res[i] and (k == want[i] or k >= TITLE_MIN) then
        left = left - (cost(k) - cost(res[i]))
        res[i] = k
      end
    end
    return done()
  end
  -- 選んでいるタブの題名も短くする
  local function active_title(k)
    local t = math.min(k, want[a])
    return (t < want[a] and t < TITLE_MIN) and 0 or t
  end
  local k = budget - others(function(i) return l2[i] end) - l2[a] - 2
  if k >= math.min(12, want[a]) then
    for i = 1, n do res[i] = 0 end
    res[a] = active_title(k)
    return done()
  end
  -- ほかのタブは番号と印だけ
  k = budget - others(function(i) return l1[i] end) - l2[a] - 2
  for i = 1, n do res[i] = -1 end
  res[a] = active_title(k)
  return done()
end

wezterm.on("format-tab-title", function(tab, tabs, _, _, hover, max_width)
  local pane = tab.active_pane
  local icon, title = tab_label(tab)

  local bg, fg = T.surface, T.dim
  if tab.is_active then
    bg, fg = (is_remote_name(pane.foreground_process_name) and T.accent2 or T.accent), T.bar
  elseif hover then
    bg, fg = T.surface, T.fg
  end

  -- Claude Code の状態(タブの中の全 pane のうち一番目立つもの。同じ状態が複数なら数も出す)
  local cc = {}
  local mux_tab = wezterm.mux.get_tab(tab.tab_id)
  local state, count = nil, 0
  if mux_tab then state, count = tab_cc(mux_tab) end
  if state then
    local look = CC_LOOK[state]
    -- 選んでいるタブでは文字と同じ色、それ以外は状態の色(確認待ちはタブごと目立たせる)
    if state == "waiting" and not tab.is_active then bg, fg = T.warn, T.bar end
    cc = { { Foreground = { Color = (tab.is_active or state == "waiting") and fg or T[look.color] } }, { Text = cc_mark(state, count) } }
  end

  -- 並び: 番号 + 状態の印 + アイコン + 題名。
  -- 最初の文字の色がタブの × の色になるので、番号(文字の色)を先頭に置く
  -- (fancy のタブバーでは tab_max_width が効かず max_width が小さいので、題名の上限はここで決める)
  local widths = tab_widths(tabs, tab.window_id)
  local k = widths and widths[tab.tab_index + 1] or TITLE_MAX
  local text
  if k > 0 then
    if wezterm.column_width(title) > k then title = wezterm.truncate_right(title, k - 1) .. "…" end
    text = string.format("  %s  %s ", icon, title)
  elseif k == 0 then
    text = string.format("  %s ", icon)
  else
    text = " "
  end
  local cells = { { Background = { Color = bg } }, { Foreground = { Color = fg } }, { Text = string.format(" %d", tab.tab_index + 1) } }
  for _, c in ipairs(cc) do table.insert(cells, c) end
  table.insert(cells, { Foreground = { Color = fg } })
  table.insert(cells, { Text = text })
  return cells
end)

----------------------------------------------------------------
-- Mutagen の同期状態(リモートの mutagen にセッション名を書いたとき、右上に出す)
----------------------------------------------------------------
-- mutagen の問い合わせは WezTerm の画面の処理を止めて待つ(約 40ms)ので、15 秒に 1 回にする
local MUTAGEN = { at = 0, sessions = {} }
local function mutagen_sessions()
  if os.time() - MUTAGEN.at < 15 then return MUTAGEN.sessions end
  MUTAGEN.at = os.time()
  local ok, success, out = pcall(wezterm.run_child_process, { "mutagen", "sync", "list", "--template",
    '{{range .}}{{.Name}}|{{.Status}}|{{len .Conflicts}}|{{.Paused}}|{{.LastError}}{{"\\n"}}{{end}}' })
  local list = {}
  if ok and success and out then
    for line in tostring(out):gmatch("[^\r\n]+") do
      local name, status, conflicts, paused, err = line:match("^(.-)|(.-)|(%d+)|(%a+)|(.*)$")
      if name then
        list[name] = { status = status, conflicts = tonumber(conflicts), paused = paused == "true", error = err }
      end
    end
  end
  MUTAGEN.sessions = list
  return list
end

-- リモートの同期の状態: 一番悪いもの。{ 表示, 色 }
local function sync_state(r)
  if #r.mutagen == 0 then return nil end
  local sessions = mutagen_sessions()
  local worst, rank = { "同期済", T.ok }, 0
  local function bump(n, text, color) if n > rank then worst, rank = { text, color }, n end end
  for _, name in ipairs(r.mutagen) do
    local s = sessions[name]
    if not s then bump(5, "同期なし", T.warn)
    elseif s.paused then bump(4, "同期停止", T.warn)
    elseif s.error ~= "" or s.status:find("^Halted") or s.status:find("^Disconnected") or s.status:find("^Connecting") then
      bump(5, "同期エラー", T.warn)
    elseif s.conflicts > 0 then bump(3, "競合 " .. s.conflicts, T.warn)
    elseif s.status ~= "Watching" then bump(1, "同期中", T.accent2) end
  end
  return worst
end

----------------------------------------------------------------
-- Claude Code の通知(確認待ち・完了になったとき)と、ローカルの状態の読み直し
----------------------------------------------------------------
wezterm.GLOBAL.cc_prev = wezterm.GLOBAL.cc_prev or {}
local cc_scanned = 0
local function scan_cc(window)
  if os.time() == cc_scanned then return false end
  cc_scanned = os.time()
  local changed = false
  local focused = window:is_focused() and window:active_pane()
  -- ローカルの状態のファイルは、あるものだけ読む(フォルダの一覧を 1 回取る)
  local present = {}
  local ok, files = pcall(wezterm.read_dir, CC_DIR)
  if ok then
    for _, f in ipairs(files) do present[f:match("([^\\/]+)$") or f] = true end
  end
  local alive, tab_state = {}, {}
  for _, mw in ipairs(wezterm.mux.all_windows()) do
    for _, t in ipairs(mw:tabs()) do
      local best, count = nil, 0
      for _, p in ipairs(t:panes()) do
        local id = p:pane_id()
        alive[id] = true
        local remote = is_remote_name(fg_name(p))
        if not remote then CC_LOCAL[id] = present[tostring(id)] and read_local_cc(id) or nil end
        local s, n = pane_cc(p)
        -- 見ている pane の「完了」は消す(ローカルのみ。リモートは tmux の pane-focus-in で消える)
        if s == "done" and not remote and focused and focused:pane_id() == id then
          os.remove(CC_DIR .. id)
          CC_LOCAL[id], s = nil, nil
        end
        if s then
          if not best or CC_RANK[s] > CC_RANK[best] then best, count = s, n
          elseif s == best then count = count + n end
        end
        local key = tostring(id)
        local prev = wezterm.GLOBAL.cc_prev[key]
        if (s or "") ~= prev then
          changed = true
          wezterm.GLOBAL.cc_prev[key] = s or ""
          -- prev が nil = 起動して初めて見た pane(前からの状態なので知らせない)
          if (s == "waiting" or s == "done") and prev ~= nil and not (focused and focused:pane_id() == id) then
            local name = t:get_title() ~= "" and t:get_title() or (remote and p:get_title()) or folder_name(p:get_current_working_dir()) or ""
            window:toast_notification("Claude Code", name .. ": " .. (s == "waiting" and "確認を求めています" or "作業が終わりました"), nil, 6000)
          end
        end
      end
      if best then tab_state[t:tab_id()] = { best, count } end
    end
  end
  TAB_CC = tab_state
  -- 閉じた pane の覚えを捨てる
  for id in pairs(FG) do if not alive[id] then FG[id] = nil end end
  for id in pairs(CC_LOCAL) do if not alive[id] then CC_LOCAL[id] = nil end end
  return changed
end

-- 右上: 接続先(ローカル / リモート)と同期の状態・ズーム中の印・時刻
-- 右上の表示は、中身が変わったときだけ書き直す(書き直すとタブの描き直しも走るため)。
-- force = Claude Code の状態やタブの幅が変わった(タブを描き直したい)
-- (書いた中身は設定を読み直しても覚えておく。読み直した直後も、描き直させられるように)
wezterm.GLOBAL.last_status = wezterm.GLOBAL.last_status or {}
local LEFT_DONE = {}
local function render_status(window, pane, force)
  local rem = is_remote_name(fg_name(pane)) and remote_of(pane)
  local where_bg = rem and T.accent2 or T.accent
  local where = rem and (nf.md_server_network .. " " .. rem.name) or (nf.md_monitor .. " " .. wezterm.hostname())

  local cells = {}
  local function pill(bg, fg, text)
    table.insert(cells, { Background = { Color = T.bar } })
    table.insert(cells, { Foreground = { Color = bg } })
    table.insert(cells, { Text = LEFT })
    table.insert(cells, { Background = { Color = bg } })
    table.insert(cells, { Foreground = { Color = fg } })
    table.insert(cells, { Text = text })
    table.insert(cells, { Background = { Color = T.bar } })
    table.insert(cells, { Foreground = { Color = bg } })
    table.insert(cells, { Text = RIGHT .. " " })
  end

  local tab = pane:tab()
  if tab then
    for _, info in ipairs(tab:panes_with_info()) do
      if info.is_zoomed then pill(T.surface, T.ok, nf.md_fullscreen .. " ZOOM") break end
    end
  end
  pill(where_bg, T.bar, where)
  -- 同期の状態: リモートのタブならそのリモート、ローカルのタブなら同期を設定した最初のリモート
  local sync_remote = rem
  if not sync_remote then
    for _, r in ipairs(S.remotes) do
      if #r.mutagen > 0 then sync_remote = r break end
    end
  end
  local sync = sync_remote and sync_state(sync_remote)
  if sync and not rem and #S.remotes > 1 then sync[1] = sync_remote.name .. " " .. sync[1] end
  if sync then pill(T.surface, sync[2], nf.md_sync .. " " .. sync[1]) end
  pill(T.surface, T.fg, nf.md_clock_outline .. " " .. wezterm.strftime("%H:%M"))
  -- 窓の幅か右上の幅が変わったら、タブの幅を割り振り直す(タブを描き直させる)
  local cols = 0
  for _, c in ipairs(cells) do if c.Text then cols = cols + wezterm.column_width(c.Text) end end
  if measure_tabbar(window, cols) then force = true end
  local wid = window:window_id()
  local text = wezterm.format(cells)
  local last = wezterm.GLOBAL.last_status[tostring(wid)]
  if force and last and last:gsub("​$", "") == text then
    -- 中身が同じでもタブを描き直させたいときは、見えない文字を付け外しして「変わった」ことにする
    text = last:find("​$") and text or (text .. "​")
  end
  if text ~= last then
    wezterm.GLOBAL.last_status[tostring(wid)] = text
    window:set_right_status(text)
  end
  if not LEFT_DONE[wid] then
    LEFT_DONE[wid] = true
    window:set_left_status(wezterm.format({
      { Background = { Color = T.bar } }, { Foreground = { Color = T.accent } }, { Text = "  " .. nf.md_console_line .. " " },
    }))
  end
end

wezterm.on("update-status", function(window, pane)
  local changed = scan_cc(window)
  render_status(window, pane, changed)
end)

----------------------------------------------------------------
-- ツリーの幅を保つ(tree_width_fixed)。WezTerm は窓の大きさに合わせて pane を伸び縮みさせるので、戻す。
--   窓の大きさが変わっていないのに幅が変わった = 境目をドラッグした → その幅を覚える
----------------------------------------------------------------
wezterm.GLOBAL.tree_panes = wezterm.GLOBAL.tree_panes or {}
wezterm.GLOBAL.tree_w = wezterm.GLOBAL.tree_w or {} -- タブ → 保つ幅
local TAB_COLS = {} -- タブ → 前に見たときのタブの幅
local function fit_trees(gw, resized)
  if not S.tree_width_fixed then return end
  for _, t in ipairs(gw:mux_window():tabs()) do
    local key = tostring(t:tab_id())
    local tree_id = wezterm.GLOBAL.tree_panes[key]
    for _, info in ipairs(tree_id and t:panes_with_info() or {}) do
      if info.pane:pane_id() == tree_id and not info.is_zoomed then
        local cols = t:get_size().cols
        local want = wezterm.GLOBAL.tree_w[key] or S.tree_width
        if not resized and TAB_COLS[key] == cols then
          wezterm.GLOBAL.tree_w[key] = info.width
        elseif info.width ~= want then
          gw:perform_action(act.AdjustPaneSize({ info.width > want and "Left" or "Right", math.abs(info.width - want) }), info.pane)
        end
        TAB_COLS[key] = cols
      end
    end
  end
end
wezterm.on("window-resized", function(window, pane)
  fit_trees(window, true)
  render_status(window, pane) -- タブの幅を割り振り直す
end)

-- update-status は窓が前に無いとほとんど呼ばれない。別のアプリを使っている間も通知とタブの表示を更新するため、
-- 1 秒ごとに自分で回す。
--   ・設定を読むときの Lua では時計が動かない(捨てられる)ので、窓の処理(イベント)の中で回し始める
--   ・設定を読み直すと、新しい Lua が回し始めた時点で古い Lua の回り方は止まる(tick_owner)
wezterm.GLOBAL.tick_gen = (wezterm.GLOBAL.tick_gen or 0) + 1
local TICK_GEN = wezterm.GLOBAL.tick_gen
local tick_started = false
local function tick()
  if wezterm.GLOBAL.tick_owner ~= TICK_GEN then tick_started = false return end
  local ok, windows = pcall(wezterm.gui.gui_windows)
  local cc_changed = false
  if ok then
    for i, gw in ipairs(windows) do
      if i == 1 then
        local ok2, ch = pcall(scan_cc, gw)
        cc_changed = ok2 and ch or cc_changed
      end
      pcall(fit_trees, gw, false)
      -- 右上を書き直すと、タブ(format-tab-title)も描き直される。Claude Code の状態が変わったときは必ず書き直す
      pcall(render_status, gw, gw:active_pane(), cc_changed)
    end
  end
  wezterm.time.call_after(1, tick)
end
local function start_tick()
  wezterm.GLOBAL.tick_owner = TICK_GEN
  if tick_started then return end
  tick_started = true
  wezterm.time.call_after(1, tick)
end
wezterm.on("window-config-reloaded", start_tick)
wezterm.on("update-status", start_tick)

----------------------------------------------------------------
-- リモートからの「Windows で開く」合図(OSC 1337 SetUserVar=wez_open)
--   リモートの wopen(bin/wopen)が "open|<パス>|<連番>" / "reveal|<パス>|<連番>" を送ってくる
----------------------------------------------------------------
-- 「Windows のアプリで開く」の扱い(拡張子ごと)
--   block   : 開かない。Windows では開く = 実行になる種類(exe・bat・ps1・lnk など)
--   caution : 開く前に確認する(最初に選ばれているのは「やめる」)。入っているアプリによっては実行される
--             スクリプト(py・sh など)と、マクロを含みうる Office(xlsm・docm など)
--   それ以外: そのまま開く
local OPEN_POLICY = {}
for _, e in ipairs({
  "exe", "com", "bat", "cmd", "ps1", "psm1", "psd1", "ps1xml", "psc1", "vbs", "vbe", "vb", "js", "jse",
  "wsf", "wsh", "msi", "msp", "mst", "scr", "hta", "cpl", "msc", "lnk", "pif", "reg", "jar", "url",
  "application", "appref-ms", "gadget", "inf", "scf", "chm", "settingcontent-ms", "iso", "img", "vhd", "vhdx",
  "appx", "msix", "appinstaller", "library-ms", "search-ms", "xll", "sys", "dll", "ocx",
  "ps2", "ps2xml", "psc2", "msh", "msh1", "msh2", "mshxml", "msh1xml", "msh2xml", "sct", "wsc", "shs", "shb",
  "hlp", "jnlp", "diagcab", "wsb", "website", "searchconnector-ms", "theme", "themepack", "desktopthemepack",
  "rdp", "ica", "xbap", "wll", "vsto", "appxbundle", "msixbundle",
}) do OPEN_POLICY[e] = "block" end
for _, e in ipairs({
  "py", "pyw", "pyz", "pyzw", "pyc", "pyo", "sh", "bash", "zsh", "ksh", "csh", "pl", "rb", "php", "tcl",
  "docm", "dotm", "xlsm", "xltm", "xlsb", "xlam", "xla", "pptm", "potm", "ppsm", "ppam", "sldm",
  "mdb", "mde", "accdb", "accde", "accda", "ade", "adp", "slk", "iqy", "one", "onepkg",
  -- 旧形式の Office(マクロを持てる)と rtf(OLE 埋め込み)
  "doc", "dot", "xls", "xlt", "ppt", "pot", "pps", "rtf",
}) do OPEN_POLICY[e] = "caution" end

-- path(リモートの / か Windows の \ 区切り)を開くときの扱い
local function open_policy(path)
  local ext = (path:match("%.([%w%-]+)$") or ""):lower()
  return OPEN_POLICY[ext] or "open", ext
end

-- リモートのパスが、Windows で別の意味に読まれないか(Windows で開く・表示するときだけ確かめる)。
-- Linux のファイル名は「/」と NUL 以外なら何でも使えるが、Windows では次のものが特別な意味を持つ:
--   ・: (別のデータの流れ・ドライブ)、" < > | ? * (コマンド行・ワイルドカード)、\ (区切り。UNC で外の共有へつながる)
--   ・名前の末尾の . と空白(Windows は落とす。evil.exe. が evil.exe として開かれ、拡張子の確認をすり抜ける)
--   ・制御文字(改行など)
local function safe_remote_path(p)
  -- % は Windows が環境変数として展開する(名前と違うファイルを開かせられる)ので弾く
  if p:find('[%c\\:"<>|%?%*%%]') then return false end
  for part in p:gmatch("[^/]+") do
    if part:match("[%. ]$") then return false end
  end
  return true
end

local function starts_with(s, pre)
  return s:sub(1, #pre) == pre
end

local function q(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(s)
  return ((s:gsub(".", function(c)
    local b, r = c:byte(), ""
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
    if #x < 6 then return "" end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
    return B64:sub(c + 1, c + 1)
  end) .. ({ "", "==", "=" })[#s % 3 + 1])
end

-- リモートで動かすコマンド。ssh はコマンドをリモートのログインシェルに読ませるので、中身を base64 にして
-- sh に渡す(フォルダ名などリモート由来の文字列が、fish など sh と書き方の違うシェルで別の意味に読まれないように)。
-- ログインシェルが読むのは「sh -c '…'」だけ(' の中はどのシェルでもそのままの文字)
local function remote_sh(cmd)
  return "sh -c 'eval \"$(echo " .. base64(cmd) .. " | base64 -d)\"'"
end

-- リモートのプログラムを新しいタブで動かす(× で閉じられる)。prog は PATH か ~/.local/bin から探す
local function remote_tab(window, rem, dir, prog, extra, title)
  -- そのフォルダの .git/config に書かれたコマンド(core.fsmonitor)を動かさない(nvim の設定と同じ)
  local cmd = "export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false; cd " .. q(dir)
    .. " && p=$(command -v " .. prog .. " || echo ~/.local/bin/" .. prog .. ") && exec \"$p\""
  if extra then cmd = cmd .. " " .. extra end
  local tab = window:mux_window():spawn_tab({ args = { "ssh", "-t", "--", rem.host, remote_sh(cmd) } })
  tab:set_title(title or prog)
end

-- 操作一覧(このリポジトリの nvim/keys.md)を別の窓のプレビューで開く
local function open_keys()
  local file = wezterm.config_dir .. "/../nvim/keys.md"
  local tab = wezterm.mux.spawn_window({ args = { "nvim", "-R", "-c", "nnoremap q <Cmd>qa!<CR>", file }, width = 110, height = 42 })
  tab:set_title("操作一覧")
end

-- Windows のファイルをリモートのフォルダへ送る(ツリーへのドラッグ&ドロップ)。
-- 端末に流れた文字列だけで手元のファイルが送られないよう、必ず確認してから送る
local function upload(window, pane, rem, dest, files)
  -- 説明は 1 行で切れるので短く。送るものは手元の場所(フルパス)ごと下に並べる
  -- (端末に流れた文字列で、手元の別のファイルを送らせる合図を偽装されても、ここで気づけるように)
  local desc = string.format("%s:%s へ %d 件(同名は上書き) Enter:配置 Esc:やめる", rem.name, dest, #files)
  local choices = { { id = "yes", label = "配置する" }, { id = "no", label = "やめる" } }
  for i, f in ipairs(files) do
    if i > 10 then
      table.insert(choices, { id = "no", label = string.format("    …ほか %d 件", #files - 10) })
      break
    end
    table.insert(choices, { id = "no", label = "    " .. f })
  end
  window:perform_action(act.InputSelector({
    title = "ファイルの配置",
    description = desc,
    choices = choices,
    action = wezterm.action_callback(function(_, p, id)
      if id ~= "yes" then return end
      -- 送っている間も WezTerm が止まらないよう、下に小さな pane を開いて送る(進み具合が見える)。
      -- うまくいったら「配置しました」と知らせて閉じる。失敗したら理由を残し、キーを押すと閉じる。
      -- (ファイル名は JSON にして base64 で渡す。PowerShell の命令の文字列に直接入れない)
      local payload = wezterm.json_encode({
        files = files, target = rem.host .. ":" .. dest .. "/",
        start = string.format("%s:%s へ %d 件を送っています…", rem.name, dest, #files),
        ok = string.format("%d 件を配置しました(%s:%s)", #files, rem.name, dest),
        ng = "配置に失敗しました。上の理由を確かめてください。何かキーを押すと閉じます",
      })
      local script = "[Console]::OutputEncoding=[Text.Encoding]::UTF8;"
        .. "$j=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" .. base64(payload) .. "'))|ConvertFrom-Json;"
        .. "Write-Host $j.start;"
        .. "& scp -r -- @($j.files) $j.target;"
        .. "if($LASTEXITCODE -eq 0){[Console]::Write([char]27+']777;notify;WezTerm;'+$j.ok+[char]7);Start-Sleep -Milliseconds 300;exit 0}"
        .. "Write-Host $j.ng;[void][Console]::ReadKey($true);exit 1"
      p:split({ direction = "Bottom", size = 6, args = { SHELL, "-NoLogo", "-NoProfile", "-EncodedCommand",
        base64((script:gsub(".", "%0\0"))) } })
    end),
  }), pane)
end

local function remote_to_windows(rem, p)
  for _, m in ipairs(rem.path_map) do
    local pre = m[1]:gsub("/$", "")
    if p == pre or starts_with(p, pre .. "/") then
      return (m[2]:gsub("[\\/]$", "")) .. p:sub(#pre + 1):gsub("/", "\\")
    end
  end
  if rem.fallback_root then
    return rem.fallback_root .. p:gsub("/", "\\")
  end
  return nil
end

-- 開く前の確かめ(拡張子の扱いに従う)。do_open は実際に開く処理
local function open_checked(window, pane, path, do_open)
  local policy, ext = open_policy(path)
  local name = path:match("([^/\\]+)$") or path
  if ext == "" then
    -- 拡張子が無い名前は、Windows が種類を補って別のファイル(payload に対する payload.cmd など)を実行しうるので開かない
    window:toast_notification("WezTerm", "拡張子が無いので開きません(種類を補って別のものが実行されるのを防ぐため): "
      .. name .. "(中を見るならツリーのダブルクリック、場所を見るなら「エクスプローラー」)", nil, 7000)
    return
  end
  if policy == "block" then
    window:toast_notification("WezTerm", "." .. ext .. " は Windows で開くと実行される種類なので開きません: " .. name
      .. "(中を見るならツリーのダブルクリック、場所を見るなら「エクスプローラー」)", nil, 7000)
    return
  elseif policy == "caution" then
    window:perform_action(act.InputSelector({
      title = "開く",
      description = string.format("%s を開きますか(.%s は、入っているアプリによっては実行されたり、マクロが動いたりします)"
        .. "  Enter:決定 Esc:やめる", name, ext),
      choices = { { id = "no", label = "やめる" }, { id = "yes", label = "Windows のアプリで開く" } },
      action = wezterm.action_callback(function(_, _, id) if id == "yes" then do_open() end end),
    }), pane)
    return
  end
  do_open()
end

-- 端末の中のリンク(OSC 8 / URL)を Ctrl+クリックで開くとき
--   ・http / https / mailto: 既定のブラウザ・メール(標準の動き)
--   ・file:(Claude Code などが出すファイルのリンク): 上と同じ拡張子の扱いで、Windows のアプリで開く
--   ・それ以外(ms-msdt: など、Windows でプログラムを動かせる種類): 開かない
wezterm.on("open-uri", function(window, pane, uri)
  if uri:match("^https?://") or uri:match("^mailto:") then return end
  local file = uri:match("^file://[^/]*(/.*)$")
  if file then
    file = file:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    file = file:gsub("^/(%a:)", "%1"):gsub("/", "\\")
    if file:match("^%a:\\") and not file:find('[%c"<>|%?%*%%]') and not file:sub(3):find(":", 1, true)
      and not file:match("[%. ]$") then
      open_checked(window, pane, file, function() wezterm.open_with(file) end)
      return false
    end
  end
  window:toast_notification("WezTerm", "このリンクは開きません: " .. uri:sub(1, 80), nil, 4000)
  return false
end)

local function open_allowed(rem, p)
  local list = rem.open_allowed
  if not list then
    list = {}
    for _, m in ipairs(rem.path_map) do table.insert(list, (m[1]:gsub("/$", "")) .. "/") end
  end
  for _, pre in ipairs(list) do
    if starts_with(p, pre) then return true end
  end
  return false
end

----------------------------------------------------------------
-- リモートから頼まれて、この PC の新しいタブで Claude Code を起動する(wopen --claude <ファイル>)
--   ・起動するのは Claude Code(.exe)だけ。権限のモードは付けない(この PC の Claude Code の設定のまま。既定は毎回確認)
--   ・起動する場所は設定で固定(ask_claude.cwd)。渡すのはファイルの場所だけで、中身はコマンド行に入れない
--   ・渡せるのは ask_claude.allowed の直下の .md だけ。続けて来た合図(interval 秒以内)は捨てる
--   ・ファイルは同期で後から届くことがあるので、見つからなければ少し待つ
----------------------------------------------------------------
local ASK = S.ask_claude
if ASK then ASK.allowed = as_list(ASK.allowed) end
-- 頼みごとのファイルとして受け付けるか(--claude と --close で同じ判定)。受け付けるならファイル名、断るなら nil と理由
local function ask_file(win_path, what)
  if not (ASK and ASK.cwd and #ASK.allowed > 0) then
    return nil, "Claude Code に頼む合図は、設定(local.lua の ask_claude)で使えるようにしていません"
  end
  if not win_path then return nil, "この PC のどこにあるファイルか分かりません(remotes の path_map を確かめてください)" end
  local name = win_path:match("([^\\]+)$") or ""
  local dir = win_path:sub(1, #win_path - #name - 1):lower()
  local allowed = false
  for _, a in ipairs(ASK.allowed) do
    if dir == a:gsub("/", "\\"):gsub("\\+$", ""):lower() then allowed = true end
  end
  if not allowed or not name:lower():match("%.md$") then
    return nil, "決まった場所の .md ではないので、" .. what .. ": " .. name
  end
  -- 名前は claude の引数(最初の指示)に入る。Windows で別の意味になりうる記号を含む名前は断る
  if win_path:find('[%c"%%^&!`<>|]') then return nil, "記号を含む名前なので、" .. what .. ": " .. name end
  return name
end
local function ask_claude(window, win_path)
  local function say(msg) window:toast_notification("WezTerm", msg, nil, 6000) end
  local name, why = ask_file(win_path, "Claude Code を起動しません")
  if not name then return say(why) end
  local exe = ASK.command or "claude.exe"
  if not exe:lower():match("%.exe$") then return say("ask_claude.command は .exe を指定してください") end
  local interval = ASK.interval or 30
  if os.time() - (wezterm.GLOBAL.tenv_ask_at or 0) < interval then
    return say("続けて来た合図なので無視しました(" .. interval .. " 秒あけてください): " .. name)
  end
  wezterm.GLOBAL.tenv_ask_at = os.time()
  local tries = 0
  local function start()
    local f = io.open(win_path, "r")
    if not f then
      tries = tries + 1
      if tries > 5 then return say("ファイルがこの PC に見つからないので、Claude Code を起動しません: " .. name) end
      return wezterm.time.call_after(2, start)
    end
    f:close()
    -- WezTerm は読めない作業フォルダを黙って捨てて別の場所で起動するので、先に確かめて止める
    if not pcall(wezterm.read_dir, ASK.cwd) then
      return say("作業フォルダ(ask_claude.cwd)が読めないので、Claude Code を起動しません: " .. ASK.cwd)
    end
    wezterm.log_info("ask_claude: cwd=" .. ASK.cwd .. " file=" .. win_path)
    -- spawn_tab は args と cwd を一緒に渡すと cwd を捨て、前に出ている pane の場所で開く(20240203 時点)。
    -- wezterm cli spawn なら cwd が効く。シェルは通さない
    local argv = { wezterm.executable_dir .. "\\wezterm.exe", "cli", "spawn",
      "--window-id", tostring(window:window_id()), "--cwd", ASK.cwd, "--", exe }
    if ASK.remote_control then
      table.insert(argv, "--remote-control")
      table.insert(argv, ASK.remote_control)
    end
    table.insert(argv, "次のファイルを読んで、書かれている依頼を進めてください: " .. win_path)
    local ok, out, err = wezterm.run_child_process(argv)
    if not ok then return say("Claude Code のタブを開けませんでした: " .. tostring(err)) end
    local id = tonumber((out or ""):match("%d+"))
    local p = id and wezterm.mux.get_pane(id)
    if p then p:tab():set_title("依頼: " .. name) end
    -- wopen --close で閉じられるように、ファイルと pane を覚える(WezTerm を終えると忘れる)
    if id then
      local panes = wezterm.GLOBAL.tenv_ask_panes or {}
      panes[win_path:lower()] = id
      wezterm.GLOBAL.tenv_ask_panes = panes
    end
  end
  start()
end

-- wopen --close <ファイル>: そのファイルを渡して開いた pane だけを閉じる。覚えていないもの・もう無いものは閉じずに知らせる
local function ask_close(window, win_path)
  local function say(msg) window:toast_notification("WezTerm", msg, nil, 6000) end
  local name, why = ask_file(win_path, "閉じません")
  if not name then return say(why) end
  local panes = wezterm.GLOBAL.tenv_ask_panes or {}
  local id = panes[win_path:lower()]
  if not id then return say("このファイルで開いたタブを覚えていないので、閉じません: " .. name) end
  panes[win_path:lower()] = nil
  wezterm.GLOBAL.tenv_ask_panes = panes
  if not wezterm.mux.get_pane(id) then return say("このファイルで開いたタブは、もうありません: " .. name) end
  local ok, _, err = wezterm.run_child_process({ wezterm.executable_dir .. "\\wezterm.exe", "cli", "kill-pane", "--pane-id", tostring(id) })
  if not ok then return say("タブを閉じられませんでした: " .. tostring(err)) end
  -- 閉じたことは知らせない(デバッグ表示 Ctrl+Shift+L にだけ出す)
  wezterm.log_info("ask_claude: closed pane " .. id .. " file=" .. win_path)
end

wezterm.on("user-var-changed", function(window, pane, name, value)
  if name ~= "wez_open" then return end
  -- 合言葉が合わない合図は捨てる(端末に流れただけの文字列からは来ない)。知らせるのは 1 分に 1 回まで
  local kind, path, tok = value:match("^(%a+)|(/.-)|%d+|([%x,]+)$")
  if not kind or not token_ok(tok) then
    if os.time() - (wezterm.GLOBAL.tenv_bad_token_at or 0) > 60 then
      wezterm.GLOBAL.tenv_bad_token_at = os.time()
      window:toast_notification("WezTerm", "合言葉の無い合図を無視しました(リモートは Shift+Alt+O で開き直すと使えます)", nil, 6000)
    end
    return
  end
  if path:find("%.%.") then return end
  -- Windows で開く・表示するときだけ、Windows で別の意味になる文字を確かめる。
  -- 編集・Git はリモートの中だけで動くので、制御文字だけを確かめる(配置は「配置先 改行 Windows のパス...」の形)
  if kind == "open" or kind == "reveal" or kind == "claude" or kind == "close" then
    if not safe_remote_path(path) then
      window:toast_notification("WezTerm", "Windows では扱えない文字を含む名前です(: \" < > | ? * \\ や、末尾の . と空白)。"
        .. "ツリーのダブルクリック(エディタ)なら開けます", nil, 6000)
      return
    end
  elseif (kind == "upload" and (path:match("^[^\n]*") or "") or path):find("%c") then
    return
  end

  if kind == "settings" then
    open_settings(window)
    return
  elseif kind == "keys" then
    open_keys()
    return
  end

  -- ここから先はリモートのパスを扱う。合図を送ってきた pane のリモートで処理する
  local rem = remote_of(pane)
  if not rem then
    window:toast_notification("WezTerm", "設定(local.lua)の remotes に無い接続先です", nil, 4000)
    return
  end
  if kind == "edit" then
    -- nomodeline: ファイルの中の「vim の設定の行」を読まない(よそのファイルを開くため)
    remote_tab(window, rem, path:match("^(.*)/[^/]*$") or "/", "nvim", "--cmd 'set nomodeline' -- " .. q(path), "編集: " .. (path:match("([^/]+)$") or path))
    return
  elseif kind == "git" then
    remote_tab(window, rem, path, "lazygit", nil, "Git: " .. (path:match("([^/]+)/?$") or path))
    return
  elseif kind == "upload" then
    -- 送り元は、ドライブ(C:\...)かネットワークの場所(\\server\...)。
    -- 鍵や認証の情報の置き場所(.ssh・.gnupg・.aws・.azure・.kube・.docker・Windows の資格情報・この仕組みの合言葉)は送らない
    local dest, files, refused = nil, {}, 0
    local SECRET_DIR = { [".ssh"] = true, [".gnupg"] = true, [".aws"] = true, [".azure"] = true, [".kube"] = true,
      [".docker"] = true, [".claude"] = true, [".config"] = true, [".password-store"] = true }
    local SECRET_PATH = { "\\appdata\\roaming\\microsoft\\credentials\\", "\\appdata\\local\\microsoft\\credentials\\",
      "\\appdata\\roaming\\microsoft\\protect\\", "\\appdata\\local\\tenv\\",
      "\\.git-credentials\\", "\\.netrc\\", "\\.pgpass\\", "\\.npmrc\\",
      "\\appdata\\local\\google\\chrome\\user data\\", "\\appdata\\local\\microsoft\\edge\\user data\\",
      "\\appdata\\roaming\\mozilla\\" }
    -- ホーム・ドライブ直下・AppData など、丸ごと送ると鍵や認証の情報ごと再帰で送られる場所(ちょうどその階層)
    local DANGER_ROOT = { "^%a:$", "^%a:\\users$", "^%a:\\users\\[^\\]+$",
      "^%a:\\users\\[^\\]+\\appdata$", "^%a:\\users\\[^\\]+\\appdata\\local$",
      "^%a:\\users\\[^\\]+\\appdata\\locallow$", "^%a:\\users\\[^\\]+\\appdata\\roaming$",
      "^%a:\\windows$", "^%a:\\programdata$" }
    -- 送り元を送ってよいか(鍵や認証の置き場所・丸ごと危険な場所・短い名前ですり抜けるものを断る)
    local function refuse_src(line)
      if not (line:match("^%a:[\\/]") or line:match("^\\\\[^\\]")) then return true end
      if line:find('[%c"<>|%?%*]') or line:sub(3):find(":", 1, true) then return true end
      -- 小文字・/ を \・各部品の末尾の . と空白を外す(.ssh. ですり抜けさせない)・\ の重複と末尾を外す
      local norm = line:lower():gsub("/", "\\"):gsub("([^\\]+)", function(p) return (p:gsub("[%. ]+$", "")) end)
      norm = norm:gsub("\\+", "\\"):gsub("\\+$", "")
      for part in norm:gmatch("[^\\]+") do
        if SECRET_DIR[part] or part:match("~%d+$") then return true end -- 鍵の置き場所 / 8.3 の短い名前
      end
      local probe = norm .. "\\"
      for _, s in ipairs(SECRET_PATH) do if probe:find(s, 1, true) then return true end end
      for _, pat in ipairs(DANGER_ROOT) do if norm:match(pat) then return true end end
      return false
    end
    for line in path:gmatch("[^\n]+") do
      if not dest then
        dest = line
      elseif refuse_src(line) then
        refused = refused + 1
      else
        table.insert(files, line)
      end
    end
    if refused > 0 then
      window:toast_notification("WezTerm", refused .. " 件は送りません(鍵や認証の情報の置き場所: .ssh・.aws など)", nil, 6000)
    end
    -- 配置先はリモートのシェルが解釈することがある(古い scp)。シェルで意味を持つ記号を含む配置先には送らない
    if dest and dest:find("[$`;&|<>(){}\\\"'*?!]") then
      window:toast_notification("WezTerm", "配置先の名前に記号($ ; & | ` など)が含まれるので送りません", nil, 6000)
      return
    end
    -- 確認が出ている間に来た次の合図は無視する(続けて送りつけられても、うっかり Enter で送らないように)
    if dest and #files > 0 and os.time() - (wezterm.GLOBAL.tenv_upload_at or 0) > 3 then
      wezterm.GLOBAL.tenv_upload_at = os.time()
      upload(window, pane, rem, dest, files)
    end
    return
  end

  if not open_allowed(rem, path) then
    window:toast_notification("WezTerm", "開けない場所です: " .. path, nil, 4000)
    return
  end
  local win_path = remote_to_windows(rem, path)

  if kind == "open" then
    local function do_open()
      if rem.open_command then
        wezterm.background_child_process(rem.open_command(path, win_path))
      elseif win_path then
        -- Windows の「開く」(既定のアプリ)。explorer.exe の引数の読み方(, で区切るなど)を通さない
        wezterm.open_with(win_path)
      end
    end
    open_checked(window, pane, path, do_open)
  elseif kind == "claude" then
    ask_claude(window, win_path)
  elseif kind == "close" then
    ask_close(window, win_path)
  elseif kind == "reveal" and win_path then
    if win_path:find(",", 1, true) then
      -- explorer.exe は , を区切りとして読むので、, を含むパスは場所(親のフォルダ)を開くだけにする
      wezterm.open_with(win_path:match("^(.*)\\[^\\]*$") or win_path)
    else
      wezterm.background_child_process({ "explorer.exe", "/select," .. win_path })
    end
  end
end)

----------------------------------------------------------------
-- キー
----------------------------------------------------------------
local function is_remote(pane)
  return is_remote_name(pane:get_foreground_process_name())
end

-- リモート(ssh)の pane では tmux へ seq をそのまま送り、ローカルの pane では local_action を実行する
local function dual(seq, local_action)
  return wezterm.action_callback(function(win, pane)
    if is_remote(pane) then
      win:perform_action(act.SendString(seq), pane)
    else
      win:perform_action(local_action, pane)
    end
  end)
end

-- ツリー(nvim + neo-tree)を左端に出す / 出ていればそこへ移る / ツリーにいれば閉じる
wezterm.GLOBAL.tree_panes = wezterm.GLOBAL.tree_panes or {}
local function toggle_tree_local(win, pane)
  local tab = pane:tab()
  local key = tostring(tab:tab_id())
  local tree_id = wezterm.GLOBAL.tree_panes[key]
  if tree_id then
    for _, p in ipairs(tab:panes()) do
      if p:pane_id() == tree_id then
        if p:pane_id() == pane:pane_id() then
          win:perform_action(act.CloseCurrentPane({ confirm = false }), p)
          wezterm.GLOBAL.tree_panes[key] = nil
        else
          p:activate()
        end
        return
      end
    end
  end
  local cwd = pane:get_current_working_dir()
  local new = pane:split({
    direction = "Left",
    top_level = true,
    size = S.tree_width, -- 桁数
    cwd = cwd and cwd.file_path:gsub("^/(%a:)", "%1") or nil,
    args = { "nvim" },
    -- TENV_MAIN_PANE: ツリーから開いたファイルは、この pane の上にエディタを作って開く
    set_environment_variables = { NVIM_TREE_ONLY = "1", TENV_MAIN_PANE = tostring(pane:pane_id()) },
  })
  wezterm.GLOBAL.tree_panes[key] = new:pane_id()
  wezterm.GLOBAL.tree_w[key] = S.tree_width -- 開くときはいつも既定の幅
end

local function sh_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- リモート: tenv-open がセッションを用意(無ければツリー + 起動コマンドの並びを作る)して attach する
-- resume_ids: 再開する Claude Code の会話(前の作業を再開)
local function remote_open_command(rem, dir, resume_ids)
  local cmd = "~/.local/bin/tenv-open"
  for _, id in ipairs(resume_ids or {}) do
    if id:match("^[%x%-]+$") then cmd = cmd .. " -r " .. id end
  end
  if S.start_command then cmd = cmd .. " -c " .. sh_quote(S.start_command) end
  if rem.attach_with then cmd = cmd .. " -a " .. sh_quote(rem.attach_with) end
  if not S.open_with_tree then cmd = cmd .. " -T" end
  cmd = cmd .. " -w " .. tostring(math.floor(S.tree_width)) .. " -f " .. (S.tree_width_fixed and "1" or "0")
  -- 合言葉を、そのリモートの tmux に渡す(wopen / tenv-cc-state が合図に付ける)
  if TOKEN then cmd = cmd .. " -k " .. TOKEN end
  return remote_sh(cmd .. " " .. sh_quote(dir))
end

-- ローカル: 新しいタブで開き、ツリーと起動コマンドの並びにする。
-- resume_ids があれば、その Claude Code の会話を再開する(2 つ目からは右に pane を分けて並べる)
local function open_local_folder(win, dir, resume_ids)
  local tab, pane = win:mux_window():spawn_tab({ cwd = dir })
  -- タブ名は開いたフォルダ名に固定する(エディタの pane は別のフォルダにいることがあるため)
  tab:set_title(folder_name(dir) or dir)
  local ids = {}
  for _, id in ipairs(resume_ids or {}) do
    if id:match("^[%x%-]+$") then table.insert(ids, id) end
  end
  if #ids > 0 then
    local base = S.start_command or "claude"
    local p = pane
    for i, id in ipairs(ids) do
      if i > 1 then p = p:split({ direction = "Right", cwd = dir }) end
      p:send_text(base .. " --resume " .. id .. "\r")
    end
  elseif S.start_command then
    pane:send_text(S.start_command .. "\r")
  end
  if S.open_with_tree then
    toggle_tree_local(win, pane)
    pane:activate()
  end
end

-- 指示を出した日時(bin/tenv-cc-state が残す)を「今日 9:12」「昨日 18:40」「10/21 14:03」の形に
local function when_label(epoch)
  if not epoch then return "" end
  local d, now = os.date("*t", epoch), os.date("*t")
  local days = math.floor((os.time({ year = now.year, month = now.month, day = now.day, hour = 0 })
    - os.time({ year = d.year, month = d.month, day = d.day, hour = 0 })) / 86400 + 0.5)
  local hm = string.format("%d:%02d", d.hour, d.min)
  if days == 0 then return "今日 " .. hm
  elseif days == 1 then return "昨日 " .. hm
  elseif d.year == now.year then return string.format("%d/%d %s", d.month, d.day, hm) end
  return string.format("%d/%d/%d", d.year, d.month, d.day)
end

local function prompt_key(path)
  return (path:lower():gsub("[\\/:]", "%%"))
end

local function local_last_prompt(path)
  local f = io.open(STATE_HOME .. "\\last-prompt\\" .. prompt_key(path), "r")
  if not f then return nil end
  local t = tonumber(f:read("*l") or "")
  f:close()
  return t
end

-- フォルダの一覧は 3 段の字下げ: 接続先(Linux / ローカルPC)> 一覧の場所(親フォルダの名前と場所)> フォルダ
-- (再開の画面のフォルダの一覧も同じ見出しを使う。open_resume_picker で渡す)
local HOST_LABELS = { remote = "Linux", ["local"] = "ローカルPC" }

-- 接続先の行。note: リモートが 2 台以上のときの名前・つながらないときの理由
local function host_label(icon, name, note)
  return wezterm.format({
    { Foreground = { Color = T.accent } }, { Attribute = { Intensity = "Bold" } }, { Text = icon .. " " .. name },
    { Attribute = { Intensity = "Normal" } }, { Foreground = { Color = T.dim } }, { Text = note and ("  " .. note) or "" },
  })
end

-- 一覧の場所の行: 親フォルダの名前 + 場所(控えめな色)
local function root_label(root)
  local name = root:match("([^\\/]+)[\\/]*$") or root
  local pad = math.max(2, 16 - wezterm.column_width(name))
  return wezterm.format({
    { Foreground = { Color = T.accent } }, { Text = "   " .. nf.md_folder .. " " .. name .. string.rep(" ", pad) },
    { Foreground = { Color = T.dim } }, { Text = root },
  })
end

-- フォルダの行: フォルダ名 + 指示を出した日時(控えめな色)
local function folder_label(name, epoch)
  local pad = math.max(2, 32 - wezterm.column_width(name))
  return wezterm.format({
    { Foreground = { Color = T.fg } }, { Text = "       " .. name .. string.rep(" ", pad) },
    { Foreground = { Color = T.dim } }, { Text = when_label(epoch) },
  })
end

-- リモートのフォルダ(projects_root の直下)と、指示を出した日時を 1 回の ssh でまとめて取るコマンド。
-- 出力は「#<TAB>一覧の場所」の行と、その下に「フォルダ<TAB>日時」の行(再開の画面 resume.lua も同じ形で読む)
local function remote_list_cmd(rem)
  local roots = {}
  for _, r in ipairs(rem.projects_root) do table.insert(roots, r == "~" and "~" or sh_quote(r)) end
  local script = "st=${XDG_STATE_HOME:-$HOME/.local/state}/tenv/last-prompt; for r in " .. table.concat(roots, " ")
    .. "; do cd \"$r\" 2>/dev/null || continue; printf '#\\t%s\\n' \"$PWD\"; for d in */; do p=\"$PWD/${d%/}\";"
    .. " k=$(printf '%s' \"$p\" | tr 'A-Z' 'a-z' | sed 's#[/\\\\:]#%#g'); printf '%s\\t%s\\n' \"$p\" \"$(cat \"$st/$k\" 2>/dev/null)\"; done; done"
  return remote_sh(script)
end

local function remote_choices(choices, ri, rem)
  local ok, out = wezterm.run_child_process({ "ssh", "-o", "ConnectTimeout=5", "--", rem.host, remote_list_cmd(rem) })
  -- 接続先の名前は、リモートが 2 台以上のときだけ添える(見分けるため)
  local note = #S.remotes > 1 and rem.name or nil
  if not ok then note = (note and note .. "  " or "") .. "(つながりません)" end
  table.insert(choices, { id = "-", label = host_label(nf.md_server_network, HOST_LABELS.remote, note) })
  if not ok then return end
  -- フォルダ名はリモート由来。改行や制御文字を含む名前(偽の行を作れる)と、一覧の場所の外を指すものは出さない
  local root
  for line in out:gmatch("[^\r\n]+") do
    local path, t = line:match("^(.-)\t(.*)$")
    if path == "#" then
      root = t
      table.insert(choices, { id = "-", label = root_label(t) })
    elseif path and root and starts_with(path, root .. "/") and not path:find("%c") then
      local name = path:match("([^/]+)$")
      if name and not name:match("^[_.]") then
        table.insert(choices, { id = "R" .. ri .. "\t" .. path, label = folder_label(name, tonumber(t)) })
      end
    end
  end
end

-- この PC のフォルダ(local_projects_root の直下)と、指示を出した日時: { { root, items = { { path, name, t } } } }
local function local_folders()
  local roots = #S.local_projects_root > 0 and S.local_projects_root or { wezterm.home_dir }
  local list = {}
  for _, root in ipairs(roots) do
    root = root:gsub("[\\/]$", "")
    local items = {}
    for _, d in ipairs(wezterm.glob(root .. "\\*\\")) do
      local name = d:gsub("[\\/]$", ""):match("([^\\/]+)$")
      if name and not name:match("^[_.]") then
        local path = root .. "\\" .. name
        table.insert(items, { path = path, name = name, t = local_last_prompt(path) })
      end
    end
    table.insert(list, { root = root, items = items })
  end
  return list
end

local function local_choices(choices)
  table.insert(choices, { id = "-", label = host_label(nf.md_monitor, HOST_LABELS["local"]) })
  for _, g in ipairs(local_folders()) do
    table.insert(choices, { id = "-", label = root_label(g.root) })
    for _, it in ipairs(g.items) do
      table.insert(choices, { id = "L\t" .. it.path, label = folder_label(it.name, it.t) })
    end
  end
end

-- フォルダを開く: 接続先ごとに見出しを付けた一覧から選ぶ。リモートは ssh + tmux、ローカルは新しいタブ
--   with_remotes = true: リモート(登録した順)+ この PC / false: この PC だけ
local function select_folder(win, pane, with_remotes)
  local choices = {}
  if with_remotes then
    for ri, rem in ipairs(S.remotes) do remote_choices(choices, ri, rem) end
  end
  local_choices(choices)

  win:perform_action(act.InputSelector({
    title = "フォルダを開く",
    fuzzy = true,
    fuzzy_description = "フォルダ: ",
    choices = choices,
    action = wezterm.action_callback(function(w, p, id)
      if not id or id == "-" then return end
      local kind, path = id:match("^(%w+)\t(.*)$")
      if kind == "L" then
        open_local_folder(w, path)
      elseif kind then
        local rem = S.remotes[tonumber(kind:sub(2))]
        w:perform_action(act.SpawnCommandInNewTab({ args = { "ssh", "-t", "--", rem.host, remote_open_command(rem, path) } }), p)
      end
    end),
  }), pane)
end

-- タブを選ぶ: タブが多くて題名が縮んだときに、題名で探して移る(Shift+Alt+L)
local function select_tab(win, pane)
  local choices = {}
  for _, info in ipairs(win:mux_window():tabs_with_info()) do
    local t, p = info.tab, info.tab:active_pane()
    local icon, title = tab_label({ tab_title = t:get_title(), active_pane = { foreground_process_name = fg_name(p),
      title = p:get_title(), current_working_dir = p:get_current_working_dir() } })
    local state = TAB_CC[t:tab_id()]
    local label = string.format("%2d  %s  %s", info.index + 1, icon, title)
    if state then label = label .. "   " .. CC_LOOK[state[1]].icon .. " " .. CC_LOOK[state[1]].label end
    table.insert(choices, { id = tostring(info.index), label = label })
  end
  win:perform_action(act.InputSelector({
    title = "タブを選ぶ",
    fuzzy = true,
    fuzzy_description = "タブ: ",
    choices = choices,
    action = wezterm.action_callback(function(w, p, id)
      if id then w:perform_action(act.ActivateTab(tonumber(id)), p) end
    end),
  }), pane)
end

----------------------------------------------------------------
-- 前の作業を再開(Claude Code)。画面は nvim(nvim/lua/tenv/resume.lua)が新しいタブで出す。
-- 同じ画面にフォルダを開く一覧(Shift+Alt+O と同じ)もあり、Tab で切り替える
--   mode = "startup": 起動時。窓をこの画面のタブ 1 つで始める(gui-startup)。前回開いていた作業があれば
--                    再開(claude_resume_on_startup)、無ければフォルダの一覧(open_on_startup)から。
--                    何も開かずに閉じたとき・出すものが無いときは、いつもの並びのタブを開かせる(tenv_resume_home)
--   mode = "manual" : Shift+Alt+R・「＋」から
-- 選んだ結果は、合言葉付きで tenv_resume として返ってくる: { items = { { r = リモートの番号 | nil, cwd, ids } } }
-- (フォルダを開くときは ids が空)
----------------------------------------------------------------
local RESUME_TITLE = S.claude_resume and "前の作業" or "フォルダを開く"
local function resume_spawn(mode)
  local remotes = {}
  for i, r in ipairs(S.remotes) do
    table.insert(remotes, { i = i, name = r.name, host = r.host, list = remote_list_cmd(r) })
  end
  return {
    cwd = wezterm.home_dir,
    args = { "nvim", "--cmd", "let g:tenv_not_tree = 1", "--cmd", "let g:tenv_resume = 1",
      "-c", "lua require('tenv.resume').run()" },
    set_environment_variables = {
      TENV_RESUME = wezterm.json_encode({
        mode = mode, days = S.claude_resume_days, remotes = remotes, folders = local_folders(), host_labels = HOST_LABELS,
        resume = S.claude_resume and true or false,
        startup_resume = (S.claude_resume and S.claude_resume_on_startup) and true or false,
        startup_folders = S.open_on_startup and true or false,
      }),
    },
  }
end

local function open_resume_picker(mux_win, mode)
  mux_win:spawn_tab(resume_spawn(mode)):set_title(RESUME_TITLE)
end

-- いつもの並びのタブ: 左にツリー、右にシェル。HOME_ROOT で開いたタブ(tab, pane)を並べる
local HOME_ROOT = S.local_projects_root[1] or wezterm.home_dir
local function setup_home_tab(tab, pane)
  tab:set_title(folder_name(HOME_ROOT) or HOME_ROOT)
  if S.tree_on_startup then
    toggle_tree_local(nil, pane)
    pane:activate()
  end
end

wezterm.on("user-var-changed", function(window, pane, name, value)
  if name ~= "tenv_resume" and name ~= "tenv_resume_show" and name ~= "tenv_resume_home" then return end
  -- 再開の画面はこの PC の nvim で動く。リモートの pane からの合図は受け付けない
  if is_remote_name(fg_name(pane)) then return end
  if name == "tenv_resume_show" then
    pcall(function() pane:tab():activate() end)
    return
  end
  if name == "tenv_resume_home" then
    setup_home_tab(window:mux_window():spawn_tab({ cwd = HOME_ROOT }))
    return
  end
  local ok, req = pcall(wezterm.json_parse, value)
  if not ok or type(req) ~= "table" or not token_ok(req.token) or type(req.items) ~= "table" then return end
  for _, it in ipairs(req.items) do
    if type(it) == "table" and type(it.cwd) == "string" and not it.cwd:find("%c") then
      local ids = {}
      for _, id in ipairs(type(it.ids) == "table" and it.ids or {}) do
        if type(id) == "string" and id:match("^[%x%-]+$") then table.insert(ids, id) end
      end
      if it.r then
        local rem = S.remotes[tonumber(it.r) or 0]
        if rem then
          window:mux_window():spawn_tab({ args = { "ssh", "-t", "--", rem.host, remote_open_command(rem, it.cwd, ids) } })
        end
      else
        open_local_folder(window, it.cwd, ids)
      end
    end
  end
end)

-- タブバーの「＋」: 新しいタブ・フォルダを開く・前の作業を再開・タブを選ぶ
wezterm.on("new-tab-button-click", function(window, pane, button)
  if button ~= "Left" then return end
  local choices = { { id = "tab", label = "新しいタブ" }, { id = "open", label = "フォルダを開く(Shift+Alt+O)" } }
  if S.claude_resume then
    table.insert(choices, { id = "resume", label = "前の作業を再開(Claude Code・Shift+Alt+R)" })
  end
  table.insert(choices, { id = "tabs", label = "タブを選ぶ(Shift+Alt+L)" })
  window:perform_action(act.InputSelector({
    title = "開く",
    description = "開くものを選ぶ   Enter・数字・クリック: 決定   Esc: やめる",
    choices = choices,
    action = wezterm.action_callback(function(w, p, id)
      if id == "tab" then
        w:perform_action(act.SpawnTab("CurrentPaneDomain"), p)
      elseif id == "open" then
        select_folder(w, p, true)
      elseif id == "resume" then
        open_resume_picker(w:mux_window(), "manual")
      elseif id == "tabs" then
        select_tab(w, p)
      end
    end),
  }), pane)
  return false
end)


-- 起動した窓を、今の画面の window_scale の大きさにして中央に置く
local function fit_to_screen(mux_win)
  if not S.window_scale then return end
  local gui = mux_win:gui_window()
  local ok, screens = pcall(wezterm.gui.screens)
  if not gui or not ok then return end
  local s = screens.active
  local w, h = math.floor(s.width * S.window_scale), math.floor(s.height * S.window_scale)
  gui:set_inner_size(w, h)
  gui:set_position(s.x + math.floor((s.width - w) / 2), s.y + math.floor((s.height - h) / 2))
end

-- 起動した最初の画面(コマンドを指定して起動されたときは何もしない)
--   起動時の画面を出すなら、そのタブ 1 つで始める(閉じるといつもの並びのタブになる)。出さないなら、いつもの並び
wezterm.on("gui-startup", function(cmd)
  if cmd and cmd.args then
    local _, _, w = wezterm.mux.spawn_window(cmd)
    fit_to_screen(w)
    return
  end
  -- 前回開いていた Claude Code の作業があれば再開の画面を、無ければフォルダを開く画面を出す(同じ画面。Tab で切り替え)
  if (S.claude_resume and S.claude_resume_on_startup) or S.open_on_startup then
    local tab, _, w = wezterm.mux.spawn_window(resume_spawn("startup"))
    tab:set_title(RESUME_TITLE)
    fit_to_screen(w)
    return
  end
  local tab, pane, w = wezterm.mux.spawn_window({ cwd = HOME_ROOT })
  fit_to_screen(w)
  setup_home_tab(tab, pane)
end)

local function cycle_theme()
  return wezterm.action_callback(function()
    local n = theme_index % #THEMES + 1
    local f = io.open(THEME_FILE, "w")
    if f then f:write(tostring(n)); f:close() end
    wezterm.reload_configuration()
  end)
end

-- Claude Code の改行。mods = 押したキー(Claude Code 以外のローカルの pane にはそのまま渡す)
local function newline_key(mods)
  return wezterm.action_callback(function(win, pane)
    local b = basename(pane:get_foreground_process_name())
    if is_remote(pane) or b == "claude.exe" or b == "node.exe" then
      win:perform_action(act.SendString("\x1b\r"), pane)
    else
      win:perform_action(act.SendKey({ key = "Enter", mods = mods }), pane)
    end
  end)
end

local SA = "SHIFT|ALT"
config.keys = {
  -- tmux と同じ操作(リモートでは tmux へ、ローカルでは WezTerm の pane へ)
  { key = "phys:Minus", mods = SA, action = dual("\x1b=", act.SplitVertical({ domain = "CurrentPaneDomain" })) },
  { key = "phys:Semicolon", mods = SA, action = dual("\x1b+", act.SplitHorizontal({ domain = "CurrentPaneDomain" })) },
  { key = "phys:Equal", mods = SA, action = dual("\x1b+", act.SplitHorizontal({ domain = "CurrentPaneDomain" })) },
  { key = "phys:W", mods = SA, action = dual("\x1bW", act.CloseCurrentPane({ confirm = true })) },
  { key = "phys:Z", mods = SA, action = dual("\x1bZ", act.TogglePaneZoomState) },
  { key = "UpArrow", mods = SA, action = dual("\x1b[1;4A", act.AdjustPaneSize({ "Up", 3 })) },
  { key = "DownArrow", mods = SA, action = dual("\x1b[1;4B", act.AdjustPaneSize({ "Down", 3 })) },
  { key = "RightArrow", mods = SA, action = dual("\x1b[1;4C", act.AdjustPaneSize({ "Right", 3 })) },
  { key = "LeftArrow", mods = SA, action = dual("\x1b[1;4D", act.AdjustPaneSize({ "Left", 3 })) },
  { key = "phys:E", mods = SA, action = wezterm.action_callback(function(win, pane)
      if is_remote(pane) then win:perform_action(act.SendString("\x1bE"), pane) else toggle_tree_local(win, pane) end
    end) },

  -- WezTerm だけの操作
  -- Shift+Alt+O: リモートとこの PC のフォルダ(リモートを設定していなければ、この PC だけ)/ P: この PC だけ
  { key = "phys:O", mods = SA, action = wezterm.action_callback(function(win, pane) select_folder(win, pane, true) end) },
  -- Shift+Alt+R: 前の作業を再開(Claude Code)
  { key = "phys:R", mods = SA, action = wezterm.action_callback(function(win)
      if S.claude_resume then open_resume_picker(win:mux_window(), "manual")
      else win:toast_notification("WezTerm", "前の作業を再開は、設定(claude_resume)で止めてあります", nil, 4000) end
    end) },
  { key = "phys:P", mods = SA, action = wezterm.action_callback(function(win, pane) select_folder(win, pane, false) end) },
  { key = "phys:N", mods = SA, action = act.SpawnTab("CurrentPaneDomain") },
  { key = "phys:T", mods = SA, action = cycle_theme() },
  { key = "phys:K", mods = SA, action = act.ActivateCommandPalette },
  { key = "phys:L", mods = SA, action = wezterm.action_callback(select_tab) },
  { key = "phys:S", mods = SA, action = dual("\x1bS", act.Nop) }, -- tmux のステータス行を出す / 隠す

  -- コピー/貼り付けを VS Code に寄せる
  -- Ctrl+C: 選択中ならコピー、選択が無ければ今までどおり中断(Ctrl+C)を送る
  { key = "c", mods = "CTRL", action = wezterm.action_callback(function(win, pane)
      local sel = win:get_selection_text_for_pane(pane)
      if sel ~= "" then
        win:perform_action(act.CopyTo("Clipboard"), pane)
        win:perform_action(act.ClearSelection, pane)
      else
        win:perform_action(act.SendKey({ key = "c", mods = "CTRL" }), pane)
      end
    end) },
  -- Ctrl+V: どこでもクリップボードの文字を貼り付ける(Windows Terminal と同じ)。
  -- Claude Code への画像の貼り付けは Alt+V(Windows の Claude Code の割り当て)を使う
  { key = "v", mods = "CTRL", action = act.PasteFrom("Clipboard") },
  -- Shift+Enter / Alt+Enter: Claude Code の改行(tmux を挟んでも届くよう Esc+Enter として送る)。
  -- Alt+Enter は WezTerm の標準では全画面の切り替えなので、改行に置き換える。
  -- PowerShell では Esc が「行の取り消し」になるので、Claude Code 以外のローカルの pane には押したキーのまま渡す
  { key = "Enter", mods = "SHIFT", action = newline_key("SHIFT") },
  { key = "Enter", mods = "ALT", action = newline_key("ALT") },
}

config.mouse_bindings = {
  -- 右クリック: 選択中ならコピー、そうでなければ貼り付け(Windows Terminal と同じ)。
  -- tmux / nvim がマウスを使っているときは、そちらに届く(ツリーの右クリックメニューはこちら)
  { event = { Down = { streak = 1, button = "Right" } }, mods = "NONE",
    action = wezterm.action_callback(function(win, pane)
      local sel = win:get_selection_text_for_pane(pane)
      if sel ~= "" then
        win:perform_action(act.CopyTo("Clipboard"), pane)
        win:perform_action(act.ClearSelection, pane)
      else
        win:perform_action(act.PasteFrom("Clipboard"), pane)
      end
    end) },
}

return config
