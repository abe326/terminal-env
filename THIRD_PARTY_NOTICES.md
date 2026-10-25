# 利用するソフトウェアとライセンス

このリポジトリには以下のソフトウェア・フォント・プラグインは **同梱していません**。
利用者が各公式の配布元から入手し、それぞれのライセンスに従って利用します。
このリポジトリに入っているのは、自作の設定ファイル・スクリプト・説明だけです([MIT License](LICENSE))。

## 必要なもの

| 名前 | 用途 | ライセンス | 公式の配布元 |
|---|---|---|---|
| WezTerm | ターミナル | MIT | <https://wezterm.org> / <https://github.com/wez/wezterm> |
| Neovim | ツリー・エディタ | Apache-2.0(一部 Vim License) | <https://neovim.io> / <https://github.com/neovim/neovim> |
| UDEV Gothic NF | フォント | SIL Open Font License 1.1 | <https://github.com/yuru7/udev-gothic> |
| Git(Windows では Git for Windows) | プラグインの取得・Git の状態・hook を動かす bash | GPL-2.0 | <https://git-scm.com> / <https://gitforwindows.org> |
| ripgrep | 検索の本体 | MIT / Unlicense(どちらか) | <https://github.com/BurntSushi/ripgrep> |
| lazy.nvim | プラグイン管理 | Apache-2.0 | <https://github.com/folke/lazy.nvim> |
| tokyonight.nvim | 配色 | Apache-2.0 | <https://github.com/folke/tokyonight.nvim> |
| neo-tree.nvim | ファイルツリー | MIT | <https://github.com/nvim-neo-tree/neo-tree.nvim> |
| nui.nvim | neo-tree の部品 | MIT | <https://github.com/MunifTanjim/nui.nvim> |
| plenary.nvim | neo-tree・telescope の部品 | MIT | <https://github.com/nvim-lua/plenary.nvim> |
| nvim-web-devicons | アイコン | MIT | <https://github.com/nvim-tree/nvim-web-devicons> |
| lualine.nvim | ステータス行 | MIT | <https://github.com/nvim-lualine/lualine.nvim> |
| render-markdown.nvim | Markdown のプレビュー | MIT | <https://github.com/MeanderingProgrammer/render-markdown.nvim> |
| telescope.nvim | ファイル名・文字列の検索の画面 | MIT | <https://github.com/nvim-telescope/telescope.nvim> |

## 使う場合だけ

| 名前 | 用途 | ライセンス | 公式の配布元 |
|---|---|---|---|
| tmux | リモートの pane 管理 | ISC | <https://github.com/tmux/tmux> |
| PowerShell 7 | 入っていれば、この PC の pane のシェルに使う(無ければ Windows 標準の PowerShell 5.1) | MIT | <https://github.com/PowerShell/PowerShell> |
| OpenSSH | リモートへの接続 | BSD 系(Windows 標準の機能) | Windows の「オプション機能」 |
| lazygit | Git の操作画面 | MIT | <https://github.com/jesseduffield/lazygit> |
| Mutagen | ファイルの同期(右上の同期の状態) | MIT。ただし v0.17 以降の公式ビルドには SSPL のコードを含む | <https://github.com/mutagen-io/mutagen> |
| Claude Code | タブの状態表示(hook) | Anthropic の利用規約 | <https://code.claude.com/docs> |

## その他

- WezTerm の配色(Tokyo Night・Catppuccin Mocha・Kanagawa・Rosé Pine)は、WezTerm に同梱されているものを名前で指定しているだけで、このリポジトリには含まれていません。
- `nvim/lazy-lock.json` は、各プラグインの版(コミットの番号)を書いた一覧だけで、プラグインのコードは含みません。
- アイコンは、利用者が入れたフォント(UDEV Gothic NF に含まれる Nerd Fonts のアイコン)の文字を番号で指定しているだけです。

ライセンスは 2026-10-25 時点で各リポジトリの表記を確認したものです。最新の条件は各配布元を確認してください。
