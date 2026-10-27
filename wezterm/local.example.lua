-- local.lua の見本。このファイルを同じフォルダに local.lua という名前でコピーして使う(導入スクリプトが写す)。
-- 値の行はすべてコメント(先頭が --)なので、写したままでも既定値で動く。変えたい行だけ、先頭の -- を外して書き換える。
-- 使わない項目も、例はコメントのまま残しておく(消さない)。後から使うときに -- を外して書き換えるだけで済む。
-- 書かなかった項目は wezterm.lua の既定値になる。local.lua は配布物に含めない(.gitignore 済み)。
-- 保存するとすぐ反映される(窓の大きさだけは次の起動から)。
return {
  ----------------------------------------------------------------
  -- 基本(Windows だけで使う場合は、ここだけ見ればよい)
  ----------------------------------------------------------------
  -- Shift+Alt+P(と O)で一覧するフォルダ。この直下のフォルダを選べる。複数なら { [[C:\a]], [[D:\b]] }
  -- 起動した最初の窓もここ(複数なら先頭)で開く。省略時はホーム
  -- local_projects_root = [[C:\Users\<you>\work]],
  -- この PC の pane のシェル(省略時は pwsh.exe が PATH にあればそれ、無ければ Windows 標準の powershell.exe)
  -- shell = "powershell.exe",
  -- フォルダを開いたとき右の pane で起動するコマンド(省略時 "claude")。シェルのまま開くなら false
  -- start_command = "claude",
  -- フォルダを開いたとき左にツリーを出すか(省略時 true)
  -- open_with_tree = true,
  -- WezTerm を起動した最初の画面(起動時の画面を何も開かずに閉じたとき・出さないとき)にもツリーを出すか(省略時 true)
  -- tree_on_startup = true,
  -- WezTerm を起動したとき、フォルダを開く一覧(Shift+Alt+O と同じ)を出すか(省略時 true)
  --   「前の作業」の画面のタブ 1 つで窓を始め、前回開いていた作業があれば再開の一覧を先に出す(Tab で切り替え)
  -- open_on_startup = true,
  -- ツリーの幅(桁数)。開くときはいつもこの幅(省略時 34)
  -- tree_width = 34,
  -- ツリーの幅を固定するか(省略時 true)
  --   true : 窓の大きさを変えても幅を保つ。境目をドラッグして変えた幅も保ち、開き直すと tree_width に戻る
  --   false: 窓の大きさに合わせて伸び縮みする
  -- tree_width_fixed = true,

  ----------------------------------------------------------------
  -- 前の作業を再開(Claude Code を使う場合だけ。Shift+Alt+R・タブバーの「＋」)
  --   3 日以内の会話を一覧し、選んだものを場所ごとのタブで再開する
  ----------------------------------------------------------------
  -- 使うか(省略時 true)。Claude Code を使わないなら false(キーと「＋」の項目も消える)
  -- claude_resume = true,
  -- WezTerm を起動したとき、前回開いたまま閉じた作業があれば、再開の画面を出すか(省略時 true)
  -- claude_resume_on_startup = true,
  -- 一覧に出す会話: この日数以内に使ったもの(省略時 3)
  -- claude_resume_days = 3,

  ----------------------------------------------------------------
  -- 見た目
  ----------------------------------------------------------------
  -- window_scale = 0.7,  -- 起動した窓の大きさ(画面に対する割合)。nil なら WezTerm の既定
  -- default_theme = 1,   -- 1 Tokyo Night / 2 Catppuccin Mocha / 3 Kanagawa / 4 Rosé Pine(Shift+Alt+T でも切り替え)
  -- opacity = 0.9,       -- 背景の不透明度(1.0 で透けない)

  -- 文字
  -- font_family = "UDEV Gothic 35NF",
  -- font_size = 12.5,       -- 本文(ターミナル・ツリー)
  -- tab_font_size = 10.5,   -- タブと右上の表示
  -- palette_font_size = 13, -- コマンドパレット・選択画面
  -- line_height = 1.08,     -- 行の高さ

  -- 文字の配色(テーマの上に重ねる。書いた項目だけ変わる)
  -- colors = {
  --   foreground = "#e0e0e0",       -- 本文の文字
  --   background = "#101018",       -- 本文の背景
  --   cursor_bg = "#ffcc66",        -- カーソル
  --   selection_bg = "#334466",     -- 選択範囲
  --   -- ansi / brights: 端末の 16 色(黒・赤・緑・黄・青・紫・水色・白)。tmux の色もこれに従う
  --   -- ansi = { "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6" },
  --   -- brights = { "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5" },
  -- },
  -- theme_colors = {
  --   bg = "#1a1b26",       -- 窓の背景(左上から右下へのグラデーションの始まり)
  --   bg2 = "#1f2335",      -- 窓の背景(グラデーションの終わり)
  --   accent = "#7aa2f7",   -- 選んでいるタブ・ローカルの表示
  --   accent2 = "#bb9af7",  -- リモートのタブ・表示
  --   bar = "#13141c",      -- タブバーの背景
  --   surface = "#292e42",  -- 選んでいないタブ・pane の境目
  --   fg = "#c0caf5",       -- タブバーの文字
  --   dim = "#565f89",      -- 控えめな文字
  --   ok = "#9ece6a",       -- 完了・同期済み
  --   warn = "#ff9e64",     -- 確認待ち・同期の問題
  -- },

  ----------------------------------------------------------------
  -- リモート(ssh でつなぐ Linux 機)。使う場合だけ
  --   ・使うときは、すぐ下の --[=[ の 1 行を消して、つなぐ先の値に書き換える
  --   ・Shift+Alt+O の一覧に、リモートごとの見出しを付けて並ぶ
  --   ・リモートの pane では、右クリックの「アプリで開く」などが手元の Windows で開く
  --   ・リモート側の準備(tmux・nvim・bin/ の 4 本)は README の「導入(リモートの Linux 機。使う場合だけ)」
  ----------------------------------------------------------------
  --[=[
  remotes = {
    {
      -- 表示名(右上・一覧の見出し)
      name = "myserver",
      -- ssh の接続先(~/.ssh/config の Host 名。鍵で入れるようにしておく)
      host = "myserver",
      -- Shift+Alt+O で一覧するフォルダ(この直下のフォルダを選べる)。複数なら { "~/work", "/srv/projects" }
      projects_root = "~/work",

      -- リモートのパス → Windows のパス。同じファイルが Windows から見える経路(Samba・同期ツールなど)を書く。
      -- 右クリックの「アプリで開く」「エクスプローラー」は、ここで Windows のパスに直して開く
      path_map = {
        { "/home/<you>/work", [[\\myserver\work]] },
      },
      -- 対応表に無いパスでも、この前置を付けて開く(リモートのルートをドライブとしてマウントしている場合など)
      -- fallback_root = "X:",
      -- 開く合図を受け付けるリモートのパス(前方一致)。省略時は path_map のリモート側だけ
      -- open_allowed = { "/home/<you>/" },
      -- 開く処理を自分のスクリプトに差し替える(省略時は explorer.exe で既定のアプリが開く)
      -- open_command = function(remote_path, windows_path)
      --   return { "powershell.exe", "-NoProfile", "-File", [[C:\tools\open.ps1]], remote_path }
      -- end,

      -- attach を自分のスクリプトに任せる(<コマンド> <dir> の形で呼ばれる。省略時は tmux attach)
      -- attach_with = "~/bin/my-attach",
      -- Mutagen で同期しているなら、そのセッション名(mutagen sync list の Name)。右上に同期の状態が出る
      -- mutagen = { "work" },
    },
    -- 2 台目以降も同じ形で足す
    -- { name = "gpu", host = "gpu-box", projects_root = "~/src" },
  },
  --]=]
}
