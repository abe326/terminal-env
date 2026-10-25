-- ツリーからファイルを開く先(VS Code のエディタに相当する、上段の pane)
--   ・右側の pane(Claude Code など。ツリーを出したときの pane = TENV_MAIN_PANE)の上に、エディタの pane を 1 つ作る
--   ・既にあれば、そこにタブとして追加する(エディタの nvim に --listen の口から頼む)
--   ・tmux(リモート)でも WezTerm(Windows)でも同じ動き
--   ・検索(tenv/picker.lua)も、狭いツリーではなくエディタの中で開く
local M = {}

local is_win = vim.fn.has("win32") == 1

-- エディタとの連絡口(ソケット)の場所。Linux では自分だけが使えるフォルダに置く
-- (共用の /tmp では、別のユーザーが先に同じ名前のフォルダを作っていることがあるので、持ち主と権限を確かめる)
local function addr_for(main)
  if is_win then
    -- 名前付きパイプは、同じ PC のほかのユーザーからも名前で探せる。推測されないよう、
    -- WezTerm が作った合言葉(この PC の自分だけが読めるファイル)の一部を名前に入れる
    local f = io.open((vim.env.LOCALAPPDATA or "") .. "\\tenv\\token", "r")
    local tok = f and (f:read("*l") or ""):match("^(%x+)") or ""
    if f then f:close() end
    return "\\\\.\\pipe\\tenv-edit-" .. tok:sub(1, 16) .. "-" .. main
  end
  local dir = (vim.env.XDG_RUNTIME_DIR or "/tmp") .. "/tenv-" .. (vim.env.USER or "user")
  vim.fn.mkdir(dir, "p", "0700")
  local st = vim.uv.fs_lstat(dir)
  if not st or st.type ~= "directory" or st.uid ~= vim.uv.getuid() or st.mode % 64 ~= 0 then
    return nil -- 自分のものでない・ほかの人も使える → 使わない(エディタの pane を作らずに開く)
  end
  return dir .. "/edit-" .. main:gsub("[^%w]", "") .. ".sock"
end

local function wezterm_cli()
  local exe = vim.env.WEZTERM_EXECUTABLE
  return exe and exe:gsub("wezterm%-gui(%.?%a*)$", "wezterm%1")
end

local function focus(pane)
  if not pane or pane == "" then return end
  if vim.env.TMUX then
    vim.system({ "tmux", "select-pane", "-t", pane })
  elseif wezterm_cli() then
    vim.system({ wezterm_cli(), "cli", "activate-pane", "--pane-id", pane })
  end
end

-- 開いているエディタで lua を動かす(code の中の ... が args)。動かせたら true
local function send(addr, code, args)
  local ok, ch = pcall(vim.fn.sockconnect, "pipe", addr, { rpc = true })
  if not ok or ch <= 0 then return false end
  local sent = pcall(vim.rpcrequest, ch, "nvim_exec_lua", code, args)
  local pane = sent and select(2, pcall(vim.rpcrequest, ch, "nvim_eval", is_win and "$WEZTERM_PANE" or "$TMUX_PANE"))
  pcall(vim.fn.chanclose, ch)
  if sent then vim.defer_fn(function() focus(pane) end, 250) end
  return sent
end

-- エディタがあればそこで code を動かし、無ければ作る(extra = 起動するときの nvim の引数)。
-- root = 開いているフォルダ(ツリーの最上位)。エディタでの検索の範囲にする(g:tenv_root)
local function with_editor(code, args, dir, extra, root)
  local main = vim.env.TENV_MAIN_PANE
  if not main or main == "" then return false end
  local addr = addr_for(main)
  if not addr then return false end
  if send(addr, "vim.g.tenv_root = select(1, ...); " .. code:gsub("%(%.%.%.%)", "(select(2, ...))"), { root or "", unpack(args) }) then
    return true
  end

  if not is_win then os.remove(addr) end -- 前のエディタが残した古いソケット
  local argv = { vim.v.progpath, "--listen", addr, "--cmd", "let g:tenv_editor = 1" }
  if root then vim.list_extend(argv, { "--cmd", "let g:tenv_root = " .. vim.fn.string(root) }) end
  vim.list_extend(argv, extra)
  local r
  if vim.env.TMUX then
    local cmd = table.concat(vim.tbl_map(vim.fn.shellescape, argv), " ")
    r = vim.system({ "tmux", "split-window", "-v", "-b", "-l", "62%", "-t", main, "-c", dir,
      "-P", "-F", "#{pane_id}", cmd }):wait()
    -- ダブルクリックの残りのマウス操作でツリーに戻らないよう、少し待ってからエディタへ移る
    local pane = vim.trim(r.stdout or "")
    vim.defer_fn(function() focus(pane) end, 250)
  elseif wezterm_cli() then
    r = vim.system(vim.list_extend(
      { wezterm_cli(), "cli", "split-pane", "--pane-id", main, "--top", "--percent", "62", "--cwd", dir, "--" }, argv)):wait()
    local pane = vim.trim(r.stdout or "")
    if r.code == 0 then vim.defer_fn(function() focus(pane) end, 250) end
  else
    return false
  end
  return r.code == 0
end

--- path をエディタの pane で開く。エディタの pane を作れない状況なら false。tree_root = 開いているフォルダ
function M.open(path, tree_root)
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
  return with_editor("require('tenv.tabs').open(...)", { path }, dir, { path }, tree_root)
end

--- エディタの pane で検索を開く。kind: "files" / "grep"、root: 探す場所、tree_root = 開いているフォルダ
function M.pick(kind, root, tree_root)
  local lua = string.format("lua require('tenv.picker').run(%q, %q)", kind, root)
  return with_editor("require('tenv.picker').run(...)", { kind, root }, root, { "-c", lua }, tree_root or root)
end

return M
