-- ツリーの最下段(フッター)に出す Git の状態
--   ・リモート先(owner/repo。無ければ「リモートなし」)
--   ・未コミットのファイル数
--   ・未 push のコミットがあるか(どのリモートにも無いコミットがあれば「未push」)
-- git は裏で実行し、結果だけを表示する(表示のたびには実行しない)。調べ直すのは:
--   ・.git の中が変わったとき・ツリーの Git の状態が変わったとき(neo-tree の監視の知らせ。コミット・push・add など)
--   ・保存したとき・窓に戻ったとき
--   ・念のため 10 秒ごと(閉じたフォルダの中の変更は、上の知らせが来ないため)
-- 起動を遅くしないよう、リポジトリの場所とリモートは git を起動せずにファイルから読む
local M = {}

local INTERVAL = 10000
local info = { kind = "loading" }
local running = false
local again = false -- 調べている間に次の知らせが来たら、終わってからもう一度

local function set_hl()
  local hl = vim.api.nvim_set_hl
  hl(0, "TenvGitBar", { fg = "#a9b1d6", bg = "#1f2335" })
  hl(0, "TenvGitDim", { fg = "#565f89", bg = "#1f2335" })
  hl(0, "TenvGitRepo", { fg = "#7aa2f7", bg = "#1f2335", bold = true })
  hl(0, "TenvGitDirty", { fg = "#e0af68", bg = "#1f2335", bold = true })
  hl(0, "TenvGitClean", { fg = "#9ece6a", bg = "#1f2335" })
  hl(0, "TenvGitAhead", { fg = "#ff9e64", bg = "#1f2335", bold = true })
end
set_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

local function root()
  local ok, state = pcall(function() return require("neo-tree.sources.manager").get_state("filesystem") end)
  return ok and state and state.path or vim.fn.getcwd()
end

-- scp 形式(git@host:owner/repo.git)/ https://host/owner/repo / ssh://git@host:22/owner/repo.git → host, owner/repo
local function parse_remote(url)
  local host, path = url:match("^%w+://[^@/]*@?([^/:]+):?%d*/(.+)$")
  if not host then host, path = url:match("^[^@]+@([^:]+):(.+)$") end
  if not host then return nil, url:gsub("%.git$", "") end
  return host, path:gsub("%.git$", ""):gsub("/$", "")
end

-- --no-optional-locks: 調べるだけで index.lock を取らない(Claude Code などが同時に git を使っても邪魔しない)
-- core.fsmonitor=false: 開いたフォルダの .git/config に書かれたコマンドを、git status のたびに動かさない
--   (よそから持ってきたフォルダを開いただけで、仕込まれたコマンドが動くのを防ぐ)
local function git(dir, args, cb)
  local cmd = { "git", "--no-optional-locks", "-c", "core.fsmonitor=false", "-C", dir }
  vim.list_extend(cmd, args)
  local ok = pcall(vim.system, cmd, { text = true }, function(r) cb(r.code == 0 and r.stdout or nil) end)
  if not ok then cb(nil) end
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- リポジトリの設定ファイル(.git/config)。.git がファイルのとき(worktree・submodule)は、その指す先から探す
local function config_path(top)
  local dotgit = top .. "/.git"
  local st = vim.uv.fs_stat(dotgit)
  if st and st.type == "directory" then return dotgit .. "/config" end
  local gitdir = (read(dotgit) or ""):match("gitdir:%s*(.-)%s*$")
  if not gitdir then return nil end
  -- .git ファイルの gitdir が UNC(ネットワークの場所)を指すときは読まない(開いただけで SMB 接続・認証が走る)
  if gitdir:match("^[/\\][/\\]") then return nil end
  if not gitdir:match("^/") and not gitdir:match("^%a:[\\/]") then gitdir = top .. "/" .. gitdir end
  local common = vim.trim(read(gitdir .. "/commondir") or "")
  if common ~= "" then
    if common:match("^[/\\][/\\]") then return nil end
    if not common:match("^/") and not common:match("^%a:[\\/]") then common = gitdir .. "/" .. common end
    return common .. "/config"
  end
  return gitdir .. "/config"
end

-- [remote "名前"] の url を読む
local function read_remotes(top)
  local path = config_path(top)
  local text = path and read(path)
  local remotes, current = {}, nil
  for line in (text or ""):gmatch("[^\r\n]+") do
    local section, name = line:match('^%s*%[%s*([%w%.%-]+)%s+"(.-)"%s*%]')
    if section then
      current = section:lower() == "remote" and name or nil
    elseif line:match("^%s*%[") then
      current = nil
    elseif current then
      local url = line:match("^%s*[Uu][Rr][Ll]%s*=%s*(.-)%s*$")
      if url and not remotes[current] then remotes[current] = url end
    end
  end
  return remotes
end

local function update()
  if running then again = true return end
  running = true
  local top = vim.fs.root(root(), ".git")
  local function finish(new)
    running = false
    if not vim.deep_equal(new, info) then
      info = new
      vim.schedule(function() vim.cmd("redrawstatus!") end)
    end
    if again then
      again = false
      vim.schedule(update)
    end
  end
  if not top then return finish({ kind = "none" }) end

  local remotes = read_remotes(top)
  local name = remotes.origin and "origin" or next(remotes)
  local host, repo
  if name then host, repo = parse_remote(remotes[name]) end
  local res, pending = {}, name and 2 or 1
  local function done()
    pending = pending - 1
    if pending > 0 then return end
    local changed = 0
    for _ in (res.status or ""):gmatch("[^\n]+") do changed = changed + 1 end
    finish({ kind = "repo", top = top, host = host, repo = repo, changed = changed,
      ahead = tonumber(vim.trim(res.ahead or "0")) or 0 })
  end
  git(top, { "status", "--porcelain", "-uall" }, function(out) res.status = out; done() end)
  -- 未 push は、リモートがあるときだけ調べる
  if name then git(top, { "rev-list", "--count", "HEAD", "--not", "--remotes" }, function(out) res.ahead = out; done() end) end
end

-- 知らせが続けて来ても、まとめて 1 回だけ調べる
local queued = false
local function request()
  if queued then return end
  queued = true
  vim.defer_fn(function()
    queued = false
    update()
  end, 300)
end

local function esc(s) return (s:gsub("%%", "%%%%")) end

function M.render()
  if info.kind == "loading" then return "%#TenvGitDim# 󰊢 …" end
  if info.kind == "none" then return "%#TenvGitDim# 󰊢 Git 管理外" end
  local changes = info.changed > 0 and { "TenvGitDirty", "● 変更 " .. info.changed } or { "TenvGitClean", "✓ 変更なし" }
  local push
  if info.repo then
    push = info.ahead > 0 and { "TenvGitAhead", "↑未push" } or { "TenvGitDim", "push済" }
  end
  local right = " " .. changes[2] .. (push and "  " .. push[2] or "") .. " "

  -- 幅が足りないときは、件数と push の有無を優先して見せる(リモート名は所有者を省き、それでも長ければ切り詰める)
  local width = vim.api.nvim_win_get_width(vim.g.statusline_winid or 0)
  local room = width - vim.fn.strdisplaywidth(right) - 3 -- 3 = 先頭の空白・アイコン・空白
  local left
  if info.repo then
    local repo = info.repo
    if vim.fn.strdisplaywidth(repo) > room then repo = repo:match("([^/]+)$") or repo end
    if vim.fn.strdisplaywidth(repo) > room then
      repo = vim.fn.strcharpart(repo, 0, math.max(room - 1, 1)) .. "…"
    end
    local icon = info.host and info.host:find("github") and "" or "󰊢"
    left = "%#TenvGitRepo# " .. icon .. " " .. esc(repo)
  else
    left = "%#TenvGitDim# 󰊢 リモートなし"
  end
  -- 全体をクリックできるようにする(Lazygit を開く)
  return "%@v:lua.TenvGitFooterClick@" .. left .. "%#TenvGitBar#%=%#" .. changes[1] .. "# " .. changes[2]
    .. (push and "%#TenvGitBar#  %#" .. push[1] .. "#" .. push[2] or "") .. "%#TenvGitBar# %X"
end

--- opts.on_click(リポジトリの根): フッターをクリックしたとき(Git 管理外では何もしない)
function M.setup(opts)
  opts = opts or {}
  _G.TenvGitFooterClick = function()
    if info.kind == "repo" and opts.on_click then opts.on_click(info.top) end
  end
  vim.o.laststatus = 2
  vim.o.statusline = "%!v:lua.require'tenv.gitfooter'.render()"
  -- 最初は画面が出てから調べる(起動を待たせない)
  request()
  local timer = vim.uv.new_timer()
  timer:start(INTERVAL, INTERVAL, vim.schedule_wrap(request))
  vim.api.nvim_create_autocmd({ "FocusGained", "DirChanged", "BufWritePost" }, { callback = request })
  -- neo-tree の監視の知らせ(.git の中の変化・ツリーの Git の状態の変化)
  local ok, events = pcall(require, "neo-tree.events")
  if ok then
    for _, ev in ipairs({ events.GIT_EVENT, events.GIT_STATUS_CHANGED }) do
      pcall(events.subscribe, { event = ev, id = "tenv_gitfooter_" .. ev, handler = request })
    end
  end
end

return M
