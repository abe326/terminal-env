-- terminal-env: Neovim の設定(Windows とリモートの Linux 機で共用)
-- Windows は %LOCALAPPDATA%\nvim、Linux は ~/.config/nvim にこのフォルダをリンクして使う
--
-- 主な用途は「ツリー専用の pane」。NVIM_TREE_ONLY=1 で起動すると neo-tree だけを全面に出す
-- (tmux の Shift+Alt+E / WezTerm の Shift+Alt+E がこの形で起動する)。
-- ファイルの右クリックで「アプリで開く」「エクスプローラー」などのメニューを出す。
-- Windows のエクスプローラーからファイルをドロップすると、選んでいるフォルダに配置する。

local is_win = vim.fn.has("win32") == 1
-- Windows では、ツリーから開いたタブ・窓・エディタの pane が NVIM_TREE_ONLY を引き継いでしまう。
-- ツリーから起動する nvim には --cmd で g:tenv_editor / g:tenv_not_tree を付け、ツリーにならないようにする
local tree_only = vim.env.NVIM_TREE_ONLY == "1" and vim.g.tenv_editor ~= 1 and vim.g.tenv_not_tree ~= 1

-- Windows では、プログラムを探すときに今のフォルダが先に探される。開いたフォルダに git.exe や rg.exe が
-- 置かれていると、本物の代わりにそれが動くので、今のフォルダは探さないようにする(この nvim から起動するものすべて)
if is_win then vim.env.NoDefaultCurrentDirectoryInExePath = "1" end

-- ツリーやエディタは、開いたフォルダで自動的に git を実行する(neo-tree の Git の印・下の行の状態・検索)。
-- そのフォルダの .git/config に core.fsmonitor でコマンドが書かれていると、git のたびにそれが動くので、
-- ここから起動する git では使わない(環境変数での設定は、リポジトリの設定より強い)
do
  local n = tonumber(vim.env.GIT_CONFIG_COUNT or "") or 0
  vim.env["GIT_CONFIG_KEY_" .. n] = "core.fsmonitor"
  vim.env["GIT_CONFIG_VALUE_" .. n] = "false"
  vim.env.GIT_CONFIG_COUNT = tostring(n + 1)
end

vim.g.mapleader = " "
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local o = vim.opt
o.termguicolors = true
o.mouse = "a"
-- 右クリックは「メニュー」。extend(範囲選択を広げる)にしない
o.mousemodel = "popup_setpos"
o.number = not tree_only
o.signcolumn = tree_only and "no" or "yes"
o.laststatus = tree_only and 0 or 3
o.showmode = not tree_only
o.ruler = not tree_only
o.fillchars = { eob = " ", vert = "│" }
o.ignorecase = true
o.smartcase = true
o.clipboard = "unnamedplus"
o.updatetime = 300
o.splitright = true
o.undofile = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.scrolloff = 4
-- ファイルの中の「vim の設定の行」(modeline)は読まない(信用できないフォルダのファイルを開くため。リモートの編集でも切っている)
o.modeline = false

-- ツリー専用 pane は最下段の入力行を出さない(メッセージは右下に浮かべる。Neovim 0.12 の ui2)
if tree_only then
  local ok, ui2 = pcall(require, "vim._core.ui2")
  if ok and ui2.enable then
    pcall(ui2.enable, {})
    o.cmdheight = 0
  end
end

-- Linux 側は画面が無い前提で、コピーは OSC 52 で手元(Windows)のクリップボードへ送る(tmux は set-clipboard on)
if not is_win then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end

----------------------------------------------------------------
-- 開く・表示する
--   Windows: その場で開く / Linux: wopen で手元の WezTerm に頼む(新しいタブで開くので × で閉じられる)
----------------------------------------------------------------
local A = {}

-- wopen は合図をこの pane の端末に書く。nvim の画面の描き直しと重なると合図が壊れるので、書き終わるまで待つ(数十ミリ秒)
local function wopen(args)
  local p = vim.fn.expand("~/.local/bin/wopen")
  pcall(function() vim.system(vim.list_extend({ vim.fn.executable(p) == 1 and p or "wopen" }, args)):wait(3000) end)
end

local function dir_of(path)
  return vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
end

-- Windows: WezTerm の新しいタブ(new_window なら新しい窓)で開く(× で閉じられる)
local function new_tab(dir, argv, title, new_window)
  if vim.env.WEZTERM_PANE and vim.env.WEZTERM_EXECUTABLE then
    -- WEZTERM_EXECUTABLE は画面側(wezterm-gui)を指すことがある。cli を受け付けるのは wezterm 本体
    local exe = vim.env.WEZTERM_EXECUTABLE:gsub("wezterm%-gui(%.?%a*)$", "wezterm%1")
    local cmd = { exe, "cli", "spawn", "--cwd", dir }
    if new_window then table.insert(cmd, "--new-window") end
    table.insert(cmd, "--")
    if argv[1] == "nvim" then
      -- 絶対パスで起動する(開いたフォルダに置かれた nvim.exe を拾わない)
      argv = vim.list_extend({ vim.v.progpath, "--cmd", "let g:tenv_not_tree = 1" }, vim.list_slice(argv, 2))
    end
    vim.system(vim.list_extend(cmd, argv), {}, function(r)
      local id = vim.trim(r.stdout or "")
      if title and id ~= "" then
        vim.system({ exe, "cli", "set-tab-title", "--pane-id", id, title })
      end
    end)
  else
    vim.cmd.tabnew()
    vim.fn.jobstart(argv, { cwd = dir, term = true })
    vim.cmd.startinsert()
  end
end

-- Windows で「アプリで開く」。Windows が名前を補ったり環境変数を展開したりして、名前と違うファイルを
-- 実行しないようにする(名前どおりのものが無ければ開かない / % を含む名前は開かない / cmd.exe を通さない)
local function open_on_windows(path)
  if not vim.uv.fs_stat(path) then
    require("tenv.dialog").toast("見つかりません: " .. vim.fn.fnamemodify(path, ":t"))
    return
  end
  if path:find("%%") then
    require("tenv.dialog").toast("% を含む名前は Windows では開けません(ツリーのダブルクリックで開けます): "
      .. vim.fn.fnamemodify(path, ":t"))
    return
  end
  -- rundll32 の FileProtocolHandler は、cmd.exe を通さず、名前どおりのファイルを開く(名前の & で別の命令が動かない)
  vim.system({ "rundll32.exe", "url.dll,FileProtocolHandler", path })
end

function A.system_open(path)
  if is_win then open_on_windows(path) else wopen({ path }) end
end

function A.reveal(path)
  if is_win then vim.system({ "explorer.exe", "/select," .. path }) else wopen({ "--reveal", path }) end
end

-- ツリーの最上位のフォルダ(= 開いているフォルダ。検索の範囲にする)
local function tree_root()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  -- ツリーを今の窓に直に開いているときは、状態が窓ごとにある
  local state = ok and (manager.get_state_for_window and manager.get_state_for_window() or manager.get_state("filesystem"))
  return state and state.path or vim.fn.getcwd()
end

-- ツリーから開く: 右側の上段のエディタ(タブ)で開く。エディタを作れないときだけ新しいタブ
function A.edit(path)
  if not tree_only then
    vim.cmd.wincmd("p")
    vim.cmd.edit(vim.fn.fnameescape(path))
  elseif require("tenv.editor").open(path, tree_root()) then
    return
  elseif is_win then
    new_tab(dir_of(path), { "nvim", path }, "編集: " .. vim.fn.fnamemodify(path, ":t"))
  else
    wopen({ "--edit", path })
  end
end

function A.git(path)
  if vim.fn.executable("lazygit") ~= 1 then
    vim.notify("lazygit が見つかりません(README の導入手順を参照)", vim.log.levels.WARN)
    return
  end
  if is_win then new_tab(dir_of(path), { vim.fn.exepath("lazygit") }, "Git: " .. vim.fn.fnamemodify(dir_of(path), ":t")) else wopen({ "--git", dir_of(path) }) end
end

-- 設定(WezTerm の local.lua)。設定は手元の Windows にある
function A.settings()
  if is_win and vim.env.TENV_SETTINGS then
    new_tab(vim.fn.fnamemodify(vim.env.TENV_SETTINGS, ":h"), { "nvim", vim.env.TENV_SETTINGS }, "設定")
  elseif not is_win then
    wopen({ "--settings" })
  else
    vim.notify("WezTerm の中で使ってください(TENV_SETTINGS が無い)", vim.log.levels.WARN)
  end
end

-- 操作一覧(手元の Windows の keys.md を、別の窓のプレビューで開く)
function A.keys()
  if is_win then
    local file = vim.fn.resolve(vim.fn.stdpath("config")) .. "/keys.md"
    new_tab(vim.fn.fnamemodify(file, ":h"), { "nvim", "-R", "-c", "nnoremap q <Cmd>qa!<CR>", file }, "操作一覧", true)
  else
    wopen({ "--keys" })
  end
end

function A.copy_path(path)
  vim.fn.setreg("+", path)
  vim.notify("コピーしました: " .. path)
end

-- 検索(kind: "files" ファイル名 / "grep" 文字列)。ツリーからはエディタ(右上段)の中で開く(ツリーは狭いため)
-- 探す範囲は開いているフォルダ(ツリーの最上位)。エディタでは、そのエディタを作ったツリーの最上位(g:tenv_root)
function A.search(kind, root)
  root = root or (tree_only and tree_root()) or vim.g.tenv_root or vim.fn.getcwd()
  if tree_only and require("tenv.editor").pick(kind, root, tree_root()) then return end
  require("tenv.picker").run(kind, root)
end

----------------------------------------------------------------
-- プラグイン(lazy.nvim。取得元は各プラグインの公式 GitHub リポジトリ)
----------------------------------------------------------------
-- 版の固定: このリポジトリの lazy-lock.json(作者が動作を確かめた版)を、初めて入れるときの版にする。
-- 正本フォルダ(同期対象)には書かせず、各自のデータフォルダに写して使う(以後の :Lazy update は各自の判断で)
local lockfile = vim.fn.stdpath("data") .. "/lazy-lock.json"
if not vim.uv.fs_stat(lockfile) then
  vim.fn.mkdir(vim.fn.stdpath("data"), "p")
  pcall(vim.uv.fs_copyfile, vim.fn.stdpath("config") .. "/lazy-lock.json", lockfile)
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath })
  -- lazy.nvim 本体も lazy-lock.json の版に固定する(stable ブランチの先頭に勝手に追従しない)
  local ok, lock = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n")) end)
  local commit = ok and type(lock) == "table" and type(lock["lazy.nvim"]) == "table" and lock["lazy.nvim"].commit
  if type(commit) == "string" and commit:match("^%x+$") then
    vim.fn.system({ "git", "-C", lazypath, "checkout", "--quiet", commit })
  end
end
vim.opt.rtp:prepend(lazypath)

local function tree_state()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then return nil end
  return manager.get_state_for_window and manager.get_state_for_window() or manager.get_state("filesystem")
end

local function node_path(state)
  state = state or tree_state()
  local node = state and state.tree and state.tree:get_node()
  if not node or node.type == "message" then return nil, nil end
  return node:get_id(), node
end

-- Enter / ダブルクリック: フォルダは開閉、ファイルは編集(ツリー専用 pane では新しいタブで開く)
local function activate(state)
  local path, node = node_path(state)
  if not path then return end
  local fs = require("neo-tree.sources.filesystem.commands")
  if node.type == "directory" or not tree_only then
    fs.open(state)
  else
    A.edit(path)
  end
end

local function with_path(fn)
  return function(state)
    local path = node_path(state)
    if path then fn(path) end
  end
end

local tree_opts = {
  close_if_last_window = not tree_only,
  popup_border_style = "rounded",
  enable_git_status = true,
  enable_diagnostics = false,
  sort_case_insensitive = true,
  default_component_configs = {
    indent = { indent_size = 2, with_expanders = true },
    modified = { symbol = "●" },
    -- ツリーを広げたときに出る日時の列。作成日時は Windows で文字化けするので出さない
    last_modified = { format = "%Y/%m/%d %H:%M" },
    created = { enabled = false },
    -- Git の状態は VS Code と同じ文字で出す(既定のアイコンは、フォントや tmux によって崩れて見えるため)
    git_status = {
      symbols = {
        added = "A", deleted = "D", modified = "M", renamed = "R",
        untracked = "U", ignored = "", unstaged = "", staged = "", conflict = "!",
      },
    },
  },
  window = {
    position = tree_only and "current" or "left",
    width = 34,
    mappings = {
      ["<cr>"] = activate,
      -- 右クリックメニューの項目をダブルクリックしたときの 2 回目は、下のファイルを開かずに捨てる
      ["<2-LeftMouse>"] = function(state) if not require("tenv.menu").just_clicked() then activate(state) end end,
      ["O"] = with_path(A.system_open),
      ["E"] = with_path(A.reveal),
      ["Y"] = with_path(A.copy_path),
      ["g"] = with_path(A.git),
      ["<C-p>"] = function(state) A.search("files", state.path) end,
      ["<C-f>"] = function(state) A.search("grep", state.path) end,
      ["?"] = function() A.keys() end,
      ["q"] = tree_only and function() vim.cmd("qa") end or "close_window",
      -- ツリーの最上位のフォルダは動かさない(Backspace の「一つ上へ」と . の「ここを最上位に」を止める。
      -- 検索などのつもりで打った文字がツリーに入っても、開いているフォルダが変わらないように)
      ["<bs>"] = tree_only and "none" or "navigate_up",
      ["."] = tree_only and "none" or "set_root",
    },
  },
  -- ドロップの配置先の印(tenv/drop.lua)は、ツリーが描き直されるたびに付け直す
  event_handlers = tree_only and {
    { event = "after_render", handler = function() vim.schedule(function() require("tenv.drop").refresh() end) end },
  } or nil,
  filesystem = {
    follow_current_file = { enabled = true },
    use_libuv_file_watcher = true,
    hijack_netrw_behavior = "open_current",
    group_empty_dirs = false,
    filtered_items = {
      visible = true,
      hide_dotfiles = false,
      hide_gitignored = false,
      hide_by_name = { ".git" },
    },
  },
}

require("lazy").setup({
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      -- 背景は端末(WezTerm)に任せる。WezTerm のテーマを切り替えても浮かない
      require("tokyonight").setup({
        style = "night",
        transparent = true,
        styles = { sidebars = "transparent", floats = "transparent" },
      })
      vim.cmd.colorscheme("tokyonight")
    end,
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    lazy = false,
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim", "nvim-tree/nvim-web-devicons" },
    opts = tree_opts,
  },
  {
    -- 検索の画面(ファイル名・文字列。tenv/picker.lua から使う。ripgrep が要る)
    "nvim-telescope/telescope.nvim",
    tag = "v0.2.2",
    cmd = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons" },
    opts = function()
      local actions = require("telescope.actions")
      return {
        defaults = {
          layout_strategy = "flex",
          layout_config = { width = 0.95, height = 0.92, flex = { flip_columns = 120 } },
          path_display = { "truncate" },
          sorting_strategy = "ascending",
          prompt_prefix = "  ",
          selection_caret = " ",
          -- Esc 1 回で閉じる(VS Code と同じ)。↑↓ / Ctrl+J / K で選ぶ
          mappings = {
            i = { ["<Esc>"] = actions.close, ["<C-j>"] = actions.move_selection_next, ["<C-k>"] = actions.move_selection_previous },
          },
        },
      }
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    cond = not tree_only and vim.g.tenv_resume ~= 1, -- 「前の作業を再開」の画面にはステータス行を出さない
    event = "VeryLazy", -- 画面が出てから読む(起動を待たせない)
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "tokyonight",
        globalstatus = true,
        component_separators = "",
        section_separators = { left = "", right = "" },
        disabled_filetypes = { statusline = { "neo-tree" } },
      },
    },
  },
  {
    -- Markdown のプレビュー(GitHub 風の配色は tenv/markdown.lua)
    "MeanderingProgrammer/render-markdown.nvim",
    cond = not tree_only,
    ft = { "markdown" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = function() return require("tenv.markdown").opts() end,
    config = function(_, opts)
      require("render-markdown").setup(opts)
      require("tenv.markdown").setup()
      -- 最初の md は setup の前に FileType が過ぎているので、ここで表示を整える
      if vim.bo.filetype == "markdown" then vim.cmd("doautocmd FileType markdown") end
    end,
  },
}, {
  lockfile = lockfile,
  install = { colorscheme = { "tokyonight" } },
  ui = { border = "rounded" },
  change_detection = { notify = false },
  checker = { enabled = false },
  -- 使わない標準のプラグインは読まない(起動を少し速くする)
  performance = { rtp = { disabled_plugins = { "gzip", "tarPlugin", "zipPlugin", "tohtml", "tutor", "netrwPlugin" } } },
})

----------------------------------------------------------------
-- ドラッグ&ドロップ: エクスプローラーからツリーへファイルを落とすと、選んでいるフォルダに配置する
--   WezTerm はドロップされたファイルのパスを "C:\..." の形で貼り付ける(quote_dropped_files)。
--   ツリーの上でそれを受けたら、貼り付けの代わりに配置する。
--   Windows: その場でコピー / Linux: WezTerm に頼んで scp で送る(WezTerm 側で確認が出る)
----------------------------------------------------------------
local function dropped_paths(text)
  local paths = {}
  -- 貼り付けられた文字列から配置するのは、制御文字を含まず・.. を含まず・実在するパスだけ
  local function add(p)
    if p:find("%c") then return end
    for seg in p:gmatch("[^\\/]+") do if seg == ".." then return end end
    if vim.uv.fs_stat(p) then table.insert(paths, p) end
  end
  for p in text:gmatch('"(%a:[\\/][^"]*)"') do add(p) end
  for p in text:gmatch('"(\\\\[^"]+)"') do add(p) end
  return paths
end

-- Windows のファイルを、このPC のフォルダへ配置する(配置するかは「配置先を選ぶ」状態の Enter / Esc で決めてある)。
-- 同じ名前があるときだけ、確認画面で「上書き / 飛ばす / やめる」を選ぶ
local function place_local(files, dest)
  local exists = {}
  for _, src in ipairs(files) do
    local name = vim.fn.fnamemodify(src, ":t")
    if vim.uv.fs_stat(dest .. "\\" .. name) then table.insert(exists, name) end
  end
  local function copy(overwrite)
    local n = 0
    for _, src in ipairs(files) do
      local name = vim.fn.fnamemodify(src, ":t")
      local to = dest .. "\\" .. name
      if overwrite or not vim.uv.fs_stat(to) then
        if vim.fn.isdirectory(src) == 1 then
          vim.system({ "robocopy", src, to, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP" }):wait()
        else
          vim.uv.fs_copyfile(src, to)
        end
        n = n + 1
      end
    end
    local state = tree_state()
    if state then require("neo-tree.sources.filesystem.commands").refresh(state) end
    local skipped = #files - n
    vim.notify(n == 0 and "配置しませんでした(同じ名前のため飛ばしました)"
      or (n .. " 件を配置しました" .. (skipped > 0 and ("(" .. skipped .. " 件は飛ばしました)") or "")))
  end
  if #exists == 0 then return copy(false) end
  require("tenv.dialog").open({
    title = "同じ名前があります",
    lines = { vim.fn.fnamemodify(dest, ":t") .. " に、次のものが既にあります。", "", table.concat(exists, "\n") },
    buttons = { { label = "上書きする", value = "over" }, { label = "飛ばす", value = "skip" }, { label = "やめる", value = "no" } },
    danger = true,
  }, function(v)
    if v == "over" then copy(true) elseif v == "skip" then copy(false) end
  end)
end

local orig_paste = vim.paste
local pasted = {}
vim.paste = function(lines, phase)
  -- ツリーは文字を貼り付ける場所が無いので、貼り付けはすべてここで受ける(ドロップしたファイル。どの窓にいても受ける)
  if tree_only then
    -- 長い貼り付けは分割して届く(phase 1→2→3)。最後にまとめて扱う
    -- 前のかたまりの最後の行と、次のかたまりの最初の行は同じ行の続き(ssh 越しでは行の途中で切れて届く)
    if #pasted > 0 and #lines > 0 then
      pasted[#pasted] = pasted[#pasted] .. lines[1]
      vim.list_extend(pasted, lines, 2)
    else
      vim.list_extend(pasted, lines)
    end
    if phase == 1 or phase == 2 then return true end
    local text = table.concat(pasted, "\n")
    pasted = {}
    local files = dropped_paths(text)
    if #files > 0 then
      -- 配置先を選ぶ状態にする(tenv/drop.lua。最初はカーソルの行のフォルダ、マウスを乗せた行のフォルダに変えられる)
      vim.schedule(function()
        require("tenv.drop").start(files, function(dest)
          if is_win then place_local(files, dest) else wopen(vim.list_extend({ "--upload", dest }, files)) end
        end)
      end)
      return true
    end
    return true -- ツリーには文字を貼り付けない
  end
  return orig_paste(lines, phase)
end

-- エディタの pane(ツリーから開いたファイルを並べる上段の pane)ではタブを出す
if vim.g.tenv_editor == 1 then
  require("tenv.tabs").setup()
end

-- 検索: Ctrl+P ファイル名 / Ctrl+F 文字列(エディタでは Git の根、無ければ今のフォルダから探す。ツリーは neo-tree の割り当て)
if not tree_only then
  -- Ctrl+C: 選んでいる範囲(ドラッグ / v)をクリップボードへコピー(VS Code と同じ。リモートでは OSC 52 で手元へ)
  vim.keymap.set("x", "<C-c>", function()
    vim.cmd('normal! "+y')
    vim.notify("コピーしました")
  end, { desc = "コピー" })
  vim.keymap.set("n", "<C-p>", function() A.search("files") end, { desc = "ファイル名で探す" })
  vim.keymap.set("n", "<C-f>", function() A.search("grep") end, { desc = "文字列で探す" })
end

----------------------------------------------------------------
-- 右クリックメニュー(ツリーの上だけ)
----------------------------------------------------------------
_G.TreeMenu = function(what)
  local state = tree_state()
  local path = node_path(state)
  local fs = require("neo-tree.sources.filesystem.commands")
  local on_path = { open = A.system_open, reveal = A.reveal, copy = A.copy_path, git = A.git }
  if on_path[what] then
    if path then on_path[what](path) end
  elseif what == "settings" then
    A.settings()
  elseif what == "refresh" then
    if state then fs.refresh(state) end
  elseif what == "keys" then
    A.keys()
  elseif what == "files" or what == "grep" then
    -- フォルダの上ならそのフォルダの中、ファイルの上ならツリーの根から探す
    local root = (path and vim.fn.isdirectory(path) == 1) and path or (state and state.path)
    A.search(what, root)
  end
end

-- 新規・名前変更・削除はキー(a / A / r / d)で行う。一覧は「操作一覧」(?)
local function open_tree_menu(at)
  local function act(what) return function() TreeMenu(what) end end
  require("tenv.menu").open(at, {
    { icon = "󰏋", label = "アプリで開く", key = "O", action = act("open") },
    { icon = "󰉋", label = "エクスプローラー", key = "E", action = act("reveal") },
    { icon = "󰆏", label = "パスをコピー", key = "Y", action = act("copy") },
    "-",
    { icon = "󰈞", label = "ファイルを探す", key = "^P", action = act("files") },
    { icon = "󰍉", label = "文字列を探す", key = "^F", action = act("grep") },
    "-",
    { icon = "󰒓", label = "設定", action = act("settings") },
    { icon = "󰑓", label = "更新", key = "R", action = act("refresh") },
    { icon = "󰌌", label = "操作一覧", key = "?", action = act("keys") },
  })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "neo-tree",
  callback = function(ev)
    local opts = { buffer = ev.buf, silent = true }
    -- 右クリック: 押したときは行を選ぶだけ。離したときにメニューを開く
    -- (押した瞬間に開くと、離した操作がメニューの項目を選んでしまう)
    -- 素早く続けて押すと 2- / 3- / 4- 付きで届く(押し忘れると nvim 標準の英語メニューが出る)
    for _, mode in ipairs({ "n", "x" }) do
      for _, n in ipairs({ "", "2-", "3-", "4-" }) do
        vim.keymap.set(mode, "<" .. n .. "RightMouse>", "<Esc><LeftMouse>", opts)
        vim.keymap.set(mode, "<" .. n .. "RightRelease>", function() open_tree_menu("mouse") end, opts)
      end
    end
    -- ツリーの上ではドラッグで範囲選択にしない(クリックの手ぶれで選択になり、右クリックが効かなくなるため)
    -- (続けて押したクリックの 2- / 3- / 4- 付きも同じ。離したときに nvim 標準の範囲選択が始まるため)
    for _, n in ipairs({ "", "2-", "3-", "4-" }) do
      for _, key in ipairs({ "LeftDrag", "LeftRelease", "RightDrag" }) do
        vim.keymap.set({ "n", "x" }, "<" .. n .. key .. ">", "<Nop>", opts)
      end
    end
    for _, key in ipairs({ "<3-LeftMouse>", "<4-LeftMouse>" }) do
      vim.keymap.set({ "n", "x" }, key, "<Nop>", opts)
    end
    vim.keymap.set("x", "<LeftMouse>", "<Esc><LeftMouse>", opts)
    -- キーでもメニューを開ける(カーソルの行に対して)
    vim.keymap.set("n", "M", function() open_tree_menu("cursor") end, opts)
    -- 範囲を選んで d: 選んだ行のファイル・フォルダをまとめて削除する(確認あり)。
    -- neo-tree の範囲選択は、ツリーを窓に直に開いているときに選んだ行を拾えない(0 件になる)ため、自前で数える
    -- (neo-tree が後から "v" で割り当てるので、その後に上書きする)
    vim.schedule(function() if vim.api.nvim_buf_is_valid(ev.buf) then vim.keymap.set("v", "d", function()
      local a, b = vim.fn.line("v"), vim.fn.line(".")
      if a > b then a, b = b, a end
      vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
      local state = tree_state()
      if not state or not state.tree then return end
      local paths = {}
      for l = a, b do
        local ok, node = pcall(function() return state.tree:get_node(l) end)
        if ok and node and (node.type == "file" or node.type == "directory") and node:get_depth() > 1 then
          table.insert(paths, node.path or node:get_id())
        end
      end
      if #paths == 0 then return end
      require("neo-tree.sources.filesystem.lib.fs_actions").delete_nodes(paths, function()
        require("neo-tree.sources.filesystem.commands").refresh(state)
      end)
    end, opts) end end)
    -- ドロップの配置先(カーソルの行のフォルダ)に印を付ける
    if tree_only then
      vim.api.nvim_create_autocmd("CursorMoved", { buffer = ev.buf, callback = function() require("tenv.drop").refresh() end })
    end
  end,
})

-- ツリー専用 pane の最下段に Git の状態(リモート先 / 未コミット数 / 未 push の有無)。クリックで Lazygit
-- ツリーからの確認とお知らせ(tenv/dialog.lua)
--   ・確認(削除など、neo-tree が y/n で聞くもの)は、ボタン付きの確認画面にする。Enter で実行、Esc でやめる
--   ・お知らせは下に数秒だけ出す。注意・エラーは確認画面(OK で閉じる)にする
if tree_only then
  local dialog = require("tenv.dialog")
  local ok_inputs, inputs = pcall(require, "neo-tree.ui.inputs")
  if ok_inputs then
    inputs.confirm = function(message, callback)
      local name = message:match("[Dd]elete (.+)%?$")
      local trash = message:match("[Tt]rash (.+)%?$")
      local target = name or trash
      if target == "0 items" then
        dialog.toast("消せるものが選ばれていません")
        return callback(false)
      end
      local lines, label, title = { message }, "OK", "確認"
      if target then
        target = target:gsub("^['\"](.*)['\"]$", "%1"):gsub("^the selected files and directories$", "選んだファイルとフォルダ")
          :gsub("^(%d+) items$", "選んだ %1 件")
        lines = { "「" .. vim.fn.fnamemodify(target, ":t") .. "」を" .. (trash and "ごみ箱へ移" or "削除") .. "します。",
          trash and "" or "元に戻せません。" }
        label, title = trash and "ごみ箱へ" or "削除する", trash and "ごみ箱へ移す" or "削除"
      end
      dialog.confirm(title, lines, label, function(yes) callback(yes) end, target ~= nil)
    end
    -- 名前の入力(新しいファイル・フォルダ、名前の変更、複製・移動の先)は、ツリーの幅に収まる日本語の入力欄にする
    inputs.input = function(prompt, default_value, callback)
      prompt = tostring(prompt)
      local title, hint = "入力", nil
      if prompt:match("^Enter name for new file or directory") then
        title, hint = "新しいファイル", "フォルダは末尾を / に"
      elseif prompt:match("^Enter name for new directory") then
        title = "新しいフォルダ"
      elseif prompt:match("^Enter new base name") or prompt:match("^Enter new name") then
        title = "名前を変える"
      elseif prompt:match("already exists") then
        title, hint = "別の名前を入力", "同じ名前が既にあります"
      elseif prompt:match("^Copy") then
        title = "複製先"
      elseif prompt:match("^Move") then
        title = "移動先"
      else
        hint = prompt
      end
      dialog.input({ title = title, hint = hint, default = default_value }, callback)
    end
  end
  -- neo-tree のお知らせ(英語)のうち、よく出るものは日本語にする
  local function ja(msg)
    msg = msg:gsub("^%[Neo%-tree %u+%]%s*", "")
    local rules = {
      { "^Deleted file (.+)$", "削除しました: " }, { "^Deleted directory (.+)$", "削除しました: " },
      { "^Renamed .+ to (.+)$", "名前を変えました: " }, { "^Moved .+ to (.+)$", "移動しました: " },
      { "^Copied .+ to (.+)$", "複製しました: " }, { "^Created (.+)$", "作りました: " },
    }
    for _, r in ipairs(rules) do
      local path = msg:match(r[1])
      if path then return r[2] .. vim.fn.fnamemodify(path, ":t") end
    end
    return msg
  end
  vim.notify = function(msg, level)
    msg = ja(tostring(msg))
    if level and level >= vim.log.levels.WARN then
      dialog.open({ title = level >= vim.log.levels.ERROR and "エラー" or "注意", lines = { msg },
        buttons = { { label = "OK", value = true } } }, function() end)
    else
      dialog.toast(msg)
    end
  end
end

if tree_only then
  require("tenv.gitfooter").setup({ on_click = A.git })
  -- タブ名を決めておく(決めないと、Git の状態を調べる git が動くたびに、タブ名が git.exe に変わる)
  o.title = true
  o.titlestring = "ツリー: %{fnamemodify(getcwd(), ':t')}"
end

-- ツリー専用 pane の見出し(neo-tree の窓が開いてから付ける)
vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
  callback = function(ev)
    if not tree_only then return end
    vim.schedule(function()
      for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
        if vim.bo[ev.buf].filetype == "neo-tree" then
          vim.wo[win].winbar = "%#Title#  󰙅 EXPLORER %*"
          vim.wo[win].cursorline = true
        end
      end
    end)
  end,
})

----------------------------------------------------------------
-- 起動時
----------------------------------------------------------------
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if tree_only then
      require("neo-tree.command").execute({ source = "filesystem", position = "current", dir = vim.fn.getcwd() })
    end
  end,
})

vim.keymap.set("n", "<leader>e", "<Cmd>Neotree toggle reveal<CR>", { desc = "ツリー" })
