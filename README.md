# terminal-env

Windows の **WezTerm** と **Neovim(neo-tree)のツリー** を組み合わせて、VS Code のように作業するための設定一式です。
**Windows だけで使えます。** ssh でつなぐ Linux 機(**tmux**)は、使う場合だけ足します。

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
| Windows 10/11 | WezTerm、Neovim 0.12 以上、Git(Git Bash を含む)、ripgrep、lazygit(任意)、UDEV Gothic NF フォント。**管理者権限は要りません**(すべて自分のユーザーだけに入れます)。シェルは PowerShell 7(`pwsh`)があればそれを、無ければ Windows に最初から入っている PowerShell 5.1 を使います |
| リモートの Linux 機(使う場合だけ) | tmux 3.3 以上、Neovim 0.10 以上、Git、ripgrep、lazygit(任意)、bash、coreutils(`base64` など)。Windows からは OpenSSH クライアント(Windows 標準)で鍵を使ってつなぐ |

## Claude Code に導入を任せる場合

Windows で(リモートの Linux 機も使うなら、そちらでも)Claude Code を開き、「terminal-env の README の導入を進めて」と頼めば、この README を読んで進められるように書いてあります。Claude Code に守ってほしいこと:

1. **先に利用者に聞く**(推測で埋めない)
   - Windows だけで使うか、ssh でつなぐ Linux 機も使うか。Windows だけなら、下のリモートの項目は聞かず、Linux 側の導入も飛ばす
   - Shift+Alt+P で一覧するこの PC のフォルダ(`local_projects_root`。書かなければホーム)
   - フォルダを開いたときに起動するコマンド(既定は `claude`)
   - リモートを使うなら: 表示名・`~/.ssh/config` の Host 名(鍵で入れること)・一覧するフォルダ・Windows から同じファイルが見える経路(`path_map`)
2. **実行前に利用者の承認を取る**: `~/.claude/settings.json` の書き換え(控えを取り、既にある `hooks` に足す。置き換えない)・`~/.tmux.conf` の書き換え・既にある Neovim の設定の退避
3. **管理者権限を使わない。** `sudo` や昇格が要る手順になったら、止めて利用者に聞く
4. **自分の環境の値は `wezterm/local.lua`(Git 管理外)にだけ書く。** このリポジトリのファイルは書き換えない(`git pull` で更新できなくなる)
   - `local.lua` はスクリプトが見本から作ったものを直す。使う項目だけ先頭の `--` を外して値を書き、**使わない項目(リモートなど)の例はコメントのまま残す**(後から使うときに外すだけで済むように)。作り直したり、例を消したりしない
5. **自分の機械だけを触る。** Windows の Claude Code は Windows、Linux の Claude Code は Linux
6. **終わったら確かめる**
   - Windows: `scripts\install-windows.ps1 -Check` が「そろっています」で終わる
   - Linux(使う場合): 下の「確かめる」のコマンドがすべて通る
   - 最後に利用者が WezTerm をすべて閉じてから起動し直し、「前の作業」の画面が出る(Esc で閉じるとツリーが出る)・Shift+Alt+O でフォルダを開ける・Claude Code の状態がタブに出ることを見る

## 導入(Windows。管理者権限は要らない)

### 1. Git・ripgrep・lazygit を入れる(winget。どれも公式パッケージで、自分のユーザーだけに入る)

```powershell
winget install --id Git.Git -e --scope user       # 入っていなければ
winget install --id BurntSushi.ripgrep.MSVC -e    # ファイル・文字列の検索
winget install --id JesseDuffield.lazygit -e      # Git の画面(任意)
```

入れた後は、PATH を読み直すために PowerShell を開き直します。

### 2. このリポジトリを置いて、導入スクリプトを実行する

```powershell
git clone https://github.com/abe326/terminal-env.git $HOME\terminal-env
powershell -NoProfile -ExecutionPolicy Bypass -File $HOME\terminal-env\scripts\install-windows.ps1
```

`-ExecutionPolicy Bypass` はこの 1 回の実行だけに効きます(PC の設定は変えません)。スクリプトは Windows に最初から入っている PowerShell 5.1 で動き、何度実行しても構いません(済んでいるものは飛ばします)。

| 項目 | スクリプトがすること |
|---|---|
| WezTerm・Neovim | 公式の zip 版を sha256 で照合し、`%LOCALAPPDATA%\Programs\` に置いてユーザーの PATH に足す。winget などで既に入っていれば、それを使う |
| スタートメニューの WezTerm | zip 版を入れたときだけ作る。Windows の通知(確認待ち・完了)を出すのに要る。タスクバーへのピン留めはここから |
| UDEV Gothic NF | 公式の zip の 35NF の 4 本を、自分のフォントに入れる |
| `WEZTERM_CONFIG_FILE` | ユーザー環境変数。WezTerm がこのリポジトリの設定を読む |
| `%LOCALAPPDATA%\nvim` | このリポジトリの `nvim` へのジャンクション。既にあれば `nvim.bk_<日時>` に名前を変えて残す |
| `wezterm\local.lua` | 無ければ見本(`local.example.lua`)から作る |
| Neovim のプラグイン | lazy.nvim が各プラグインの公式 GitHub リポジトリから、`nvim/lazy-lock.json` の版(作者が動作を確かめた版)を入れる |

- 入れる版と sha256 はスクリプトの先頭にあります。確かめるだけなら `-Check` を付けます(何も変えず、足りないものがあれば終了コード 1)
- プラグインを新しい版にするときは、Neovim の中で `:Lazy update`(各自の判断で。更新内容を確かめてから)

### 3. 自分の環境の値を書く(変えたいものがあれば)

スクリプトが作った `local.lua` は、値の行がすべてコメントなので、**このままでも既定値で動きます**(フォルダの一覧はホームの直下)。
変えたい行だけ、先頭の `--` を外して書き換えます。まずは一覧するフォルダ(`local_projects_root`)を書くのがおすすめです。

```powershell
notepad $HOME\terminal-env\wezterm\local.lua
```

書き方は下の「設定」。

### 4. Claude Code の状態をタブに出す(Claude Code を使う場合)

`%USERPROFILE%\.claude\settings.json` の `hooks` に次を足します(既に `hooks` があれば、その中に足す)。
hook は Git Bash で動きます。`<you>` は自分のユーザー名(パスは置いた場所に合わせる)。

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

Git を `--scope user` で入れて Claude Code が Git Bash を見つけられないときは、ユーザー環境変数 `CLAUDE_CODE_GIT_BASH_PATH` に `%LOCALAPPDATA%\Programs\Git\bin\bash.exe` を書きます。

### 5. 起動する

開いている WezTerm をすべて閉じてから、スタートメニュー(またはタスクバー)で起動します(WezTerm の中から起動すると、前の環境変数を引き継ぎます)。

## 導入(リモートの Linux 機。使う場合だけ)

リモート側の `bin/` は GNU coreutils を前提にしています(`base64 -w0`・`date +%s%N`・`find -printf`・`realpath`)。一般的な Linux ディストリビューションには入っています。macOS や BusyBox では動かないことがあります。

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
# 既に ~/.config/nvim がフォルダとしてあると、ln はその中にリンクを作ってしまうので、先に名前を変えて残す
[ -e ~/.config/nvim ] && [ ! -L ~/.config/nvim ] && mv ~/.config/nvim ~/.config/nvim.bk_$(date +%Y%m%d)
mkdir -p ~/.config ~/.local/bin
ln -sfn ~/terminal-env/nvim ~/.config/nvim
ln -sf ~/terminal-env/bin/wopen ~/terminal-env/bin/tmux-tree ~/terminal-env/bin/tenv-open ~/terminal-env/bin/tenv-cc-state ~/.local/bin/
chmod +x ~/terminal-env/bin/*
echo 'source-file ~/terminal-env/tmux/terminal-env.conf' >> ~/.tmux.conf
tmux source-file ~/.tmux.conf 2>/dev/null || true
nvim --headless +qa   # 初回の起動でプラグインが入る(lazy-lock.json の版)
```

`~/.local/bin` が `PATH` に入っていない場合は追加してください。管理者権限(`sudo`)は要りません(tmux・ripgrep をパッケージで入れる場合を除く)。

### 3. Claude Code の状態をタブに出す(Claude Code を使う場合)

リモートの `~/.claude/settings.json` の `hooks` に次を足します(既に `hooks` があれば、その中に足す)。

```json
"hooks": {
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.local/bin/tenv-cc-state prompt", "async": true }] }],
  "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "~/.local/bin/tenv-cc-state tool", "async": true }] }],
  "Notification":     [{ "matcher": "permission_prompt|elicitation_dialog",
                         "hooks": [{ "type": "command", "command": "~/.local/bin/tenv-cc-state waiting", "async": true }] }],
  "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.local/bin/tenv-cc-state done", "async": true }] }],
  "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "~/.local/bin/tenv-cc-state end", "async": true }] }]
}
```

### 4. Windows 側の設定にリモートを足す

Windows の `local.lua` の最後にある `remotes` の例を有効にして、つなぐ先を書きます(すぐ上の `--[=[` の 1 行を消す。書き方は下の「設定」の「リモート」)。

### 5. 確かめる

```bash
readlink ~/.config/nvim                                   # ~/terminal-env/nvim
ls -l ~/.local/bin/{wopen,tmux-tree,tenv-open,tenv-cc-state}
tmux -L tenv-check -f ~/.tmux.conf new-session -d && tmux -L tenv-check list-keys -T root M-E && tmux -L tenv-check kill-server
nvim --headless +qa && echo ok
```

tmux の行は、設定を読む別の tmux を一時的に起動して、Shift+Alt+E が登録されたかを見ます(何も出なければ `source-file` の行が読まれていません。置いた場所のパスに `[` `]` があると、tmux はそれを glob として扱うので `\[` `\]` と書きます)。

## 使い方

### 1 日の流れ

1. WezTerm を起動すると、「前の作業」の画面のタブ 1 つで窓が開く。前回 Claude Code を開いたまま閉じていれば再開の一覧(下の「前の作業を再開」)、無ければフォルダの一覧(Shift+Alt+O と同じ)。**Tab** で 2 つを切り替える。何も開かずに Esc で閉じると、いつもの画面(左にツリー、右にシェル)になる
2. **Shift+Alt+O** でフォルダを選ぶ。新しいタブで PowerShell が開く。フォルダの横には **最後に Claude Code へ指示を出した日時** が出る
   - 一覧は 3 段の字下げで並ぶ: 接続先(**Linux**(リモート)・**ローカルPC**)> 一覧の場所(親フォルダの名前と場所)> フォルダ。リモートのフォルダは新しいタブで ssh + tmux になる。**Shift+Alt+P** はこの PC のフォルダだけ
3. 開いたタブは「左にツリー、右で Claude Code が起動」の並びになる
4. ツリーのファイルをダブルクリックで右上段のエディタに、右クリックで「アプリで開く」など。ツリーは **Shift+Alt+E** で出し入れできる
5. 作業を終えたら WezTerm を閉じてよい。この PC の Claude Code は閉じると止まるが、次の起動時に「前の作業」の画面から続きを開ける。**リモートは tmux の中で動き続ける**ので、次に同じフォルダを選ぶと、閉じたときの並びのまま戻る

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

- 同じ画面に **フォルダを開く** 一覧(Shift+Alt+O と同じ。リモート・この PC のフォルダ)もあり、**Tab** で切り替えます。↑↓ で選び、Enter かクリックで開く(新しいタブで、Claude Code は新しい会話で起動)
- **WezTerm を起動したとき**、この画面が自動で出ます。「前回開いていた」会話か、リモートで動いていて誰も見ていない会話があれば再開の一覧、無ければフォルダの一覧から始まります
- Claude Code を使わないなら、設定の `claude_resume = false` で止めます(キーと「＋」の項目も消え、起動時の画面はフォルダの一覧だけになる)。起動時に再開の一覧を出さないだけなら `claude_resume_on_startup = false`、フォルダの一覧を出さないなら `open_on_startup = false`(両方 `false` なら起動時は何も出ない)

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

### リモートから、この PC の Claude Code に頼む(使う場合だけ)

リモートで `wopen --claude <ファイル>` を実行すると、この PC の WezTerm が新しいタブで Claude Code を起動し、最初の指示として「次のファイルを読んで、書かれている依頼を進めてください: <この PC のパス>」を渡します。リモートの Claude Code(Bash ツール)からも呼べます。頼む内容はファイルに書き、ファイルは同期などでこの PC からも見える場所に置きます。

- 設定(`local.lua`)の `ask_claude` に、起動する場所(`cwd`)と、渡せるファイルの場所(`allowed`)を書いたときだけ動きます。書き方は `local.example.lua`
- 権限のモードは付けません。この PC の Claude Code の設定のまま(既定は操作のたびに確認)で動くので、承認はこの PC の画面で行います
- ファイルが同期で遅れて届くときは、10 秒ほど待ちます

## 設定(`wezterm/local.lua`)

ツリーの右クリック →「設定」で開きます。保存するとすぐ反映されます(窓の大きさだけは次の起動から)。
書き方の見本と各項目の説明は [`wezterm/local.example.lua`](wezterm/local.example.lua) にあります(導入スクリプトが `local.lua` に写す)。
見本は値の行がすべてコメントなので、書かなかった項目は下の表の既定値になります。変えたい行だけ、先頭の `--` を外して書き換えます。
使わない項目も、例はコメントのまま残しておきます(後から使うときに `--` を外して書き換えるだけで済む)。
設定は 4 つのまとまりです。

### 基本(Windows だけで使う場合は、ここだけ)

| 項目 | 既定 | 内容 |
|---|---|---|
| `shell` | 自動 | この PC の pane のシェル。省略時は `pwsh.exe` が PATH にあればそれ、無ければ `powershell.exe`(5.1) |
| `local_projects_root` | ホーム | Shift+Alt+P / O で一覧するフォルダ(この直下を選べる)。複数なら `{ [[C:\a]], [[D:\b]] }` |
| `start_command` | `"claude"` | フォルダを開いたとき右の pane で起動するコマンド。`false` ならシェルのまま |
| `open_with_tree` | `true` | フォルダを開いたとき左にツリーを出すか |
| `tree_on_startup` | `true` | WezTerm を起動した最初の画面(起動時の画面を何も開かずに閉じたとき・出さないとき)にもツリーを出すか |
| `open_on_startup` | `true` | WezTerm を起動したとき、フォルダを開く一覧(Shift+Alt+O と同じ)を出すか。「前の作業」の画面のタブ 1 つで窓を始め、前回開いていた作業があれば再開の一覧を先に出す(Tab で切り替え) |
| `tree_width` | `34` | ツリーの幅(桁)。開くときはいつもこの幅 |
| `tree_width_fixed` | `true` | 窓の大きさを変えてもツリーの幅を保つか(上の「ツリー」を参照) |

### 前の作業を再開(Claude Code を使う場合)

| 項目 | 既定 | 内容 |
|---|---|---|
| `claude_resume` | `true` | 前の作業を再開を使うか。`false` なら Shift+Alt+R と「＋」の項目も消える |
| `claude_resume_on_startup` | `true` | WezTerm を起動したとき、前回開いていた作業があれば再開の画面を出すか |
| `claude_resume_days` | `3` | 一覧に出す会話(この日数以内に使ったもの) |

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

### リモート(`remotes`。使う場合だけ)

ssh でつなぐ Linux 機を、1 台ずつ `{ ... }` で書きます。書かなければリモートは無しで、Shift+Alt+O もこの PC のフォルダだけを出します。
見本では最後に例があり、`--[=[` と `--]=]` で囲んで無効にしてあります。使うときは `--[=[` の 1 行を消して、つなぐ先の値に書き換えます。
Shift+Alt+O の一覧では、リモートは「Linux」の見出しの下に並びます。複数台を書くと、見分けるために見出しに `name` が添えられます。

```lua
remotes = {
  {
    name = "myserver",               -- 表示名(右上。複数台のときは一覧の見出しにも)
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
| `bin/wopen` | リモート → WezTerm へ合図を送る(開く・表示・編集・Git・設定・操作一覧・ファイルの配置・Claude Code に頼む) |
| `scripts/install-windows.ps1` | Windows の導入(管理者権限なし。`-Check` で確かめるだけ) |
| `scripts/check_public.py` | 公開前の検査(秘密・個人の情報の形が無いか。CI でも動く) |
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
  - **合言葉が守るのは「端末に流れただけの文字列」(cat したファイル・ログ・AI の出力など)です。リモートの機械そのものが乗っ取られた場合は守れません**(乗っ取った側は合言葉のファイルを読めるので、本物と同じ合図を作れます)。信用できないリモートにはつながないでください
- 受け付けるのは `open_allowed`(省略時は `path_map` のリモート側)の下のパスだけ。`..` を含むパスは捨てます

**Claude Code に頼む(`wopen --claude`)**
- 起動するのは `ask_claude.command`(`.exe` だけ。省略時 `claude.exe`)だけで、ほかのコマンドは起動しません。権限のモード(`--dangerously-skip-permissions` など)は付けません
- 起動する場所は設定で固定です。コマンド行に入るのはファイルの場所だけで、頼む内容は入りません
- 渡せるのは `ask_claude.allowed` の直下の `.md` だけです。それより下のフォルダ・ほかの場所・記号(`% ^ & ! " < > |` など)を含む名前は断ります
- 続けて来た合図(`interval` 秒以内。既定 30 秒)は無視し、タブが大量に開かないようにします
- **ファイルの中身は Claude Code への依頼としてそのまま読まれます。リモートが乗っ取られると、乗っ取った側が書いた依頼でも Claude Code が起動します。** この PC の Claude Code の権限の設定で何でも許す形(`--dangerously-skip-permissions`・広い allow など)にしていると、確認なしに実行されます。使うなら、確認が出る設定のまま、出た確認をその場で読んでください

**開く(「アプリで開く」・端末のリンク)**
- リモートの合図・端末のリンク(`file:`)から開くとき: 実行形式(exe・bat・ps1・lnk など、Windows で開く = 実行になる種類)は開きません。スクリプト(py・sh など)・マクロを含みうる Office(xlsm・doc など)は、開く前に確認を出します(最初に選ばれているのは「やめる」)。それ以外(文書・画像・データ・ソースコードなど)はそのまま開きます
- 拡張子の無い名前・`%` を含む名前・Windows で別の意味になる文字(`: " < > | ? * \`・制御文字・名前の末尾の `.` と空白)を含む名前は開きません。Windows が種類を補ったり環境変数を展開したりして、名前と違うファイルを実行するのを防ぐためです。中を見るならツリーのダブルクリック(エディタ)
- 端末の中のリンクは、http / https / mailto と、この PC のファイル(`file:`。上と同じ扱い)を開きます。それ以外の種類(Windows でプログラムを動かせるもの)は開きません
- **ツリーの「アプリで開く」(右クリック・`O`)は、手元のファイルを Windows の既定のアプリで開きます。これは実行形式(exe・bat など)も開ける = 実行するので、中身の分からないフォルダのファイルは、中を見るならダブルクリック(エディタ)、場所を見るなら「エクスプローラー」を使ってください**(名前を補って別のファイルを実行することはありません。名前どおりのものが無ければ開きません)

**送る(ドラッグ&ドロップ)**
- 送る前に必ず確認を出し、送るファイルを手元の場所ごと並べます。送っている間は下に小さな画面が出て、終わると「配置しました」と知らせます
- 鍵や認証の情報の置き場所(`.ssh`・`.gnupg`・`.aws`・`.azure`・`.kube`・`.docker`・`.claude`・ブラウザのプロファイル・Windows の資格情報・この仕組みの合言葉など)や、ホーム・ドライブ直下・AppData を丸ごと送ることはしません

**そのほか**
- 開いたフォルダの `.git/config` の、ツリー・下の行の Git 表示で勝手に動くコマンド(`core.fsmonitor`)は動かしません。ただし Git が `.git/config` や `.gitattributes` に従って動かすもの(`filter` など)まで止めきれるわけではありません。**中身の分からないフォルダ(受け取ったもの・展開したもの)は、ツリーで開かないでください**
  - Git の速くする仕組み(fsmonitor)を使っている大きなリポジトリでは、ツリーの Git の表示が少し遅くなることがあります
- ファイルの中の vim の設定の行(modeline)は、リモートの編集でもローカルでも読みません
- Windows では、ツリーとエディタから起動するもの(nvim・git・rg・lazygit など)について、開いたフォルダに置かれた同じ名前のプログラムを、本物の代わりに動かしません(今のフォルダを探さない設定・絶対パスでの起動。pane のシェルには影響しません)
- エディタとの連絡口は、Linux では自分だけが使えるフォルダ、Windows では推測できない名前にします
- Neovim のプラグインは `nvim/lazy-lock.json` の版で入ります(lazy.nvim 本体も含めて、勝手に新しい版にはなりません)
- リモートのシェルで右クリックしても、Windows のクリップボードは貼り付けません

**使う人が気をつけること**
- このフォルダ(`wezterm/`・`nvim/`・`bin/`)は、設定であると同時に**動くプログラム**です。リモートや同期ツールから書き換えられる場所に置くと、そこを乗っ取られたときに Windows でも動いてしまいます。Windows で使うものは、Windows だけが書き込める場所に置いてください
- **更新(`git pull`)は、プログラムの更新と同じです。** 信用できる取得元から取り込み、気になるときは差分を見てください
- `local.lua` の `open_command` に自分のスクリプトを書く場合、渡されるパスはリモート由来です。`Invoke-Expression` などで命令として扱わないでください
- 端末に流れた文字列は、クリップボードに書き込むこともできます(OSC 52。WezTerm と tmux の標準の機能で、tmux の `allow-passthrough` を通ります)。リモートで信用できないものを表示した後は、貼り付ける前に中身を確かめてください

## 外す

- Windows: 環境変数 `WEZTERM_CONFIG_FILE` を消し、`%LOCALAPPDATA%\nvim` のジャンクションを消す(`cmd /c rmdir "%LOCALAPPDATA%\nvim"`。`Remove-Item -Recurse` はリンク先の中身まで消すことがあるので使わない)。`settings.json` の `tenv-cc-state` の hook を消す。導入スクリプトで入れたものは、`%LOCALAPPDATA%\Programs\WezTerm`・`Neovim` のフォルダ、スタートメニューの `WezTerm`、ユーザーの PATH の 2 行、フォント(設定 →「フォント」)
- Linux: `~/.tmux.conf` の `source-file` の行を消し、`~/.config/nvim` と `~/.local/bin/{wopen,tmux-tree,tenv-open,tenv-cc-state}` のリンクを消す。`settings.json` の hook を消す

## ライセンス

このリポジトリの設定ファイルは [MIT License](LICENSE)。
入手して使うソフト・フォント・プラグインのライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください(このリポジトリには同梱していません)。
