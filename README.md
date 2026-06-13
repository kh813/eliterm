# Eliterm

Eliterm (Elixir Terminal) は、ターミナルセッション、cronジョブ、および `home/` ディレクトリをノード間で移送（マイグレート）できる、ポータブルな分散ターミナル環境です。

## 特徴
- bash セッション（cwd・環境変数・履歴）をノード間でマイグレート可能
- cron ジョブ（Quantum）をセッションとともに移送し、別ノードで継続実行
- `home/` ディレクトリ（スクリプト・venv・CLIアプリ等）をまるごと持ち運び
- インタラクティブモード（bash + cron）とヘッドレスモード（cron のみ）に対応
- 一般ユーザー権限のみで動作（root・sudo 不要）

## 開発環境
- Elixir
- OTP

## ライセンス
[MIT License](LICENSE)
