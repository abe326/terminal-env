# terminal-env

Windows の **WezTerm** と **Neovim(neo-tree)のツリー** を組み合わせて、VS Code のように作業するための設定一式です。
リモートの Linux 機(**tmux**)につないで使うこともできますが、**Windows だけでも使えます**。

- フォルダツリー。右クリックで「Windows アプリで開く」「エクスプローラー」「パスをコピー」「ファイル・文字列を探す」
- ファイルは右上段のエディタにタブで開く。Markdown は GitHub 風のプレビュー
- タブに Claude Code の状態(作業中 / 確認待ち / 完了)。確認待ちと完了は Windows の通知でも知らせる
- 前の作業を再開: 3 日以内の Claude Code の会話を一覧し、選んだものを場所ごとのタブで再開する。開いたまま閉じた会話は、WezTerm の起動時に知らせる
- ツリーの最下段に Git の状態(リモート先・未コミット数・未 push の有無)。クリックで Lazygit
- pane の分割・最大化を Shift+Alt 系のキーで。ローカルでも、ssh 先の tmux でも同じキー
- 見た目: UDEV Gothic、アクリルの半透明、丸いタブ、テーマ 4 種の切り替え

このリポジトリには **自作の設定ファイルだけ** が入っています。WezTerm・Neovim・フォント・プラグインなどは含まれていないので、下の手順でそれぞれの **公式の配布元** から入手してください(各ライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md))。

## 必要なもの

| 場所 | もの |
|---|---|
| Windows 10/11 | WezTerm、Neovim 0.12 以上、Git(Git Bash を含む)、ripgrep、lazygit(任意)、PowerShell 7(`pwsh`)、UDEV Gothic NF フォント |
| リモートの Linux 機(使う場合だけ) | tmux 3.3 以上、Neovim 0.10 以上、Git、ripgrep、lazygit(任意)、bash、coreutils(`base64` など)。Windows からは OpenSSH クライアント(Windows 標準)で鍵を使ってつなぐ |

## 導入(Windows)

### 1. ソフトを入れる(winget。どれも公式パッケージ)

```powershell
winget install --id wez.wezterm -e
winget install --id Neovim.Neovim -e
winget install --id BurntSushi.ripgrep.MSVC -e   # ファイル・文字列の検索
winget install --id JesseDuffield.lazygit -e     # Git の画面(任意)
winget install --id Git.Git -e                   # 入っていなければ
winget install --id Microsoft.PowerShell -e      # 入っていなければ
```

### 2. フォントを入れる

作者の公式リリース <https://github.com/yuru7/udev-gothic/releases> から `UDEVGothic_NF_v*.zip` をダウンロードし、
展開した中の `UDEVGothic35NF-*.ttf` を右クリック →「インストール」。

### 3. このリポジトリを置いて、設定を読ませる

```powershell
git clone https://github.com/abe326/terminal-env.git $HOME\terminal-env

# WezTerm にこのリポジトリの設定を読ませる
[Environment]::SetEnvironmentVariable('WEZTERM_CONFIG_FILE', "$HOME\terminal-env\wezterm\wezterm.lua", 'User')

# Neovim の設定フォルダをこのリポジトリにつなぐ(既に %LOCALAPPDATA%\nvim がある場合は先に退避する)
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\nvim" -Target "$HOME\terminal-env\nvim"

# 自分の環境の値を書く(下の「設定」を参照)
Copy-Item $HOME\terminal-env\wezterm\local.example.lua $HOME\terminal-env\wezterm\local.lua
notepad $HOME\terminal-env\wezterm\local.lua
```

### 4. プラグインを入れる

```powershell
nvim --headless +qa   # 初回の起動でプラグインが入る(lazy-lock.json の版)
```

プラグインは lazy.nvim が各プラグインの公式 GitHub リポジトリから取得します。
入る版は、このリポジトリの `nvim/lazy-lock.json` に書いた版(作者が動作を確かめた版)に固定されます。
新しい版にするときは、Neovim の中で `:Lazy update`(各自の判断で。更新内容を確かめてから)。

### 5. Claude Code の状態をタブに出す(Claude Code を使う場合)

`%USERPROFILE%\.claude\settings.json` の `hooks` に次を足します(既に `hooks` があれば、その中に足す)。
hook は Git Bash で動きます。パスは置いた場所に合わせてください。

```json
"hooks": {
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash \"C:/Users/<you>/terminal-env/bin/tenv-cc-state\" prompt", "async": true }] }],
  "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "bash \"C:/Users/<you>/terminal-env/bin/tenv-cc-state\" tool", "async": true }] }],
  "Notification":     [{ "matcher": "permission_prompt|elicitation_dialog",
                         "hooks": [{ "type": "command", "command": "bash \"C:/Users/<you>/terminal-env/bin/tenv-cc-state\" waiting", "async": true }] }],
  "Stop":             [{ "hooks": [{ "type": "command", "command": "bash \"C:/Users/<you>/terminal-env/bin/tenv-cc-state\" done", "async": true }] }],
  "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "bash \"C:/Users/<you>/terminal-env/bin/tenv-cc-state\" end", "async": true }] }]
}
```

## 導入(リモートの Linux 機。使う場合だけ)

### 1. Neovim・ripgrep・lazygit を入れる

Neovim はディストリビューションのパッケージが 0.10 以上ならそれで構いません。古い場合は公式リリースを使います
(<https://github.com/neovim/neovim/releases>)。チェックサムはリリースページの各ファイルに表示される sha256 と照合してください。

```bash
ver=v0.12.6   # 使う版
sum=...       # リリースページに出ている nvim-linux-x86_64.tar.gz の sha256
tmp=$(mktemp -d)   # 自分だけの作業場所(共用の /tmp に決まった名前で置かない)
curl -fLo "$tmp/nvim.tgz" https://github.com/neovim/neovim/releases/download/$ver/nvim-linux-x86_64.tar.gz
echo "$sum  $tmp/nvim.tgz" | sha256sum -c -   # 一致しなければ止める
mkdir -p ~/.local/nvim && tar xzf "$tmp/nvim.tgz" -C ~/.local/nvim --strip-components=1 && rm -rf "$tmp"
mkdir -p ~/.local/bin && ln -sf ~/.local/nvim/bin/nvim ~/.local/bin/nvim
```

ripgrep はディストリビューションのパッケージ(`sudo apt install ripgrep` など)で構いません。

Git の画面(Lazygit)を使う場合は lazygit も入れる(公式リリース <https://github.com/jesseduffield/lazygit/releases>。同じ場所の `checksums.txt` と照合)。

```bash
ver=0.66.2
cd "$(mktemp -d)" && curl -fLO https://github.com/jesseduffield/lazygit/releases/download/v$ver/lazygit_${ver}_linux_x86_64.tar.gz
curl -fsSL https://github.com/jesseduffield/lazygit/releases/download/v$ver/checksums.txt | grep " lazygit_${ver}_linux_x86_64.tar.gz$" | sha256sum -c -
tar xzf lazygit_${ver}_linux_x86_64.tar.gz lazygit && install -m755 lazygit ~/.local/bin/
```

### 2. このリポジトリを置いて、つなぐ

```bash
git clone https://github.com/abe326/terminal-env.git ~/terminal-env
ln -sfn ~/terminal-env/nvim ~/.config/nvim
ln -sf ~/terminal-env/bin/wopen ~/terminal-env/bin/tmux-tree ~/terminal-env/bin/tenv-open ~/terminal-env/bin/tenv-cc-state ~/.local/bin/
chmod +x ~/terminal-env/bin/*
echo 'source-file ~/terminal-env/tmux/terminal-env.conf' >> ~/.tmux.conf
tmux source-file ~/.tmux.conf 2>/dev/null || true
nvim --headless +qa   # 初回の起動でプラグインが入る(lazy-lock.json の版)
```

`~/.local/bin` が `PATH` に入っていない場合は追加してください。

### 3. Claude Code の状態をタブに出す(Claude Code を使う場合)

Windows と同じ hook を、リモートの `~/.claude/settings.json` に足します。コマンドは `~/.local/bin/tenv-cc-state prompt` のように書きます(`bash "…"` は不要)。

### 4. Windows 側の設定にリモートを足す

`local.lua` の `remotes` に、つなぐ先を書きます(下の「設定」)。

## 使い方

### 1 日の流れ

1. WezTerm を起動する(左にツリー、右にシェル)。前回 Claude Code を開いたまま閉じていれば、「前の作業」の画面が出る(下の「前の作業を再開」)
2. **Shift+Alt+O** でフォルダを選ぶ。一覧は接続先ごとに見出しが付き(リモート・この PC)、フォルダの横に **最後に Claude Code へ指示を出した日時** が出る
   - リモートのフォルダ: 新しいタブで ssh + tmux
   - この PC のフォルダ: 新しいタブで pwsh(**Shift+Alt+P** はこの PC のフォルダだけ)
3. 開いたタブは「左にツリー、右で Claude Code が起動」の並びになる
4. ツリーのファイルをダブルクリックで右上段のエディタに、右クリックで「アプリで開く」など。ツリーは **Shift+Alt+E** で出し入れできる
5. 作業を終えたら WezTerm を閉じてよい。**リモートは tmux の中で動き続ける**ので、次に同じフォルダを選ぶと、閉じたときの並びのまま戻る。この PC の Claude Code は閉じると止まるが、次の起動時に「前の作業」の画面から続きを開ける

```
┌─ツリー─┬──── エディタ(タブ)────┐
│ proj/   │ README.md  main.py       │
│  docs/  ├──────────────────────────┤
│  src/   │ Claude Code              │
├─Git────┤                          │
└────────┴──────────────────────────┘
```

### タブ

- タブ名は開いているフォルダ名(リモートは tmux のセッションを作ったフォルダ)。設定・操作一覧・Git・編集のタブは、その題名のまま
- **Claude Code の状態**: タブの中の全 pane のうち一番目立つものを、番号の横に出す(同じ状態が複数なら数も)

  | 印 | 状態 | 消えるとき |
  |---|---|---|
  | 時計 | 作業中 | 応答を終えたとき |
  | ベル(タブ全体がオレンジ) | 許可などの確認を求めている。Windows の通知も出る | 答えて作業に戻ったとき |
  | チェック | 応答を終えた。Windows の通知も出る | その pane を見たとき |

- タブの × で閉じるときは、毎回確認が出る。窓の × は、まとめて 1 回だけ確認して閉じる
- 右上: 接続先と、同期の状態(Mutagen を設定したとき。同期済 / 同期中 / 競合 / 同期エラー)
- タブバーの「＋」: 新しいタブ / フォルダを開く / 前の作業を再開 / タブを選ぶ を選ぶ
- **タブが多いとき**は、右上の表示と窓のボタンの場所を残して、タブが自動で縮みます
  - 縮む順: ほかのタブの題名を「…」で短くする → 選んでいるタブの題名も短くする → ほかのタブを番号と Claude Code の印だけにする
  - 確認待ちのタブはオレンジのままなので、縮んでも見落としません
  - 題名が読めないときは **Shift+Alt+L**(または「＋」→「タブを選ぶ」)で、タブの一覧から名前で探して移れます
  - WezTerm はタブ 1 つの幅を「窓の幅 ÷ (タブの数 + 1)」ほどに制限するため、タブが多いと、選んでいるタブも題名を出せません。幅 1,344px の窓では、14 個までなら右上の表示に重なりません

### 前の作業を再開(Claude Code)

**Shift+Alt+R** か、タブバーの **「＋」→「前の作業を再開」** で、3 日以内に使った Claude Code の会話を一覧します。接続先ごと(リモート・この PC)に見出しが付き、場所・題名(`/rename` で付けた名前 > 自動で付いた題名 > 最初の指示)・最後に使った日時が並びます。

- Space かクリックでチェックを付け外しし、Enter(または「再開する」)で開く。Esc で閉じる
- 場所(フォルダ)ごとにタブを 1 つ開き、左にツリー、右で `claude --resume <会話>` を動かす。同じ場所の会話を複数選ぶと、右の pane を分けて並べる
  - リモートでその場所の tmux のセッションが残っていれば、その中の空いているシェルの pane(無ければ右端を分けた pane)で再開する
- 右端の表示:

  | 表示 | 意味 | チェック |
  |---|---|---|
  | 前回開いていた | Claude Code を開いたまま、WezTerm の窓を閉じた・PC やリモートを再起動した | 最初から付く |
  | 動いています | リモートの tmux の中で動いていて、いま誰も見ていない | 起動時だけ最初から付く。選ぶと、そのセッションを開き直す(再開はしない) |
  | 開いています | リモートで動いていて、どこかの画面で見ている | 付かない。選ぶと、同じセッションをもう 1 つのタブで開く |
  | この PC で動作中 | この PC で動いている | 選べない |
  | (なし) | 終えた会話 | 付かない |

- **WezTerm を起動したとき**、「前回開いていた」会話か、リモートで動いていて誰も見ていない会話があれば、この画面が自動で出ます。無ければ何も出ません
- Claude Code を使わないなら、設定の `claude_resume = false` で止めます(キーと「＋」の項目も消える)。起動時に出さないだけなら `claude_resume_on_startup = false`

### キー

ssh でつないでいる pane では tmux に、ローカルの pane では WezTerm 自身の pane に効きます。

| キー | 動作 |
|---|---|
| Shift+Alt+- | 上下に分割 |
| Shift+Alt++ | 左右に分割 |
| Shift+Alt+W | pane を閉じる(確認あり) |
| Shift+Alt+Z | pane の最大化 / 戻す |
| Shift+Alt+矢印 | pane の大きさ |
| Shift+Alt+E | ツリーを出す / ツリーへ移る / ツリーにいれば閉じる |
| Shift+Alt+O | フォルダを選んで開く(リモートとこの PC) |
| Shift+Alt+P | この PC のフォルダを選んで開く |
| Shift+Alt+N | 新しいタブ |
| Shift+Alt+R | 前の作業を再開(Claude Code) |
| Shift+Alt+T | テーマ切り替え(Tokyo Night → Catppuccin Mocha → Kanagawa → Rosé Pine) |
| Shift+Alt+K | コマンドパレット |
| Shift+Alt+L | タブを選ぶ(一覧から名前で探して移る。タブが多くて題名が縮んだとき) |
| Shift+Alt+S | リモートの最下段のステータス行を出す / 隠す(既定は隠す) |
| Ctrl+C | 選択中ならコピー(エディタでも)、無ければ中断。ドラッグで選んだ範囲は、離したときにもコピーされる |
| Ctrl+V | 貼り付け(どこでも。Claude Code への画像は Alt+V) |
| 右クリック(リモートのシェル) | 範囲選択中ならコピー。tmux の英語メニューは出さない(Alt+右クリックで出せる) |
| Shift+Enter / Alt+Enter | Claude Code の改行(Alt+Enter は WezTerm 標準の全画面切り替えの代わり) |

### ツリー

| 操作 | 動作 |
|---|---|
| ダブルクリック / Enter | フォルダは開閉、ファイルは右上段のエディタにタブで開く |
| 右クリック / M | メニュー: アプリで開く / エクスプローラー / パスをコピー / ファイルを探す / 文字列を探す / 設定 / 更新 / 操作一覧。ボタンを離したときに開き、マウスを乗せた項目が光る。外をクリックか Esc で閉じる。開いたまま別の行を右クリックすると、その行のメニューに開き直す |
| Ctrl+P / Ctrl+F | ファイル名で探す / 文字列で探す(開いているフォルダの中。右上段のエディタの中に検索の画面が出る。右上の ×・画面の外のクリック・Esc で閉じる) |
| 最下段の Git の表示をクリック | Lazygit を新しいタブで開く |
| ファイルをドロップ | エクスプローラーからツリーへドロップすると「配置先を選ぶ」状態になる。クリックしたフォルダが配置先になり、開く / 閉じる(中のフォルダも選べる。キーでは j / k で移って Space / l / → で開閉、h / ← で閉じる)。配置先とその中身が光る。**Enter で配置、Esc でやめる**(上の「配置」「やめる」もクリックできる)。同じ名前があれば確認が出る。リモートへは scp で送る(WezTerm の確認が出る) |
| O / E / Y / g | アプリで開く / エクスプローラーで表示 / パスをコピー / Git(Lazygit) |
| a / A / r / d | 新しいファイル / 新しいフォルダ / 名前変更 / 削除 |
| R / ? | 更新 / 操作一覧(別の窓で開く) |
| q | ツリーを閉じる |

ドロップの配置先: ふだんから、カーソルのある行のフォルダ(ファイルの行ならその親)に「配置先」の印を出す。
WezTerm はドラッグ中のマウスの位置をアプリに渡さない(ドロップした瞬間にファイルの一覧が届くだけ)ため、配置先はドロップした後に選ぶ形にしている。
ドロップは、選んでいる pane に届く。先にツリーを一度クリックしてからドロップする。

ツリーの確認・入力・お知らせは、すべてツリーの下(最下段の Git の表示のすぐ上)にツリーの幅で出る。
- 確認(削除・同じ名前・注意・エラー): Enter で決定、Esc でやめる。← → でボタンを選び直す / クリックでも選べる
- 入力(新しいファイル・名前の変更・複製・移動): Enter で決定、Esc でやめる
- お知らせ(配置した・パスをコピーした・削除したなど): 数秒だけ出て消える
- リモートへファイルを送るときだけは、WezTerm 自身が確認を出す(端末に流れた文字列で送信を偽装されないように)
- 範囲を選んで(V)d で、まとめて削除できる

ツリーの最上位のフォルダ(開いたフォルダ)は動かない(Backspace の「一つ上へ」と . の「ここを最上位に」は止めてある)。

ツリーの最下段には Git の状態を出す: リモート先(owner/repo。無ければ「リモートなし」)・未コミットのファイル数・未 push のコミットの有無(数秒ごとに更新)。
ファイルの横の文字は VS Code と同じ(M 変更 / U 新規 / A 追加 / D 削除 / R 名前変更 / ! 衝突)。

ツリーの幅は、開くときは `tree_width`(既定 34 桁)。`tree_width_fixed = true`(既定)なら、窓の大きさを変えても幅を保つ。
境目をドラッグして変えた幅も保ち、開き直すと `tree_width` に戻る。`false` にすると窓の大きさに合わせて伸び縮みする。

### エディタ(右上段)

ツリーから開いたファイルは、右側の pane の上に作るエディタに、タブで並ぶ(VS Code のエディタと同じ)。

| 操作 | 動作 |
|---|---|
| タブをクリック / H / L | 切り替え / 前 / 次のタブ |
| タブの × / 中クリック / Space x | 閉じる(未保存は ●。閉じるときに確認)。最後のタブを閉じるとエディタの pane ごと閉じる |
| 「プレビュー / 原文」/ Space v | Markdown の表示を切り替える(md は GitHub 風のプレビューで開く。編集を始めると原文になる) |
| Ctrl+P / Ctrl+F | ファイル名で探す / 文字列で探す(ツリーで開いているフォルダの中) |

リモートのシェルからも `wopen <ファイル>`(Windows アプリで開く)、`wopen -r <ファイル>`(エクスプローラーで表示)が使えます。

## 設定(`wezterm/local.lua`)

ツリーの右クリック →「設定」で開きます。保存するとすぐ反映されます(窓の大きさだけは次の起動から)。
書き方の見本と各項目の説明は [`wezterm/local.example.lua`](wezterm/local.example.lua) にあります。設定は 4 つのまとまりです。

### 基本(Windows だけで使う場合は、ここだけ)

| 項目 | 既定 | 内容 |
|---|---|---|
| `local_projects_root` | ホーム | Shift+Alt+P / O で一覧するフォルダ(この直下を選べる)。複数なら `{ [[C:\a]], [[D:\b]] }` |
| `start_command` | `"claude"` | フォルダを開いたとき右の pane で起動するコマンド。`false` ならシェルのまま |
| `open_with_tree` | `true` | フォルダを開いたとき左にツリーを出すか |
| `tree_on_startup` | `true` | WezTerm を起動した最初の画面にもツリーを出すか |
| `tree_width` | `34` | ツリーの幅(桁)。開くときはいつもこの幅 |
| `tree_width_fixed` | `true` | 窓の大きさを変えてもツリーの幅を保つか(上の「ツリー」を参照) |

### 前の作業を再開(Claude Code を使う場合)

| 項目 | 既定 | 内容 |
|---|---|---|
| `claude_resume` | `true` | 前の作業を再開を使うか。`false` なら Shift+Alt+R と「＋」の項目も消える |
| `claude_resume_on_startup` | `true` | WezTerm を起動したとき、前回開いていた作業があれば再開の画面を出すか |
| `claude_resume_days` | `3` | 一覧に出す会話(この日数以内に使ったもの) |

### リモート(`remotes`。使わないなら書かない)

ssh でつなぐ Linux 機を、1 台ずつ `{ ... }` で書きます。複数台を書くと、Shift+Alt+O の一覧に接続先ごとの見出しが付きます。

```lua
remotes = {
  {
    name = "myserver",               -- 表示名(右上・一覧の見出し)
    host = "myserver",               -- ~/.ssh/config の Host 名
    projects_root = "~/work",        -- 一覧するフォルダ。複数なら { "~/work", "/srv/projects" }
    path_map = { { "/home/<you>/work", [[\\myserver\work]] } },  -- リモートのパス → Windows のパス
    -- fallback_root = "X:",         -- 対応表に無いパスにも付ける前置
    -- open_allowed = { "/home/<you>/" }, -- 開く合図を受け付けるパス(省略時は path_map のリモート側)
    -- open_command = function(remote_path, windows_path) return { ... } end,  -- 開く処理の差し替え
    -- attach_with = "~/bin/my-attach", -- attach を自分のスクリプトに任せる
    -- mutagen = { "work" },         -- Mutagen のセッション名。右上に同期の状態が出る
  },
},
```

リモートのファイルを Windows のアプリで開くには、**同じファイルが Windows からも見える経路**(Samba 共有・同期ツール・ネットワークドライブなど)が必要です。対応関係を `path_map` に書きます。

### 見た目

| 項目 | 既定 | 内容 |
|---|---|---|
| `window_scale` | `0.7` | 起動した窓の大きさ(画面に対する割合。中央に置く)。`nil` なら WezTerm の既定 |
| `default_theme` / `opacity` | `1` / `0.9` | テーマ(Shift+Alt+T でも切り替え)/ 背景の不透明度 |
| `font_family` / `font_size` | UDEV Gothic 35NF / `12.5` | 本文(ターミナル・ツリー)の文字 |
| `tab_font_size` / `palette_font_size` | `10.5` / `13` | タブと右上 / コマンドパレット・選択画面の文字の大きさ |
| `line_height` | `1.08` | 行の高さ |
| `colors` | なし | 本文の配色(文字・背景・カーソル・選択範囲・16 色)。テーマの上に重ねる |
| `theme_colors` | なし | タブや右上の配色(選択中のタブ・リモートのタブ・確認待ちなど) |

## ファイル

| ファイル | 役割 |
|---|---|
| `wezterm/wezterm.lua` | WezTerm の設定(見た目・キー・タブ・通知・開く合図の受け口) |
| `wezterm/local.example.lua` | 環境ごとの値の見本(`local.lua` にコピーして使う) |
| `nvim/init.lua` | Neovim の設定(Windows と Linux で共用)。ツリー専用 pane は `NVIM_TREE_ONLY=1` で起動 |
| `nvim/keys.md` | 操作一覧(ツリーの ? で開く) |
| `nvim/lua/tenv/menu.lua` | 右クリックメニュー |
| `nvim/lua/tenv/gitfooter.lua` | ツリーの最下段の Git の状態 |
| `nvim/lua/tenv/editor.lua` | ツリーから開くファイル・検索を右上段のエディタへ渡す |
| `nvim/lua/tenv/dialog.lua` | ツリーの下に出す確認・入力・お知らせ |
| `nvim/lua/tenv/drop.lua` | ドラッグ&ドロップの配置先(印・ドロップ後に選ぶ) |
| `nvim/lua/tenv/picker.lua` | ファイル名・文字列の検索(telescope.nvim + ripgrep) |
| `nvim/lua/tenv/tabs.lua` | エディタのタブ |
| `nvim/lua/tenv/markdown.lua` | Markdown のプレビュー(GitHub 風の配色・切り替え) |
| `nvim/lua/tenv/resume.lua` | 前の作業を再開の画面(この PC とリモートの会話を並べ、選んだものを WezTerm へ渡す) |
| `nvim/lua/tenv/ccsessions.lua` | Claude Code の会話の一覧を作る(リモートでは ssh 越しに `nvim -l` で動かす) |
| `tmux/terminal-env.conf` | tmux の設定(`source-file` で読み込む) |
| `bin/tenv-open` | Shift+Alt+O の本体(リモートでセッションを用意して attach)。`-r <会話>` で、その中で Claude Code の会話を再開する |
| `bin/tmux-tree` | tmux の Shift+Alt+E の本体。ツリーの幅を保つ。WezTerm からつないだとき、設定が変わる前に起動したツリーを作り直す(tmux のセッションは残るため) |
| `bin/wopen` | リモート → WezTerm へ合図を送る(開く・表示・編集・Git・設定・操作一覧・ファイルの配置) |
| `bin/tenv-cc-state` | Claude Code の hook から状態を WezTerm のタブへ伝える。指示を出した日時も残す |

## 仕組み

- リモートの `wopen` が端末へ `OSC 1337 SetUserVar=wez_open` を送り(tmux は passthrough で通す)、WezTerm がそれを受けて
  `path_map` で Windows のパスに直し、Windows の既定のアプリで開きます。新しいポートや Windows 側の SSH サーバーは要りません。
  合図には合言葉が付き、WezTerm は合わないものを捨てます(下の「安全のために」)
- Claude Code の状態は、リモートでは tmux の pane に残し、セッション全体で一番目立つ状態を `SetUserVar=tenv_cc` で WezTerm に送ります。
  ローカルでは `%LOCALAPPDATA%\tenv\cc\` のファイルを WezTerm が 1 秒ごとに読みます
- 指示を出した日時は、リモートは `~/.local/state/tenv/last-prompt/`、ローカルは `%LOCALAPPDATA%\tenv\last-prompt\` に残ります(hook を入れた後の分から)
- 前の作業を再開の一覧は、Claude Code が `~/.claude/` に残すファイルから読みます(`projects/` の会話の記録と、`sessions/` の動いている会話の記録)。動いている記録が残ったまま Claude Code のプログラムが無くなっていれば「前回開いていた」とします。
  どちらも Claude Code の公開された仕組みではないため、Claude Code の版が変わると、一覧や表示が変わることがあります
- tmux の色は端末の 16 色で指定しているので、WezTerm のテーマを替えると tmux も追従します

## 安全のために

リモートからの合図(開く・送る・Claude Code の状態)は、端末に流れる文字列で届きます。リモートで表示したファイルの中身・ログ・AI の出力などにも同じ合図を仕込めるため、次の守りを入れています。

**合図の確認**
- 合言葉: WezTerm が初回にこの PC の `%LOCALAPPDATA%\tenv\token` を作り、リモートでフォルダを開くとき(Shift+Alt+O)に、リモートの自分だけが読めるファイル `~/.local/state/tenv/tokens` に書きます。本物の `wopen` / `tenv-cc-state` は合言葉を付けて合図を送り、WezTerm は合言葉の合わない合図を捨てます。端末に流れただけの文字列は合言葉を知りません
  - 合言葉はリモートのファイルに残るので、tmux やリモートを再起動しても使えます。tmux の外(ssh だけ)で `wopen` を使っても使えます
  - 複数の PC から同じリモートにつなぐ場合も、PC ごとの合言葉が並んで残る(5 台まで)ので、それぞれの PC で使えます
  - 「合言葉の無い合図を無視しました」と出たら、そのリモートを一度 Shift+Alt+O で開き直してください(合言葉がまだ渡っていない)
- 受け付けるのは `open_allowed`(省略時は `path_map` のリモート側)の下のパスだけ。`..` を含むパスは捨てます

**開く(「アプリで開く」・端末のリンク)**
- 実行形式(exe・bat・ps1・lnk など、Windows で開く = 実行になる種類)は開きません。中を見るならツリーのダブルクリック(エディタ)、場所を見るなら「エクスプローラー」
- スクリプト(py・sh など)とマクロ付きの Office(xlsm・docm など)は、開く前に確認を出します(最初に選ばれているのは「やめる」)。入っているアプリによっては実行されたり、マクロが動いたりするため
- それ以外(文書・画像・データ・ソースコードなど)は、そのまま開きます
- Windows で別の意味になる文字(`: " < > | ? * \` や制御文字)や、名前の末尾の `.` や空白(Windows が落とすため、拡張子の確認をすり抜けられる)を含む名前は、Windows では開けません。ツリーのダブルクリック(エディタ)なら開けます
- 端末の中のリンクは、http / https / mailto と、この PC のファイル(`file:`。上と同じ扱い)を開きます。それ以外の種類(Windows でプログラムを動かせるもの)は開きません

**送る(ドラッグ&ドロップ)**
- 送る前に必ず確認を出し、送るファイルを手元の場所ごと並べます。送っている間は下に小さな画面が出て、終わると「配置しました」と知らせます
- 鍵や認証の情報の置き場所(`.ssh`・`.gnupg`・`.aws`・`.azure`・`.kube`・`.docker`・Windows の資格情報・この仕組みの合言葉)からは送りません

**そのほか**
- 開いたフォルダの `.git/config` に書かれたコマンド(`core.fsmonitor`)は、ツリー・エディタ・Lazygit から動かしません。リモートでファイルを編集するときは、ファイルの中の vim の設定の行(modeline)を読みません
  - Git の速くする仕組み(fsmonitor)を使っている大きなリポジトリでは、ツリーの Git の表示が少し遅くなることがあります
- Windows では、ツリーとエディタから起動するもの(git・rg など)について、開いたフォルダに置かれた同じ名前のプログラムを、本物の代わりに動かしません(今のフォルダを探さない設定。pane のシェルには影響しません)
- エディタとの連絡口は、Linux では自分だけが使えるフォルダ、Windows では推測できない名前にします
- Neovim のプラグインは `nvim/lazy-lock.json` の版で入ります(勝手に新しい版にはなりません)
- リモートのシェルで右クリックしても、Windows のクリップボードは貼り付けません

**使う人が気をつけること**
- このフォルダ(`wezterm/`・`nvim/`・`bin/`)は、設定であると同時に**動くプログラム**です。リモートや同期ツールから書き換えられる場所に置くと、そこを乗っ取られたときに Windows でも動いてしまいます。Windows で使うものは、Windows だけが書き込める場所に置いてください
- `local.lua` の `open_command` に自分のスクリプトを書く場合、渡されるパスはリモート由来です。`Invoke-Expression` などで命令として扱わないでください
- 端末に流れた文字列は、クリップボードに書き込むこともできます(OSC 52。WezTerm と tmux の標準の機能)。リモートで信用できないものを表示した後は、貼り付ける前に中身を確かめてください

## 外す

- Windows: 環境変数 `WEZTERM_CONFIG_FILE` を消し、`%LOCALAPPDATA%\nvim` のジャンクションを消す。`settings.json` の `tenv-cc-state` の hook を消す
- Linux: `~/.tmux.conf` の `source-file` の行を消し、`~/.config/nvim` と `~/.local/bin/{wopen,tmux-tree,tenv-open,tenv-cc-state}` のリンクを消す。`settings.json` の hook を消す

## ライセンス

このリポジトリの設定ファイルは [MIT License](LICENSE)。
入手して使うソフト・フォント・プラグインのライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください(このリポジトリには同梱していません)。
