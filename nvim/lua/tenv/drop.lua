-- ツリーへのドラッグ&ドロップの配置先
--   ・いつも: カーソルのある行のフォルダ(ファイルの行ならその親)を「配置先」として色付きで示す
--   ・ドロップした後: 「配置先を選ぶ」状態になる。配置先のフォルダと、その中身(開いている分)が光る。
--     クリックしたフォルダが配置先になり、開く / 閉じる(中のフォルダも選べる)。j / k で動かしてもよい。
--     キーでは Space / l / → で開閉、h / ← で閉じる。Enter(上の「配置」)で配置、Esc(上の「やめる」)でやめる
--   WezTerm はドラッグ中のマウスの位置をアプリに渡さない(ドロップした瞬間にファイルの一覧が届くだけ)ため、
--   ドラッグ中ではなく、ドロップした後に選ぶ形にしている
local M = {}

local ns = vim.api.nvim_create_namespace("tenv_drop")
local active -- 配置先を選んでいる間の状態

local function set_hl()
  local hl = vim.api.nvim_set_hl
  hl(0, "TenvDropMark", { fg = "#73daca", italic = true })                         -- いつもの「配置先」の印
  hl(0, "TenvDropTarget", { fg = "#1a1b26", bg = "#73daca", bold = true })         -- 選んでいる間: 配置先のフォルダ
  hl(0, "TenvDropInside", { bg = "#1f3d3a" })                                      -- 選んでいる間: その中身
  hl(0, "TenvDropBar", { fg = "#1a1b26", bg = "#73daca", bold = true })            -- 選んでいる間の見出し
  hl(0, "TenvDropOk", { fg = "#1a1b26", bg = "#9ece6a", bold = true })             -- 見出しの「配置」
  hl(0, "TenvDropNo", { fg = "#c0caf5", bg = "#3b4261" })                          -- 見出しの「やめる」
end
set_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

-- ツリーを今の窓に直に開いている(position = "current")ときは、状態が窓ごとにある
local function tree_state()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then return nil end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "neo-tree" then
      local s = vim.api.nvim_win_call(win, function() return manager.get_state_for_window and manager.get_state_for_window() end)
      if s and s.tree then return s, win, buf end
    end
  end
  local s = manager.get_state("filesystem")
  return s, s and s.winid, s and s.bufnr
end

local function is_under(path, dir)
  if path == dir then return true end
  local d = dir:gsub("[\\/]$", "")
  return path:sub(1, #d + 1) == d .. "/" or path:sub(1, #d + 1) == d .. "\\"
end

-- 行 → 配置先のフォルダ(フォルダの行ならそのフォルダ、ファイルの行なら親、何も無い行なら最上位)
local function folder_at(state, line)
  local ok, node = pcall(function() return state.tree:get_node(line) end)
  if not ok or not node or node.type == "message" then return state.path end
  if node.type == "directory" then return node:get_id() end
  return node:get_parent_id() or state.path
end

-- 配置先の行と、その中身(開いている分)の行に印を付ける
local function draw(state, folder, strong)
  local _, _, buf = tree_state()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local n = vim.api.nvim_buf_line_count(buf)
  for line = 1, n do
    local ok, node = pcall(function() return state.tree:get_node(line) end)
    local id = ok and node and node:get_id()
    if id == folder then
      if strong then
        vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, { line_hl_group = "TenvDropTarget", priority = 300 })
        vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
          virt_text = { { " 󰁅 ここに配置 ", "TenvDropTarget" } }, virt_text_pos = "right_align", priority = 300 })
      else
        vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
          virt_text = { { "󰁅 配置先 ", "TenvDropMark" } }, virt_text_pos = "right_align", priority = 200 })
      end
    elseif strong and id and is_under(id, folder) then
      vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, { line_hl_group = "TenvDropInside", priority = 250 })
    end
  end
end

--- いま配置先になるフォルダ(カーソルの行から)
function M.current()
  local state, win = tree_state()
  if not state or not state.tree then return vim.fn.getcwd() end
  local line = (win and vim.api.nvim_win_is_valid(win)) and vim.api.nvim_win_get_cursor(win)[1] or 1
  return folder_at(state, line)
end

--- 印を描き直す(カーソルが動いたとき・ツリーが描き直されたとき)
function M.refresh()
  local state = tree_state()
  if not state or not state.tree then return end
  if active then
    draw(state, active.target, true)
  else
    draw(state, M.current(), false)
  end
end

local function retarget(line)
  local state = tree_state()
  if not active or active.done or not state or not state.tree then return end
  active.target = folder_at(state, line)
  draw(state, active.target, true)
end

local KEYS = { "<LeftMouse>", "<2-LeftMouse>", "<LeftRelease>", "<2-LeftRelease>", "<CR>", "<Esc>", "q",
  "<Space>", "l", "<Right>", "h", "<Left>" }

local function stop()
  if not active then return end
  local a = active
  active = nil
  vim.o.mousemoveevent = a.prev_mousemove
  if vim.api.nvim_win_is_valid(a.win) then vim.wo[a.win].winbar = a.prev_winbar end
  if vim.api.nvim_buf_is_valid(a.buf) then
    -- 選んでいる間だけ差し替えたキーを、元(neo-tree の割り当てなど)に戻す。mapset は今のバッファに戻すので、その中で行う
    vim.api.nvim_buf_call(a.buf, function()
      for _, lhs in ipairs(KEYS) do
        pcall(vim.keymap.del, "n", lhs, { buffer = a.buf })
        if a.saved[lhs] and next(a.saved[lhs]) then pcall(vim.fn.mapset, "n", false, a.saved[lhs]) end
      end
    end)
  end
  pcall(vim.api.nvim_del_autocmd, a.autocmd)
  M.refresh()
end

-- 上の帯: [配置 ⏎] [やめる Esc] 󰁅 <配置先> へ N件。ボタンは左に置く(クリックした位置で見分けるため)
local BTN_OK, BTN_NO = " 配置⏎ ", " やめるEsc "
local function update_bar()
  if not active or not vim.api.nvim_win_is_valid(active.win) then return end
  local name = vim.fn.fnamemodify(active.target, ":t")
  if name == "" then name = active.target end
  vim.wo[active.win].winbar = "%#TenvDropOk#" .. BTN_OK .. "%#TenvDropBar# %#TenvDropNo#" .. BTN_NO
    .. "%#TenvDropBar# 󰁅%<" .. name:gsub("%%", "%%%%") .. "%=%*"
end

--- ドロップした後に配置先を選ぶ。files: 置くもの、place(dest): Enter で決めたときに呼ぶ
---   クリック: そのフォルダを配置先にして、開く / 閉じる(ファイルの行なら、その親が配置先)
---   Enter / 上の「配置」: 配置する  Esc / 上の「やめる」: やめる
function M.start(files, place)
  stop()
  local state, win, buf = tree_state()
  if not state or not state.tree or not win or not vim.api.nvim_win_is_valid(win) then
    place(M.current())
    return
  end
  local saved = {}
  for _, lhs in ipairs(KEYS) do saved[lhs] = vim.fn.maparg(lhs, "n", false, true) end
  active = {
    files = files, place = place, win = win, buf = buf, saved = saved, target = M.current(),
    prev_mousemove = vim.o.mousemoveevent, prev_winbar = vim.wo[win].winbar,
  }
  update_bar()

  -- 配置する。確認(WezTerm の確認・上書きの確認)が出ている間も、選んだフォルダを光らせたままにする
  local function finish()
    if not active or active.done then return end
    active.done = true
    local dest, fn = active.target, active.place
    vim.schedule(function()
      pcall(fn, dest)
      stop()
    end)
  end
  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true }) end
  local function bar_button(p)
    if p.winid ~= win or p.winrow ~= 1 then return nil end
    local w1, w2 = vim.fn.strdisplaywidth(BTN_OK), vim.fn.strdisplaywidth(BTN_NO)
    if p.wincol <= w1 then return "ok" end
    if p.wincol >= w1 + 2 and p.wincol <= w1 + 1 + w2 then return "no" end
  end
  map("<LeftMouse>", function()
    local p = vim.fn.getmousepos()
    active.pressed = nil
    if p.winid ~= win then return end
    local btn = bar_button(p)
    if btn then active.pressed = { btn = btn } return end
    if p.line > 0 then
      vim.api.nvim_win_set_cursor(win, { p.line, 0 }) -- 配置先はカーソルに付いてくる(CursorMoved)
      active.pressed = { line = p.line }
    end
  end)
  -- 離したときに動く(押した瞬間に動くと、続けて届く「離す」操作が次の画面に届いてしまうため)
  map("<LeftRelease>", function()
    local pr = active and active.pressed
    if not pr then return end
    active.pressed = nil
    if pr.btn == "ok" then return vim.defer_fn(finish, 100) end
    if pr.btn == "no" then return stop() end
    -- フォルダの行なら開く / 閉じる(いちばん上の行 = 最上位のフォルダは閉じない)
    local st = tree_state()
    local ok, node = pcall(function() return st.tree:get_node(pr.line) end)
    if ok and node and node.type == "directory" and node:get_id() ~= st.path then
      pcall(require("neo-tree.sources.filesystem.commands").toggle_node, st)
    end
  end)
  map("<2-LeftMouse>", "<Nop>")
  map("<2-LeftRelease>", "<Nop>")
  map("<CR>", finish)
  -- キーでも開く / 閉じる(Enter は配置に使うため): Space / l / → で開閉、h / ← で閉じる
  local function node_cmd(cmd)
    local st = tree_state()
    if st then pcall(require("neo-tree.sources.filesystem.commands")[cmd], st) end
  end
  for _, k in ipairs({ "<Space>", "l", "<Right>" }) do map(k, function() node_cmd("toggle_node") end) end
  for _, k in ipairs({ "h", "<Left>" }) do map(k, function() node_cmd("close_node") end) end
  map("<Esc>", stop)
  map("q", stop)
  -- キー(j / k など)やクリックでカーソルが動いたら、配置先も動かす
  active.autocmd = vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if active then
        retarget(vim.api.nvim_win_get_cursor(win)[1])
        update_bar()
      end
    end,
  })
  draw(state, active.target, true)
end

function M.is_active()
  return active ~= nil
end

return M
