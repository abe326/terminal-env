# Changelog

## 0.2.0 — 2026-10-25

- Windows の導入に管理者権限を要らなくした。`scripts/install-windows.ps1`(PowerShell 5.1 で動く)が WezTerm・Neovim の公式 zip 版とフォントを自分のユーザーだけに入れ、設定をつなぐ。`-Check` で確かめるだけもできる
- PowerShell 7 を必須から外した。`pwsh.exe` が無ければ Windows 標準の PowerShell 5.1 を使う(`local.lua` の `shell` で指定もできる)
- README に「Claude Code に導入を任せる場合」、Linux の hook の書き方、確かめる手順を足した

## 0.1.0 — 2026-10-25

- 初回公開。WezTerm・tmux・Neovim(neo-tree)の設定と、WezTerm 経由で Windows 側のアプリで開く中継(`bin/`)
