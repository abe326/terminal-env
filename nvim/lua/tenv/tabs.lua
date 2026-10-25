-- エディタの pane の上部に出すタブ(VS Code のエディタのタブに寄せる)
--   ・開いているファイルが 1 つずつタブになる。クリックで切り替え、× で閉じる(未保存は ● になり、閉じるときに確認)
--   ・中クリックでも閉じる。最後のタブを閉じるとエディタの pane ごと閉じる
--   ・キー: H / L で前後のタブ、Space x で閉じる
local M = {}

local function set_hl()
  local hl = vim.api.nvim_set_hl
  hl(0, "TenvTabFill", { bg = "#13141c" })
  hl(0, "TenvTab", { fg = "#737aa2", bg = "#16161e" })
  hl(0, "TenvTabSel", { fg = "#e6edf3", bg = "#24283b", bold = true, underline = true, sp = "#7aa2f7" })
  hl(0, "TenvTabClose", { fg = "#565f89", bg = "#16161e" })
  hl(0, "TenvTabCloseSel", { fg = "#c0caf5", bg = "#24283b", underline = true, sp = "#7aa2f7" })
  hl(0, "TenvTabMod", { fg = "#e0af68", bg = "#16161e" })
  hl(0, "TenvTabModSel", { fg = "#e0af68", bg = "#24283b", underline = true, sp = "#7aa2f7" })
end

local function listed()
  local bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) ~= "" then table.insert(bufs, b) end
  end
  return bufs
end

function M.open(path)
  vim.cmd("drop " .. vim.fn.fnameescape(path))
  vim.cmd("redrawtabline")
end

function M.close(b)
  b = b or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(b) then return end
  if vim.bo[b].modified then
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
    local c = vim.fn.confirm(name .. " は保存されていません。保存しますか?", "&保存する\n保存し&ない\n&やめる", 1)
    if c == 1 then
      vim.api.nvim_buf_call(b, function() vim.cmd("write") end)
    elseif c ~= 2 then
      return
    end
  end
  local others = vim.tbl_filter(function(x) return x ~= b end, listed())
  if #others == 0 then
    vim.cmd("qall!")
    return
  end
  if b == vim.api.nvim_get_current_buf() then
    -- 右隣(無ければ左隣)のタブへ移ってから閉じる
    local all = listed()
    local idx = vim.fn.index(all, b) + 1
    vim.api.nvim_set_current_buf(all[idx + 1] or all[idx - 1])
  end
  vim.api.nvim_buf_delete(b, { force = true })
  vim.cmd("redrawtabline")
end

local function step(dir)
  local all = listed()
  local idx = vim.fn.index(all, vim.api.nvim_get_current_buf()) + 1
  if #all == 0 then return end
  vim.api.nvim_set_current_buf(all[(idx - 1 + dir) % #all + 1])
end

_G.TenvTabClick = function(b, _, button)
  if button == "m" then M.close(b) else vim.api.nvim_set_current_buf(b) end
end

_G.TenvTabClose = function(b)
  M.close(b)
end

_G.TenvTabline = function()
  local ok, devicons = pcall(require, "nvim-web-devicons")
  local cur = vim.api.nvim_get_current_buf()
  local parts = {}
  for _, b in ipairs(listed()) do
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t"):gsub("%%", "%%%%")
    local icon = ok and devicons.get_icon(name, nil, { default = true }) or ""
    local sel = b == cur
    local mod = vim.bo[b].modified
    local base = sel and "%#TenvTabSel#" or "%#TenvTab#"
    local close_hl = mod and (sel and "%#TenvTabModSel#" or "%#TenvTabMod#") or (sel and "%#TenvTabCloseSel#" or "%#TenvTabClose#")
    table.insert(parts, table.concat({
      base, "%", b, "@v:lua.TenvTabClick@  ", icon, " ", name, "  %X",
      close_hl, "%", b, "@v:lua.TenvTabClose@", mod and "●" or "×", " %X",
    }))
  end
  return table.concat(parts, "%#TenvTabFill# ") .. "%#TenvTabFill#%="
end

function M.setup()
  set_hl()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.TenvTabline()"
  vim.keymap.set("n", "H", function() step(-1) end, { desc = "前のタブ" })
  vim.keymap.set("n", "L", function() step(1) end, { desc = "次のタブ" })
  vim.keymap.set("n", "<leader>x", function() M.close() end, { desc = "タブを閉じる" })
  vim.api.nvim_create_autocmd({ "BufModifiedSet", "BufEnter", "BufWritePost" }, {
    callback = function() vim.cmd("redrawtabline") end,
  })
end

return M
