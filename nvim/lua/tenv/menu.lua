-- 右クリックメニュー(VS Code の右クリックメニューに寄せた浮き窓)
--   ・ボタンを「離したとき」に開く(押した瞬間に開くと、離した操作で先頭の項目が選ばれてしまうため)
--   ・マウスを乗せた項目が光る / クリックで実行 / 外をクリックすると閉じる
--   ・キーでも使える: ↑↓ / j k で移動、Enter で実行、数字で直接実行、Esc / q で閉じる
local M = {}

local ns = vim.api.nvim_create_namespace("tenv_menu")
local state

local function set_hl()
  local hl = vim.api.nvim_set_hl
  hl(0, "TenvMenu", { fg = "#c0caf5", bg = "#1a1b26" })
  hl(0, "TenvMenuBorder", { fg = "#3b4261", bg = "NONE" })
  hl(0, "TenvMenuCursor", { blend = 100, nocombine = true })
  hl(0, "TenvMenuSel", { fg = "#ffffff", bg = "#2d3f76", bold = true })
  hl(0, "TenvMenuIcon", { fg = "#7aa2f7", bg = "NONE" })
  hl(0, "TenvMenuKey", { fg = "#565f89", bg = "NONE" })
  hl(0, "TenvMenuSep", { fg = "#3b4261", bg = "NONE" })
end
set_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

function M.close()
  if not state then return end
  local s = state
  state = nil
  vim.o.mousemoveevent = s.prev_mousemove
  vim.o.guicursor = s.prev_guicursor
  if vim.api.nvim_win_is_valid(s.win) then vim.api.nvim_win_close(s.win, true) end
  if s.return_win and vim.api.nvim_win_is_valid(s.return_win) then
    pcall(vim.api.nvim_set_current_win, s.return_win)
  end
end

function M.is_open()
  return state ~= nil
end

local function selectable(line)
  local it = state and state.items[line]
  return it ~= nil and it ~= "-"
end

local function move(dir)
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  local n = #state.items
  for _ = 1, n do
    line = (line - 1 + dir) % n + 1
    if selectable(line) then break end
  end
  vim.api.nvim_win_set_cursor(state.win, { line, 0 })
end

local function choose(line)
  if not selectable(line) then return end
  local action = state.items[line].action
  M.close()
  vim.schedule(action)
end

local clicked_at = 0

--- 項目をクリックで選んだ直後か(ダブルクリックとみなす時間内)。
--- 項目をダブルクリックされたとき、2 回目のクリックが下のツリーに届いてファイルを開いてしまわないよう、呼ぶ側で無視する
function M.just_clicked()
  return vim.uv.now() - clicked_at < vim.o.mousetime
end

local function nth(n)
  local count = 0
  for i, it in ipairs(state.items) do
    if it ~= "-" then
      count = count + 1
      if count == n then return i end
    end
  end
end

--- at: "mouse"(右クリックした位置)/ "cursor"(カーソルの下)
--- items: { { icon = "", label = "", key = "O", action = function() end }, "-", ... }
function M.open(at, items)
  M.close()
  local rows = {}
  local width = 0
  for _, it in ipairs(items) do
    if it ~= "-" then
      local w = vim.fn.strdisplaywidth(" " .. it.icon .. "  " .. it.label) + vim.fn.strdisplaywidth(it.key or "") + 5
      width = math.max(width, w)
    end
  end

  for i, it in ipairs(items) do
    if it == "-" then
      rows[i] = string.rep("─", width)
    else
      local left = " " .. it.icon .. "  " .. it.label
      local right = (it.key or "") .. " "
      rows[i] = left .. string.rep(" ", width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right)) .. right
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "tenvmenu"
  for i, it in ipairs(items) do
    if it == "-" then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #rows[i], hl_group = "TenvMenuSep" })
    else
      local icon_end = 1 + #it.icon
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 1, { end_col = icon_end, hl_group = "TenvMenuIcon" })
      if it.key then
        local key_start = #rows[i] - #it.key - 1
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, key_start, { end_col = key_start + #it.key, hl_group = "TenvMenuKey" })
      end
    end
  end

  local return_win = vim.api.nvim_get_current_win()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = at == "cursor" and "cursor" or "mouse", row = at == "cursor" and 1 or 0, col = 0,
    width = width, height = #rows,
    style = "minimal", border = "rounded", zindex = 250,
  })
  vim.wo[win].winhighlight = "Normal:TenvMenu,FloatBorder:TenvMenuBorder,CursorLine:TenvMenuSel"
  vim.wo[win].cursorline = true

  state = { win = win, buf = buf, items = items, return_win = return_win,
    prev_mousemove = vim.o.mousemoveevent, prev_guicursor = vim.o.guicursor }
  vim.o.mousemoveevent = true -- マウスを乗せた項目を光らせる
  vim.o.guicursor = "a:TenvMenuCursor" -- メニューの上ではカーソルを見せない(選択中の行の色で示す)
  vim.api.nvim_win_set_cursor(win, { nth(1), 0 })

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("j", function() move(1) end)
  map("<Down>", function() move(1) end)
  map("<Tab>", function() move(1) end)
  map("k", function() move(-1) end)
  map("<Up>", function() move(-1) end)
  map("<S-Tab>", function() move(-1) end)
  map("<CR>", function() choose(vim.api.nvim_win_get_cursor(win)[1]) end)
  map("<Space>", function() choose(vim.api.nvim_win_get_cursor(win)[1]) end)
  map("<Esc>", M.close)
  map("q", M.close)
  for n = 1, 9 do
    map(tostring(n), function() local l = nth(n); if l then choose(l) end end)
  end

  -- マウス
  map("<MouseMove>", function()
    local p = vim.fn.getmousepos()
    if p.winid == win and selectable(p.line) then vim.api.nvim_win_set_cursor(win, { p.line, 0 }) end
  end)
  local function left()
    local p = vim.fn.getmousepos()
    if p.winid == win then
      if selectable(p.line) then clicked_at = vim.uv.now() end
      choose(p.line)
    else
      M.close()
    end
  end
  -- 外で右クリック: 閉じて、押した行を選び直す(離したときに、その行のメニューが開く)
  local function right()
    local p = vim.fn.getmousepos()
    if p.winid == win then return end
    M.close()
    if p.winid ~= 0 and vim.api.nvim_win_is_valid(p.winid) and p.line > 0 then
      pcall(vim.api.nvim_set_current_win, p.winid)
      pcall(vim.api.nvim_win_set_cursor, p.winid, { p.line, 0 })
    end
  end
  -- 素早く続けて押すと 2- / 3- / 4- 付きで届く(押し忘れると nvim 標準の英語メニューが出る)
  for _, n in ipairs({ "", "2-", "3-", "4-" }) do
    map("<" .. n .. "LeftMouse>", left)
    map("<" .. n .. "RightMouse>", right)
    for _, lhs in ipairs({ "LeftRelease", "LeftDrag", "RightRelease", "RightDrag", "MiddleMouse" }) do
      map("<" .. n .. lhs .. ">", "<Nop>")
    end
  end
  map("<ScrollWheelUp>", "<Nop>")
  map("<ScrollWheelDown>", "<Nop>")

  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    buffer = buf, once = true,
    callback = function() vim.schedule(function() if state and state.buf == buf then M.close() end end) end,
  })
end

return M
