-- Markdown のプレビュー(GitHub のダークテーマに寄せた表示)
--   ・md を開くとプレビューで表示する。上部の「プレビュー / 原文」をクリック(または Space v)で切り替える
--   ・同じタブの中で切り替える(別の窓は開かない)
--   ・描画は render-markdown.nvim。見出しの下線(GitHub の H1 / H2)はここで足す
local M = {}

-- GitHub(ダーク)の色
local C = {
  fg = "#e6edf3", muted = "#9198a1", border = "#3d444d", subtle = "#151b23", inline = "#2a313c",
  link = "#4493f8", note = "#4493f8", tip = "#3fb950", important = "#ab7df8", warning = "#d29922", caution = "#f85149",
}

local ns = vim.api.nvim_create_namespace("tenv_md_rule")

local function set_hl()
  local hl = vim.api.nvim_set_hl
  for i = 1, 6 do
    local h = { fg = i == 6 and C.muted or C.fg, bold = true }
    hl(0, "RenderMarkdownH" .. i, h)
    hl(0, "RenderMarkdownH" .. i .. "Bg", h)
    -- 配色テーマ(tokyonight)が見出しに付ける背景を消す(GitHub は見出しに背景が無い)
    hl(0, "@markup.heading." .. i .. ".markdown", h)
    hl(0, "@markup.heading." .. i, h)
  end
  hl(0, "TenvMdRule", { fg = C.border })
  hl(0, "RenderMarkdownCode", { bg = C.subtle })
  hl(0, "RenderMarkdownCodeBorder", { bg = C.subtle })
  hl(0, "RenderMarkdownCodeInfo", { fg = C.muted, bg = C.subtle, italic = true })
  hl(0, "RenderMarkdownCodeInline", { fg = C.fg, bg = C.inline })
  hl(0, "RenderMarkdownBullet", { fg = C.muted })
  hl(0, "RenderMarkdownDash", { fg = C.border })
  hl(0, "RenderMarkdownTableHead", { fg = C.border })
  hl(0, "RenderMarkdownTableRow", { fg = C.border })
  hl(0, "RenderMarkdownQuote", { fg = C.border })
  for i = 1, 6 do hl(0, "RenderMarkdownQuote" .. i, { fg = C.border }) end
  hl(0, "RenderMarkdownLink", { fg = C.link })
  hl(0, "RenderMarkdownLinkTitle", { fg = C.link })
  hl(0, "RenderMarkdownUnchecked", { fg = C.muted })
  hl(0, "RenderMarkdownChecked", { fg = C.link })
  hl(0, "RenderMarkdownInfo", { fg = C.note })
  hl(0, "RenderMarkdownSuccess", { fg = C.tip })
  hl(0, "RenderMarkdownHint", { fg = C.important })
  hl(0, "RenderMarkdownWarn", { fg = C.warning })
  hl(0, "RenderMarkdownError", { fg = C.caution })
  hl(0, "@markup.link.label.markdown_inline", { fg = C.link })
  hl(0, "@markup.link.url.markdown_inline", { fg = C.link, underline = true })
  hl(0, "@markup.quote.markdown", { fg = C.muted })
  hl(0, "@markup.strong.markdown_inline", { fg = C.fg, bold = true })
  hl(0, "@markup.italic.markdown_inline", { fg = C.fg, italic = true })
  -- 切り替えボタン
  hl(0, "TenvMdBar", { fg = C.muted, bg = "#13141c" })
  hl(0, "TenvMdOn", { fg = "#ffffff", bg = "#1f6feb", bold = true })
  hl(0, "TenvMdOff", { fg = C.muted, bg = "#21262d" })
end

-- リンクの前のアイコンを出さない(GitHub はリンクを青い文字で示すだけ)。既定の一覧を空のアイコンで上書きする
local function no_link_icons()
  local custom = {}
  for _, name in ipairs({ "web", "apple", "discord", "github", "gitlab", "google", "hackernews", "linkedin",
    "microsoft", "neovim", "reddit", "slack", "stackoverflow", "steam", "twitter", "wikipedia", "x",
    "youtube", "youtube_short" }) do
    custom[name] = { pattern = "^$", icon = "" }
  end
  return custom
end

function M.opts()
  return {
    file_types = { "markdown" },
    render_modes = { "n", "c", "t" },
    anti_conceal = { enabled = false }, -- カーソル行だけ原文に戻さない(プレビューの見た目を崩さない)
    heading = {
      sign = false,
      icons = { "", "", "", "", "", "" },
      position = "inline",
      width = "full",
      backgrounds = { "RenderMarkdownH1Bg", "RenderMarkdownH2Bg", "RenderMarkdownH3Bg",
        "RenderMarkdownH4Bg", "RenderMarkdownH5Bg", "RenderMarkdownH6Bg" },
    },
    code = {
      sign = false,
      style = "full",
      position = "right",
      language_icon = true,
      language_name = true,
      width = "full",
      left_pad = 2,
      right_pad = 2,
      border = "thin",
      above = "▄",
      below = "▀",
      inline_pad = 1,
    },
    dash = { icon = "─", width = "full" },
    bullet = { icons = { "•", "◦", "▪", "▫" } },
    checkbox = { unchecked = { icon = "󰄱 " }, checked = { icon = "󰱒 " } },
    quote = { icon = "▎" },
    pipe_table = { preset = "none", cell = "padded", style = "full" },
    link = { hyperlink = "", custom = no_link_icons(), image = "󰥶 ", email = "" },
    sign = { enabled = false },
  }
end

-- GitHub の H1 / H2 の下線
local function draw_rules(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not vim.b[buf].tenv_preview then return end
  local width = 0
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do width = math.max(width, vim.api.nvim_win_get_width(w)) end
  local in_fence = false
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^%s*```") or line:match("^%s*~~~") then
      in_fence = not in_fence
    elseif not in_fence and (line:match("^#%s") or line:match("^##%s")) then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
        virt_lines = { { { string.rep("─", math.max(width - 1, 1)), "TenvMdRule" } } },
      })
    end
  end
end

local function winbar(buf)
  local on = vim.b[buf].tenv_preview
  return table.concat({
    "%#TenvMdBar#  ",
    on and "%#TenvMdOn#" or "%#TenvMdOff#", "%1@v:lua.TenvMdSet@ 󰈈 プレビュー %X",
    "%#TenvMdBar# ",
    on and "%#TenvMdOff#" or "%#TenvMdOn#", "%0@v:lua.TenvMdSet@ 󰈮 原文 %X",
    "%#TenvMdBar#   Space v で切り替え%=",
  })
end

--- buf をプレビュー(true)/ 原文(false)にする
function M.set(buf, on)
  buf = buf or vim.api.nvim_get_current_buf()
  vim.b[buf].tenv_preview = on
  vim.api.nvim_buf_call(buf, function()
    pcall(function() require("render-markdown").set_buf(on) end)
  end)
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    vim.wo[w].winbar = winbar(buf)
    vim.wo[w].wrap = true
    vim.wo[w].linebreak = true
    vim.wo[w].number = not on
    vim.wo[w].relativenumber = false
    vim.wo[w].signcolumn = on and "no" or "yes"
    vim.wo[w].cursorline = not on
    vim.wo[w].conceallevel = on and 3 or 0
  end
  draw_rules(buf)
end

_G.TenvMdSet = function(on)
  M.set(vim.api.nvim_get_current_buf(), on == 1)
end

-- プレビューで上へスクロールするときは、カーソルを窓の上端へ移してから送る。
-- 窓に収まらない表は、render-markdown が元の行を隠して仮想行で描く(セルの折り返し)。その上を上へ
-- スクロールすると、Neovim は下端に残ったカーソルを画面に収めようとして表示を戻し、途中で止まる
local function scroll_up(win, count)
  vim.api.nvim_win_call(win, function()
    vim.api.nvim_win_set_cursor(win, { vim.fn.line("w0"), 0 })
    vim.cmd("normal! " .. count .. "\25") -- \25 = Ctrl+Y
  end)
end

local function wheel_up()
  local win = vim.fn.getmousepos().winid
  if win ~= 0 and vim.b[vim.api.nvim_win_get_buf(win)].tenv_preview then
    local n = tonumber(vim.o.mousescroll:match("ver:(%d+)")) or 3
    if n > 0 then scroll_up(win, n) end
  else
    vim.api.nvim_feedkeys(vim.keycode("<ScrollWheelUp>"), "n", false)
  end
end

function M.setup()
  set_hl()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
  local group = vim.api.nvim_create_augroup("tenv_md", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group, pattern = "markdown",
    callback = function(ev)
      if vim.b[ev.buf].tenv_preview == nil then vim.b[ev.buf].tenv_preview = true end
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(ev.buf) then M.set(ev.buf, vim.b[ev.buf].tenv_preview) end
      end)
      vim.keymap.set("n", "<leader>v", function() M.set(ev.buf, not vim.b[ev.buf].tenv_preview) end,
        { buffer = ev.buf, desc = "プレビュー / 原文" })
      vim.keymap.set("n", "<ScrollWheelUp>", wheel_up, { buffer = ev.buf })
      vim.keymap.set("n", "<C-y>", function()
        if vim.b[ev.buf].tenv_preview then scroll_up(0, vim.v.count1) else vim.cmd("normal! " .. vim.v.count1 .. "\25") end
      end, { buffer = ev.buf })
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "InsertLeave", "WinResized" }, {
    group = group,
    callback = function(ev)
      local buf = ev.buf ~= 0 and ev.buf or vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "markdown" then
        if ev.event == "BufWinEnter" then M.set(buf, vim.b[buf].tenv_preview ~= false) else draw_rules(buf) end
      end
    end,
  })
  -- 編集を始めたら原文に、やめたら元に戻す(プレビューのまま文字を打たない)
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group, pattern = "*.md",
    callback = function(ev)
      if vim.b[ev.buf].tenv_preview then vim.b[ev.buf].tenv_back_to_preview = true; M.set(ev.buf, false) end
    end,
  })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group, pattern = "*.md",
    callback = function(ev)
      if vim.b[ev.buf].tenv_back_to_preview then vim.b[ev.buf].tenv_back_to_preview = nil; M.set(ev.buf, true) end
    end,
  })
end

return M
