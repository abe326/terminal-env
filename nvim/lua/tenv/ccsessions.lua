-- Claude Code の会話(セッション)の一覧を作る。「前の作業を再開」(tenv/resume.lua)が使う
--   nvim --clean --headless -l ccsessions.lua <日数>   → 標準出力に JSON(リモートでは ssh 越しにこの形で呼ぶ)
--   require("tenv.ccsessions").list(<日数>)            → 表(この PC の分)
--
-- 一覧に入れるもの: <日数> 以内に使った、対話の会話(claude -p などは入れない)
--   ・running   : いま動いている(Claude Code が ~/.claude/sessions/<pid>.json に残す、動いている会話の記録)
--   ・was_open  : 動いている記録が残ったまま、そのプログラムが無くなった(WezTerm の窓を閉じた・機械を再起動した)
--                 = 前回開いていた作業。最初からチェックを付ける
--   ・tmux / attached : リモートで、その会話が動いている tmux のセッションと、いま誰かが見ているか
-- 題名は「/rename で付けた名前 > 自動で付いた題名 > 最初の指示」の順に使う
local MODNAME = ... -- require で読まれたときは "tenv.ccsessions"、nvim -l で動かしたときは引数
local M = {}

local uv = vim.uv or vim.loop
local is_win = vim.fn.has("win32") == 1

local function home()
  return vim.env.CLAUDE_CONFIG_DIR or ((is_win and vim.env.USERPROFILE or vim.env.HOME) .. "/.claude")
end

local function read_head(path, bytes)
  local f = io.open(path, "rb")
  if not f then return "" end
  local s = f:read(bytes) or ""
  f:close()
  return s
end

local function read_tail(path, bytes)
  local f = io.open(path, "rb")
  if not f then return "" end
  local size = f:seek("end")
  f:seek("set", math.max(size - bytes, 0))
  local s = f:read("*a") or ""
  f:close()
  return s
end

local function alive(pid)
  if not pid then return false end
  local ok, r = pcall(uv.kill, pid, 0)
  return ok and r == 0
end

-- 動いている会話の記録(~/.claude/sessions/*.json)
local function registry(since)
  local running, was_open = {}, {}
  local dir = home() .. "/sessions"
  local h = uv.fs_scandir(dir)
  while h do
    local name = uv.fs_scandir_next(h)
    if not name then break end
    if name:match("^%d+%.json$") then
      local ok, d = pcall(vim.json.decode, read_head(dir .. "/" .. name, 65536))
      if ok and type(d) == "table" and d.kind == "interactive" and type(d.sessionId) == "string" then
        local at = math.floor((tonumber(d.updatedAt) or 0) / 1000)
        if alive(d.pid) then
          running[d.sessionId] = { tmux = type(d.tmux) == "string" and d.tmux:match("^(.-):@") or nil,
            cwd = type(d.cwd) == "string" and d.cwd or nil, at = at }
        elseif at >= since then
          -- 同じ会話の記録が複数残っていたら新しい方(後で再開して、また閉じた場合)
          was_open[d.sessionId] = math.max(was_open[d.sessionId] or 0, at)
        end
      end
    end
  end
  return running, was_open
end

-- 会話の記録(jsonl)から、場所・対話かどうか・最初の指示・題名を読む
local function describe(path)
  local cwd, first, cli
  for line in read_head(path, 262144):gmatch("[^\n]+") do
    if line:find('"type":"user"', 1, true) then
      local ok, o = pcall(vim.json.decode, line)
      if ok and type(o) == "table" and not o.isSidechain then
        cli = cli or o.entrypoint
        cwd = cwd or o.cwd
        if not o.isMeta and first == nil then
          local c = o.message and o.message.content
          if type(c) == "table" then
            for _, b in ipairs(c) do
              if type(b) == "table" and b.type == "text" then c = b.text break end
            end
          end
          -- コマンドの出力(<command-name> など)は指示ではないので飛ばす
          if type(c) == "string" and not c:match("^%s*<") and c:match("%S") then first = c end
        end
        if cwd and first and cli then break end
      end
    end
  end
  if cli ~= "cli" or not cwd then return nil end
  local title
  local text = read_head(path, 262144) .. "\n" .. read_tail(path, 524288)
  for v in text:gmatch('"type":"custom%-title","customTitle":"(.-)","sessionId"') do title = v end
  if not title then
    for v in text:gmatch('"type":"ai%-title","aiTitle":"(.-)","sessionId"') do title = v end
  end
  if title then
    local ok, v = pcall(vim.json.decode, '"' .. title .. '"') -- JSON の書き方(\" や \uXXXX)を戻す
    title = ok and v or title
  end
  local function oneline(s) return s and vim.trim((s:gsub("%s+", " "))) or nil end
  return { cwd = cwd, first = oneline(first), title = oneline(title) }
end

--- days 日以内の会話の一覧(新しい順)
function M.list(days)
  local now = os.time()
  local since = now - (tonumber(days) or 3) * 86400
  local running, was_open = registry(since)
  local out = {}
  local root = home() .. "/projects"
  local ph = uv.fs_scandir(root)
  while ph do
    local proj, t = uv.fs_scandir_next(ph)
    if not proj then break end
    if t == "directory" then
      local fh = uv.fs_scandir(root .. "/" .. proj)
      while fh do
        local name = uv.fs_scandir_next(fh)
        if not name then break end
        local id = name:match("^([%x%-]+)%.jsonl$")
        if id then
          local path = root .. "/" .. proj .. "/" .. name
          local st = uv.fs_stat(path)
          if st and st.mtime.sec >= since then
            local d = describe(path)
            if d then
              d.id, d.mtime = id, st.mtime.sec
              d.running = running[id] ~= nil
              d.tmux = running[id] and running[id].tmux or nil
              -- 動いている記録が残ったまま止まった会話。ただし、その後に再開して使い、ふつうに閉じた場合
              -- (記録より会話の方が 10 分以上新しい)は、前回開いていたものではない
              d.was_open = not d.running and was_open[id] ~= nil and d.mtime - was_open[id] < 600
              table.insert(out, d)
            end
          end
        end
      end
    end
  end
  -- 動いているが、まだ何も指示していない会話(記録が無い)も入れる(開き直すだけ。再開するものは無い)
  local seen = {}
  for _, d in ipairs(out) do seen[d.id] = true end
  for id, r in pairs(running) do
    if not seen[id] and r.cwd and r.at >= since then
      table.insert(out, { id = id, cwd = r.cwd, mtime = r.at > 0 and r.at or now, running = true, tmux = r.tmux,
        empty = true })
    end
  end
  -- リモートでは、tmux のセッションをいま誰かが見ているか(見ていれば、その画面は開いている)
  if not is_win and vim.fn.executable("tmux") == 1 then
    -- (同じ窓を共有するグループのセッション(〜2 など)で見ている場合も、見ていることにする)
    local r = vim.system({ "tmux", "list-sessions", "-F",
      "#{session_name}\t#{?session_grouped,#{session_group_attached},#{session_attached}}" }, { text = true }):wait()
    local att = {}
    for line in (r.stdout or ""):gmatch("[^\n]+") do
      local n, a = line:match("^(.*)\t(%d+)$")
      if n then att[n] = tonumber(a) > 0 end
    end
    for _, d in ipairs(out) do
      if d.tmux then d.attached = att[d.tmux] == true end
    end
  end
  table.sort(out, function(a, b) return a.mtime > b.mtime end)
  return out
end

-- nvim -l で呼ばれたとき(リモート)は JSON を出す
if MODNAME ~= "tenv.ccsessions" then
  io.write(vim.json.encode(M.list(_G.arg and _G.arg[1])))
end

return M
