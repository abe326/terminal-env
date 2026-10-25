-- ツリーの下にまとめて出す、確認・入力・お知らせ
--   どれもツリーの幅いっぱいで、最下段(Git の表示)のすぐ上に出す(ツリーは狭いので、中央ではなく下に寄せる)
--   M.open{ title, lines, buttons = { { label, value }, ... }, danger, cancel_value } , on_choice(value)
--     ・確認。閉じるまで他は触れない(モーダル)
--     ・Enter = 選んでいるボタン(最初は先頭)、Esc = やめる(cancel_value)。← → ↑ ↓ / Tab で選び直す
--     ・ボタンはマウスを乗せると光り、クリックで決まる。1 行に収まらなければ縦に並べる
--     ・本文が長いときは、入る分だけ出して「ほか N 行」と書く
--   M.confirm(title, lines, ok_label, on_choice(bool), danger) : はい / いいえ
--   M.input{ title, hint, default } , on_submit(text) : 1 行の入力(新しいファイル名・名前の変更など)
--   M.toast(text) : 選ぶ必要のないお知らせ。数秒だけ出す
local M = {}

local ns = vim.api.nvim_create_namespace("tenv_dialog")
local open_state

local function set_hl()
  local hl = vim.api.nvim_set_hl
  hl(0, "TenvDlg", { fg = "#c0caf5", bg = "#1f2335" })
  hl(0, "TenvDlgBorder", { fg = "#7aa2f7", bg = "#1f2335" })
  hl(0, "TenvDlgDangerBorder", { fg = "#f7768e", bg = "#1f2335" })
  hl(0, "TenvDlgTitle", { fg = "#1a1b26", bg = "#7aa2f7", bold = true })
  hl(0, "TenvDlgDangerTitle", { fg = "#1a1b26", bg = "#f7768e", bold = true })
  hl(0, "TenvDlgBtn", { fg = "#c0caf5", bg = "#3b4261" })
  hl(0, "TenvDlgBtnSel", { fg = "#1a1b26", bg = "#7aa2f7", bold = true })
  hl(0, "TenvDlgBtnDanger", { fg = "#1a1b26", bg = "#f7768e", bold = true })
  hl(0, "TenvDlgHint", { fg = "#737aa2", bg = "#1f2335" })
  hl(0, "TenvDlgCursor", { blend = 100, nocombine = true })
  hl(0, "TenvToast", { fg = "#1a1b26", bg = "#9ece6a" })
end
set_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

-- 文字列を幅で折り返す(日本語は 2 桁)
local function wrap(text, width)
  local out = {}
  for _, para in ipairs(vim.split(tostring(text), "\n", { plain = true })) do
    local line, w = "", 0
    for _, ch in ipairs(vim.fn.split(para, "\\zs")) do
      local cw = vim.fn.strdisplaywidth(ch)
      if w + cw > width and line ~= "" then
        table.insert(out, line)
        line, w = "", 0
      end
      line, w = line .. ch, w + cw
    end
    table.insert(out, line)
  end
  return out
end

-- 下に寄せたときの行(枠を含めた高さ total_h のもの)。最下段(statusline)とコマンド行の分を空ける
local function bottom_row(total_h)
  local reserved = vim.o.cmdheight + (vim.o.laststatus > 0 and 1 or 0)
  return math.max(vim.o.lines - reserved - total_h, 0)
end

-- 中身の幅(枠の内側)。ツリーの幅いっぱい
local function inner_width()
  return math.max(vim.o.columns - 2, 12)
end

local function close(value)
  local s = open_state
  if not s then return end
  open_state = nil
  vim.o.mousemoveevent = s.prev_mousemove
  vim.o.guicursor = s.prev_guicursor
  pcall(vim.api.nvim_del_autocmd, s.autocmd)
  if vim.api.nvim_win_is_valid(s.win) then vim.api.nvim_win_close(s.win, true) end
  if vim.api.nvim_win_is_valid(s.return_win) then pcall(vim.api.nvim_set_current_win, s.return_win) end
  vim.schedule(function() s.on_choice(value) end)
end

local function draw_buttons(s)
  vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  if s.hint_row then vim.api.nvim_buf_set_extmark(s.buf, ns, s.hint_row, 0, { line_hl_group = "TenvDlgHint" }) end
  for i, b in ipairs(s.buttons) do
    local group = "TenvDlgBtn"
    if i == s.sel then group = (s.danger and b.value ~= s.cancel_value) and "TenvDlgBtnDanger" or "TenvDlgBtnSel" end
    vim.api.nvim_buf_set_extmark(s.buf, ns, b.row, b.col_start, { end_col = b.col_end, hl_group = group })
  end
end

function M.is_open()
  return open_state ~= nil
end

function M.open(opts, on_choice)
  if open_state then close(open_state.cancel_value) end
  local buttons = opts.buttons or { { label = "OK", value = true } }
  local cancel_value = opts.cancel_value
  if cancel_value == nil then cancel_value = buttons[#buttons].value end
  local width = inner_width()

  -- ボタン: 1 行に収まれば横に並べ、収まらなければ縦に並べる
  local btn_text, btn_width = {}, 0
  for _, b in ipairs(buttons) do
    local t = " " .. b.label .. " "
    table.insert(btn_text, t)
    btn_width = btn_width + vim.fn.strdisplaywidth(t) + 1
  end
  local horizontal = btn_width + 1 <= width
  local btn_rows = horizontal and 1 or #buttons

  -- 本文: 入る分だけ(画面の高さから、枠・空行・ボタン・最下段の分を引く)
  local body = {}
  for _, l in ipairs(opts.lines or {}) do vim.list_extend(body, wrap(l, width - 2)) end
  while #body > 0 and body[#body] == "" do table.remove(body) end
  local max_body = math.max(vim.o.lines - 2 - 2 - btn_rows - 3, 2) -- 枠・最下段・ボタン・空行・案内の行
  if #body > max_body then
    local rest = #body - (max_body - 1)
    body = vim.list_slice(body, 1, max_body - 1)
    table.insert(body, "…ほか " .. rest .. " 行")
  end

  local rows = {}
  for _, l in ipairs(body) do table.insert(rows, " " .. l) end
  table.insert(rows, "")
  local placed = {}
  if horizontal then
    local line = " "
    for i, t in ipairs(btn_text) do
      local start = #line
      line = line .. t
      placed[i] = { value = buttons[i].value, row = #rows, col_start = start, col_end = #line,
        scol = vim.fn.strdisplaywidth(line) - vim.fn.strdisplaywidth(t), ecol = vim.fn.strdisplaywidth(line) }
      line = line .. " "
    end
    table.insert(rows, line)
  else
    for i, t in ipairs(btn_text) do
      local text = t .. string.rep(" ", math.max(width - 2 - vim.fn.strdisplaywidth(t), 0))
      local line = " " .. text
      placed[i] = { value = buttons[i].value, row = #rows, col_start = 1, col_end = #line, scol = 1, ecol = width - 1 }
      table.insert(rows, line)
    end
  end

  -- 操作の案内は枠の内側の最後の行に、右寄せで出す(枠の線に重ねると、tmux 越しで角が欠けて見えるため)
  local hint = #buttons > 1 and "Enter:決定 Esc:やめる" or "Enter:閉じる"
  local hint_row = #rows
  table.insert(rows, string.rep(" ", math.max(width - 1 - vim.fn.strdisplaywidth(hint), 0)) .. hint)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local return_win = vim.api.nvim_get_current_win()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded", zindex = 400,
    width = width, height = #rows, row = bottom_row(#rows + 2), col = 0,
    title = { { " " .. (opts.title or "確認") .. " ", opts.danger and "TenvDlgDangerTitle" or "TenvDlgTitle" } },
    title_pos = "left",
  })
  vim.wo[win].winhighlight = "Normal:TenvDlg,FloatBorder:" .. (opts.danger and "TenvDlgDangerBorder" or "TenvDlgBorder")
  vim.wo[win].wrap = false

  local s = {
    win = win, buf = buf, return_win = return_win, buttons = placed, sel = 1, hint_row = hint_row,
    danger = opts.danger, cancel_value = cancel_value, on_choice = on_choice,
    prev_mousemove = vim.o.mousemoveevent, prev_guicursor = vim.o.guicursor,
  }
  open_state = s
  vim.o.mousemoveevent = true
  vim.o.guicursor = "a:TenvDlgCursor" -- カーソルは見せない(選んでいるボタンの色で示す)
  draw_buttons(s)

  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true }) end
  local function move(d) s.sel = (s.sel - 1 + d) % #placed + 1; draw_buttons(s) end
  local function button_at(p)
    if p.winid ~= win then return nil end
    for i, b in ipairs(placed) do
      if p.line - 1 == b.row and p.wincol - 1 >= b.scol and p.wincol - 1 < b.ecol then return i end
    end
  end
  map("<CR>", function() close(placed[s.sel].value) end)
  map("<Space>", function() close(placed[s.sel].value) end)
  map("<Esc>", function() close(cancel_value) end)
  map("q", function() close(cancel_value) end)
  for _, k in ipairs({ "<Right>", "<Down>", "<Tab>", "l", "j" }) do map(k, function() move(1) end) end
  for _, k in ipairs({ "<Left>", "<Up>", "<S-Tab>", "h", "k" }) do map(k, function() move(-1) end) end
  map("<MouseMove>", function()
    local i = button_at(vim.fn.getmousepos())
    if i and i ~= s.sel then s.sel = i; draw_buttons(s) end
  end)
  -- クリック: ボタンなら決める(離したとき)。外をクリックしても閉じない(モーダル)
  map("<LeftMouse>", function()
    s.pressed = button_at(vim.fn.getmousepos())
  end)
  map("<LeftRelease>", function()
    local i = button_at(vim.fn.getmousepos())
    if i and i == s.pressed then close(placed[i].value) end
    s.pressed = nil
  end)
  for _, k in ipairs({ "<2-LeftMouse>", "<2-LeftRelease>", "<LeftDrag>", "<RightMouse>", "<RightRelease>",
    "<ScrollWheelUp>", "<ScrollWheelDown>" }) do
    map(k, "<Nop>")
  end
  -- 開いている間は、ほかの窓へ移れない
  s.autocmd = vim.api.nvim_create_autocmd("WinEnter", {
    callback = function()
      if open_state == s and vim.api.nvim_get_current_win() ~= win and vim.api.nvim_win_is_valid(win) then
        vim.schedule(function() if open_state == s then pcall(vim.api.nvim_set_current_win, win) end end)
      end
    end,
  })
end

--- 確認(はい / いいえ)。on_choice(true / false)
function M.confirm(title, lines, ok_label, on_choice, danger)
  M.open({
    title = title, lines = lines, danger = danger,
    buttons = { { label = ok_label, value = true }, { label = "やめる", value = false } },
  }, on_choice)
end

--- 1 行の入力欄(新しいファイル名・名前の変更など)
--- opts = { title, hint, default }。on_submit(text) は Enter のときだけ呼ぶ(Esc ではなにもしない)
function M.input(opts, on_submit)
  local width = inner_width()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.default or "" })
  local return_win = vim.api.nvim_get_current_win()
  -- 説明(hint)は入力の下に、書き換えられない行として出す
  -- 説明と操作の案内(Enter / Esc)は、入力の下に書き換えられない行として出す(枠の線には重ねない)
  local hint_lines = opts.hint and wrap(opts.hint, width - 1) or {}
  local keys = "Enter:決定 Esc:やめる"
  table.insert(hint_lines, string.rep(" ", math.max(width - 1 - vim.fn.strdisplaywidth(keys), 0)) .. keys)
  local virt = {}
  for _, l in ipairs(hint_lines) do table.insert(virt, { { l, "TenvDlgHint" } }) end
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { virt_lines = virt })
  local height = 1 + #hint_lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded", zindex = 400,
    width = width, height = height, row = bottom_row(height + 2), col = 0,
    title = { { " " .. (opts.title or "入力") .. " ", "TenvDlgTitle" } }, title_pos = "left",
  })
  vim.wo[win].winhighlight = "Normal:TenvDlg,FloatBorder:TenvDlgBorder"
  vim.cmd("startinsert!")
  local done = false
  local function finish(text)
    if done then return end
    done = true
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_win_is_valid(return_win) then pcall(vim.api.nvim_set_current_win, return_win) end
    if text then vim.schedule(function() on_submit(text) end) end
  end
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set({ "i", "n" }, "<CR>", function() finish(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or "") end, o)
  vim.keymap.set({ "i", "n" }, "<Esc>", function() finish(nil) end, o)
  vim.keymap.set({ "i", "n" }, "<C-c>", function() finish(nil) end, o)
  vim.keymap.set("n", "q", function() finish(nil) end, o)
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = function() finish(nil) end })
end

--- 選ぶ必要のないお知らせ。ツリーの下に数秒だけ出す(確認や入力が出ているときは、その上に出す)
local toast_win
function M.toast(text, ms)
  if toast_win and vim.api.nvim_win_is_valid(toast_win) then vim.api.nvim_win_close(toast_win, true) end
  local width = inner_width() + 2
  local lines = wrap(text, width - 2)
  for i, l in ipairs(lines) do lines[i] = " " .. l end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  local row = bottom_row(#lines)
  if open_state and vim.api.nvim_win_is_valid(open_state.win) then
    row = math.max(vim.api.nvim_win_get_position(open_state.win)[1] - 1 - #lines, 0)
  end
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative = "editor", style = "minimal", focusable = false, zindex = 350,
    width = width, height = #lines, row = row, col = 0,
  })
  if not ok then return end
  toast_win = win
  vim.wo[win].winhighlight = "Normal:TenvToast"
  vim.defer_fn(function() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end, ms or 2500)
end

return M
