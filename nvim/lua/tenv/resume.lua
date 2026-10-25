-- 前の作業を再開(Claude Code)の画面。WezTerm が新しいタブの nvim で開く(Shift+Alt+R・「＋」・起動時)
--   ・この PC とリモートの、<日数> 以内の Claude Code の会話を、場所ごとに並べる(tenv/ccsessions.lua)
--   ・チェックを付けたものを再開する: 場所ごとにタブを開き(いつもの並び)、Claude Code の pane で
--     claude --resume <会話> を動かす。リモートでまだ動いているものは、開き直すだけ
--   ・前回開いていたもの(WezTerm を閉じた・機械を再起動したときに動いていたもの)には、最初からチェックが付く
--   ・選んだ結果は、合言葉を付けて WezTerm に渡す(OSC 1337 SetUserVar=tenv_resume)。WezTerm がタブを開く
--   ・起動時(mode = startup)は、前回開いていたものが無ければ何も出さずに閉じる
--   TENV_RESUME(WezTerm が渡す JSON): { mode, days, remotes = { { i, name, host } } }
local M = {}

local ns = vim.api.nvim_create_namespace("tenv_resume")

local function set_hl()
  local hl = vim.api.nvim_set_hl
  hl(0, "TenvResumeHead", { fg = "#1a1b26", bg = "#7aa2f7", bold = true })
  hl(0, "TenvResumeGroup", { fg = "#7aa2f7", bold = true })
  hl(0, "TenvResumeDim", { fg = "#737aa2" })
  hl(0, "TenvResumeCheck", { fg = "#9ece6a", bold = true })
  hl(0, "TenvResumeRun", { fg = "#bb9af7" })
  hl(0, "TenvResumeSel", { bg = "#2d3f76" })
  hl(0, "TenvResumeBtn", { fg = "#c0caf5", bg = "#3b4261" })
  hl(0, "TenvResumeBtnMain", { fg = "#1a1b26", bg = "#9ece6a", bold = true })
end

-- 手元の WezTerm に合図を送る(nvim の出力に混ぜるので、画面の描き直しと重ならない)
local function emit(name, value)
  vim.api.nvim_ui_send("\27]1337;SetUserVar=" .. name .. "=" .. vim.base64.encode(value) .. "\7")
end

local function token()
  local f = io.open((vim.env.LOCALAPPDATA or "") .. "\\tenv\\token", "r")
  if not f then return "" end
  local t = (f:read("*l") or ""):match("^(%x+)") or ""
  f:close()
  return t
end

local function when(t)
  local d, now = os.date("*t", t), os.date("*t")
  local today = os.time({ year = now.year, month = now.month, day = now.day, hour = 0 })
  local hm = string.format("%d:%02d", d.hour, d.min)
  if t >= today then return "今日 " .. hm end
  if t >= today - 86400 then return "昨日 " .. hm end
  return string.format("%d/%d %s", d.month, d.day, hm)
end

local function fit(s, w)
  s = s or ""
  if vim.fn.strdisplaywidth(s) <= w then return s .. string.rep(" ", w - vim.fn.strdisplaywidth(s)) end
  local out = vim.fn.strcharpart(s, 0, w)
  while vim.fn.strdisplaywidth(out) > w - 1 do out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1) end
  return out .. "…" .. string.rep(" ", w - 1 - vim.fn.strdisplaywidth(out))
end

-- 行の状態と、最初からチェックを付けるか(startup = 起動時)
--   remote: いま動いている → 誰も見ていなければ「動いています」(起動時はチェック = 閉じる前に開いていたタブ)、
--           見ていれば「開いています」
--   local : いま動いている → 選べない(別の窓で動いている)
--   前回開いていた(窓を閉じた・再起動で途切れた)→ チェック
local function classify(s, remote, startup)
  if s.running then
    if remote then
      if s.attached then return "開いています", false, true end
      return "動いています", startup, true
    end
    return "この PC で動作中", false, false
  end
  if s.empty then return nil end
  if s.was_open then return "前回開いていた", true, true end
  return "", false, true
end

function M.run()
  set_hl()
  local req = vim.json.decode(vim.env.TENV_RESUME or "{}")
  local days = tonumber(req.days) or 3
  local startup = req.mode == "startup"
  local groups = {} -- { { name, remote_index, sessions } }
  local pending = 0
  local rows, sel = {}, 1
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false
  vim.o.laststatus = 0
  vim.o.showmode = false
  vim.o.ruler = false
  vim.o.mouse = "a"
  vim.o.guicursor = "a:TenvResumeHide"
  vim.api.nvim_set_hl(0, "TenvResumeHide", { blend = 100, nocombine = true })

  local function lines_set(lines)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end
  lines_set({ "", "  前の作業を読み込んでいます…" })

  local buttons = {}
  local function render()
    local width = vim.api.nvim_win_get_width(win)
    local lines, marks = {}, {}
    local function add(text, hl, row_hl)
      table.insert(lines, text)
      if hl then table.insert(marks, { #lines - 1, 0, #text, hl }) end
      if row_hl then table.insert(marks, { #lines - 1, -1, -1, row_hl }) end
    end
    add(fit(string.format(" 󰑓 前の作業を再開(Claude Code・%d 日以内)", days), width), "TenvResumeHead")
    add(" Space・クリック: 選ぶ / 外す   Enter: 再開   Esc: 閉じる   "
      .. (startup and "チェック済みは前回開いていたもの" or "チェック済みは前回途中で閉じたもの"), "TenvResumeDim")
    rows = {}
    local name_w = 26
    local when_w = 12
    local state_w = 16
    -- 3(字下げ)+ 3(箱)+ 1 + 2 + 2 + 2 + 右端の余白 1
    local title_w = math.max(width - name_w - when_w - state_w - 14, 10)
    for _, g in ipairs(groups) do
      add("")
      add(" " .. (g.remote and "󰒋 " or "󰍹 ") .. g.name .. (g.error and ("  " .. g.error) or ""), "TenvResumeGroup")
      if #g.items == 0 and not g.error then add("    (ありません)", "TenvResumeDim") end
      for _, it in ipairs(g.items) do
        local s = it.s
        local box = it.selectable and (it.checked and "[✓]" or "[ ]") or "   "
        local folder = s.cwd:match("([^/\\]+)[/\\]*$") or s.cwd
        local title = s.title or s.first or (s.empty and "(まだ指示なし)" or "")
        local state = fit(it.state, state_w)
        local line = "   " .. box .. " " .. fit(folder, name_w) .. "  " .. fit(title, title_w) .. "  "
          .. fit(when(s.mtime), when_w) .. "  " .. state
        table.insert(lines, line)
        local lnum = #lines - 1
        it.lnum = lnum
        if it.checked then table.insert(marks, { lnum, 3, 3 + #box, "TenvResumeCheck" }) end
        if it.state ~= "" then table.insert(marks, { lnum, #line - #state, #line, "TenvResumeRun" }) end
        if not it.selectable then table.insert(marks, { lnum, 0, #line, "TenvResumeDim" }) end
        if it.selectable then table.insert(rows, it) end
      end
    end
    add("")
    local n = 0
    for _, it in ipairs(rows) do if it.checked then n = n + 1 end end
    local ok_label = string.format(" 再開する(%d 件)⏎ ", n)
    local no_label = " 閉じる Esc "
    local bline = "   " .. ok_label .. "  " .. no_label
    table.insert(lines, bline)
    local blnum = #lines - 1
    buttons = {
      { lnum = blnum, s = 3, e = 3 + #ok_label, action = "ok" },
      { lnum = blnum, s = 3 + #ok_label + 2, e = 3 + #ok_label + 2 + #no_label, action = "no" },
    }
    table.insert(marks, { blnum, buttons[1].s, buttons[1].e, "TenvResumeBtnMain" })
    table.insert(marks, { blnum, buttons[2].s, buttons[2].e, "TenvResumeBtn" })
    lines_set(lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, m in ipairs(marks) do
      if m[2] == -1 then
        vim.api.nvim_buf_set_extmark(buf, ns, m[1], 0, { line_hl_group = m[4] })
      else
        vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = math.min(m[3], #lines[m[1] + 1]), hl_group = m[4] })
      end
    end
    local cur = rows[sel]
    if cur then
      vim.api.nvim_buf_set_extmark(buf, ns, cur.lnum, 0, { line_hl_group = "TenvResumeSel", priority = 50 })
      pcall(vim.api.nvim_win_set_cursor, win, { cur.lnum + 1, 0 })
    end
  end

  local function close() vim.cmd("qa!") end

  local function submit()
    local items = {}
    local by = {}
    for _, g in ipairs(groups) do
      for _, it in ipairs(g.items) do
        if it.checked and it.selectable then
          local key = (g.remote or "L") .. "\t" .. it.s.cwd
          if not by[key] then
            by[key] = { r = g.remote, cwd = it.s.cwd, ids = {} }
            table.insert(items, by[key])
          end
          -- 動いているものは開き直すだけ(再開しない)。まだ指示していないものも同じ
          if not it.s.running and not it.s.empty then table.insert(by[key].ids, it.s.id) end
        end
      end
    end
    if #items == 0 then return close() end
    emit("tenv_resume", vim.json.encode({ token = token(), items = items }))
    vim.defer_fn(close, 300) -- 合図が WezTerm に届いてから閉じる
  end

  local function toggle(it)
    if it and it.selectable then it.checked = not it.checked; render() end
  end

  local function finish_loading()
    local any = false
    for _, g in ipairs(groups) do
      for _, it in ipairs(g.items) do if it.checked then any = true end end
    end
    -- 起動時は、前回開いていたものが無ければ何も出さない
    if startup and not any then return close() end
    sel = 1
    render()
    if startup then emit("tenv_resume_show", "1") end
  end

  local function add_group(name, remote, sessions, err)
    local g = { name = name, remote = remote, items = {}, error = err }
    for _, s in ipairs(sessions or {}) do
      local state, checked, selectable = classify(s, remote ~= nil, startup)
      if state then
        table.insert(g.items, { s = s, state = state, checked = checked, selectable = selectable })
      end
    end
    return g
  end

  -- リモートは ssh で並行して集める(つながらないリモートは見出しに理由を出す)
  local remote_groups = {}
  for _, r in ipairs(req.remotes or {}) do
    pending = pending + 1
    local script = 'p=$(command -v nvim || echo ~/.local/bin/nvim); exec "$p" --clean --headless -l '
      .. '"${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lua/tenv/ccsessions.lua" ' .. days
    local cmd = "sh -c 'eval \"$(echo " .. vim.base64.encode(script) .. " | base64 -d)\"'"
    local slot = #remote_groups + 1
    remote_groups[slot] = false
    vim.system({ "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "--", r.host, cmd }, { text = true },
      vim.schedule_wrap(function(res)
        local ok, list = pcall(vim.json.decode, res.stdout or "")
        if res.code == 0 and ok and type(list) == "table" then
          remote_groups[slot] = add_group(r.name, r.i, list)
        else
          remote_groups[slot] = add_group(r.name, r.i, {}, "(つながりません)")
        end
        pending = pending - 1
        if pending == 0 then
          groups = {}
          for _, g in ipairs(remote_groups) do if g then table.insert(groups, g) end end
          table.insert(groups, M._local_group)
          finish_loading()
        end
      end))
  end
  M._local_group = add_group("この PC", nil, require("tenv.ccsessions").list(days))
  if pending == 0 then
    groups = { M._local_group }
    finish_loading()
  end

  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true }) end
  local function move(d)
    if #rows == 0 then return end
    sel = math.max(1, math.min(#rows, sel + d))
    render()
  end
  for _, k in ipairs({ "j", "<Down>" }) do map(k, function() move(1) end) end
  for _, k in ipairs({ "k", "<Up>" }) do map(k, function() move(-1) end) end
  map("<Space>", function() toggle(rows[sel]) end)
  map("x", function() toggle(rows[sel]) end)
  map("<CR>", submit)
  map("<Esc>", close)
  map("q", close)
  map("<LeftMouse>", function()
    local p = vim.fn.getmousepos()
    if p.winid ~= win then return end
    for _, b in ipairs(buttons) do
      if p.line - 1 == b.lnum and p.column - 1 >= b.s and p.column - 1 < b.e then
        return b.action == "ok" and submit() or close()
      end
    end
    for i, it in ipairs(rows) do
      if it.lnum == p.line - 1 then
        sel = i
        return toggle(it)
      end
    end
  end)
  for _, k in ipairs({ "<2-LeftMouse>", "<LeftRelease>", "<LeftDrag>", "<RightMouse>" }) do map(k, "<Nop>") end
  vim.api.nvim_create_autocmd("VimResized", { buffer = buf, callback = function() if #groups > 0 then render() end end })
end

return M
