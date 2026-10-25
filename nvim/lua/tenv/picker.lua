-- ファイル名の検索(VS Code の Ctrl+P)と、文字列の検索(Ctrl+Shift+F)
--   ・telescope.nvim の画面で探し、選んだファイルはエディタのタブで開く(文字列は、その行へ移る)
--   ・ツリーの pane は狭いので、ツリーからはエディタ(右上段)の中で開く(tenv/editor.lua の pick)
--   ・ripgrep(rg)を使う。無ければ入れるよう案内する
local M = {}

-- 何も開いていない空のタブ(エディタを検索のために起動したとき)
local function empty_bufs()
  return vim.tbl_filter(function(b)
    return vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) == "" and not vim.bo[b].modified
      and vim.api.nvim_buf_line_count(b) <= 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == ""
  end, vim.api.nvim_list_bufs())
end

local function real_bufs()
  return vim.tbl_filter(function(b)
    return vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) ~= ""
  end, vim.api.nvim_list_bufs())
end

local function open(path, lnum, col)
  local empties = empty_bufs()
  if vim.g.tenv_editor == 1 then require("tenv.tabs").open(path) else vim.cmd("drop " .. vim.fn.fnameescape(path)) end
  if lnum then pcall(vim.api.nvim_win_set_cursor, 0, { lnum, math.max((col or 1) - 1, 0) }) end
  for _, b in ipairs(empties) do
    if b ~= vim.api.nvim_get_current_buf() then pcall(vim.api.nvim_buf_delete, b, {}) end
  end
  vim.cmd("redrawtabline")
end

vim.api.nvim_set_hl(0, "TenvPickerClose", { fg = "#f7768e", bold = true, default = true })

-- 検索の画面の右上に × を置く(クリックで閉じる)。戻り値は × の窓
local function add_close_button(picker)
  local top, right
  for _, w in ipairs({ picker.results_win, picker.prompt_win, picker.preview_win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      local pos = vim.api.nvim_win_get_position(w)
      local r = pos[2] + vim.api.nvim_win_get_width(w)
      top = top and math.min(top, pos[1]) or pos[1]
      right = right and math.max(right, r) or r
    end
  end
  if not top then return nil end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " ✕ " })
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = math.max(top - 1, 0), col = math.max(right - 3, 0), width = 3, height = 1,
    style = "minimal", focusable = true, zindex = 300,
  })
  vim.wo[win].winhighlight = "Normal:TenvPickerClose"
  return win
end

--- kind: "files"(ファイル名)/ "grep"(文字列)。root: 探す場所
function M.run(kind, root)
  if vim.fn.executable("rg") ~= 1 then
    vim.notify("検索には ripgrep(rg)が要ります(README の導入手順を参照)", vim.log.levels.WARN)
    return
  end
  local ok, builtin = pcall(require, "telescope.builtin")
  if not ok then
    vim.notify("telescope.nvim が読み込めません(:Lazy sync を試してください)", vim.log.levels.WARN)
    return
  end
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  local chosen = false
  -- 検索をやめたとき、何も開いていないエディタなら閉じる(検索のために起動したエディタを残さない)
  local function after_close()
    vim.defer_fn(function()
      if not chosen and vim.g.tenv_editor == 1 and #real_bufs() == 0 then vim.cmd("qall!") end
    end, 100)
  end
  local opts = {
    cwd = root,
    prompt_title = kind == "files" and "ファイル名で探す" or "文字列で探す",
    results_title = vim.fn.fnamemodify(root, ":~"),
    attach_mappings = function(bufnr, map)
      -- × と、画面の外のクリックでも閉じる(Esc だけだと閉じ方が分かりにくいため)
      local close_win
      vim.schedule(function()
        local picker = state.get_current_picker(bufnr)
        if picker then close_win = add_close_button(picker) end
      end)
      actions.close:enhance({
        post = function()
          if close_win and vim.api.nvim_win_is_valid(close_win) then vim.api.nvim_win_close(close_win, true) end
          after_close()
        end,
      })
      local function click()
        local pos = vim.fn.getmousepos()
        if pos.winid == close_win then return actions.close(bufnr) end
        -- 浮いている窓(検索の画面とその枠)の外 = 下のエディタやツリーをクリックした
        if pos.winid == 0 or vim.api.nvim_win_get_config(pos.winid).relative == "" then return actions.close(bufnr) end
        actions.mouse_click(bufnr)
      end
      map("i", "<LeftMouse>", click)
      map("n", "<LeftMouse>", click)
      actions.select_default:replace(function()
        local e = state.get_selected_entry()
        chosen = e ~= nil
        actions.close(bufnr)
        if not e then return end
        local path = e.path or e.filename or e[1]
        if path and not vim.startswith(path, "/") and not path:match("^%a:[\\/]") then
          path = vim.fs.joinpath(root, path)
        end
        vim.schedule(function() open(path, e.lnum, e.col) end)
      end)
      return true
    end,
  }
  -- パスの区切りは Windows でも / にそろえる(VS Code と同じく「nvim/keys」のように探せる)
  if kind == "files" then
    builtin.find_files(vim.tbl_extend("force", opts, {
      find_command = { "rg", "--files", "--hidden", "--glob", "!.git", "--path-separator", "/" },
    }))
  else
    builtin.live_grep(vim.tbl_extend("force", opts, { additional_args = { "--hidden", "--glob", "!.git", "--path-separator", "/" } }))
  end
end

return M
