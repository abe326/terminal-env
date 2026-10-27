-- ツリーからファイルを開く先(VS Code のエディタに相当する、上段の pane)
--   ・右側(ツリーの右。Claude Code など)の上段に、右側の全幅でエディタの pane を 1 つ作る
--     (右側が左右に割れていても、その全部の上に出る。ツリーは左端の全高のまま)
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

-- tmux: エディタの pane を、右側(ツリーの右)の全幅で上段に作る。作った pane の ID(作れなければ nil)
--   split-window は pane を 1 つしか割れないので、main の上に作ると、右側が左右に割れているときに
--   main の上だけに出てしまう。そこで、窓の全幅で上段に作ってから(-f)、ツリーを join-pane -f で
--   左端の全高に戻す(ツリー | [エディタ / 右側])。ツリーを抜き差しすると右側の pane の幅の比が
--   崩れる(抜いた分が隣の pane に寄る)ので、元の幅に戻す
local function tmux_split_editor(main, dir, cmd)
  local function tmux(args) return vim.system(vim.list_extend({ "tmux" }, args)):wait() end
  local panes = {} -- 作る前の右側の pane と幅
  local tree, tree_w
  for _, line in ipairs(vim.split(tmux({ "list-panes", "-t", main, "-F", "#{pane_id} #{pane_width} #{@tree}" }).stdout or "", "\n", { trimempty = true })) do
    local id, w, flag = line:match("^(%S+) (%d+) ?(%S*)$")
    if flag == "1" then tree, tree_w = id, w elseif id then table.insert(panes, { id, w }) end
  end
  local r = tmux({ "split-window", "-v", "-b", "-f", "-l", "62%", "-t", main, "-c", dir, "-P", "-F", "#{pane_id}", cmd })
  local pane = vim.trim(r.stdout or "")
  if r.code ~= 0 or pane == "" then return nil end
  if tree then
    -- -d: エディタを選んだままにする。幅が入らないときは幅を指定せずに戻す
    if tmux({ "join-pane", "-d", "-h", "-b", "-f", "-l", tree_w, "-s", tree, "-t", pane }).code ~= 0 then
      tmux({ "join-pane", "-d", "-h", "-b", "-f", "-s", tree, "-t", pane })
    end
  end
  for _, p in ipairs(panes) do
    if vim.trim(tmux({ "display", "-p", "-t", p[1], "#{pane_width}" }).stdout or "") ~= p[2] then
      tmux({ "resize-pane", "-t", p[1], "-x", p[2] })
    end
  end
  return pane
end

-- WezTerm: 同じ並びを、pane を 1 つずつ動かして作る。--top-level とツリーの移動は使わない
--   (WezTerm 20240203 では、--top-level で作った pane が新しい大きさに resize されず、タブが覚えている
--   大きさも縮んだまま戻らないので、そのあとの操作で全体が崩れる)
--   1. main の上にエディタを作る(普通の分割。右側が左右に割れていると、この時点では main の上だけ)
--   2. 右側の他の pane を、いったん同じ窓の新しいタブへ出す(move-pane-to-new-tab。タブは切り替わらない)。
--      右側が main だけになるので、エディタは右側の全幅に広がる
--   3. 出した pane を、main の右に元の並び・元の幅で戻す(split-pane --right --cells <幅> --move-pane-id。
--      --cells は「その pane と、それより右の全部」の幅にする。戻す先の pane はその分だけ広く作ってある。
--      空になったタブは WezTerm が消す)
--   右側が左右の並び(全部が上段 0 から同じ高さ)でないときは、組み替えずに main の上に作るだけ
local function wezterm_split_editor(main, dir, argv)
  local function cli(args) return vim.system(vim.list_extend({ wezterm_cli(), "cli" }, args)):wait() end
  local others = {} -- 右側の main 以外の pane(左から順)
  local ok, panes = pcall(vim.json.decode, cli({ "list", "--format", "json" }).stdout or "")
  if ok and type(panes) == "table" then
    local tab, rows
    for _, p in ipairs(panes) do
      if tostring(p.pane_id) == main then tab, rows = p.tab_id, p.size and p.size.rows end
    end
    local flat = tab ~= nil
    for _, p in ipairs(panes) do
      if p.tab_id == tab then
        if p.top_row ~= 0 or not p.size or p.size.rows ~= rows or p.is_zoomed then flat = false end
        if tostring(p.pane_id) ~= main and tostring(p.pane_id) ~= (vim.env.WEZTERM_PANE or "") then
          table.insert(others, { id = tostring(p.pane_id), left = p.left_col or 0, cols = p.size and p.size.cols or 0 })
        end
      end
    end
    if not flat then others = {} end
    table.sort(others, function(a, b) return a.left < b.left end)
  end

  local r = cli(vim.list_extend({ "split-pane", "--pane-id", main, "--top", "--percent", "62", "--cwd", dir, "--" }, argv))
  local pane = vim.trim(r.stdout or "")
  if r.code ~= 0 or pane == "" then return nil end

  local parked, total = {}, 0 -- 出した pane と、その幅の合計(境目込み)
  for _, o in ipairs(others) do
    if cli({ "move-pane-to-new-tab", "--pane-id", o.id }).code == 0 then
      table.insert(parked, o)
      total = total + o.cols + 1
    end
  end
  local prev = main
  for _, o in ipairs(parked) do
    local cells = tostring(total - 1) -- この pane と、それより右の全部の幅
    total = total - o.cols - 1
    if cli({ "split-pane", "--pane-id", prev, "--right", "--cells", cells, "--move-pane-id", o.id }).code ~= 0 then
      cli({ "split-pane", "--pane-id", prev, "--right", "--move-pane-id", o.id }) -- 幅が入らないときは半分で戻す
    end
    prev = o.id
  end
  return pane
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
  local pane
  if vim.env.TMUX then
    pane = tmux_split_editor(main, dir, table.concat(vim.tbl_map(vim.fn.shellescape, argv), " "))
  elseif wezterm_cli() then
    pane = wezterm_split_editor(main, dir, argv)
  end
  if not pane then return false end
  -- ダブルクリックの残りのマウス操作でツリーに戻らないよう、少し待ってからエディタへ移る
  vim.defer_fn(function() focus(pane) end, 250)
  return true
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
