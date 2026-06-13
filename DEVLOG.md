# DEVLOG

## 2026-06-13
- Phase 0.1: リポジトリ・プロジェクト初期化を完了しました。
  - `mix new` でElixirプロジェクトの作成
  - `.gitignore` の設定（デフォルト）
  - `README.md` の初稿作成
  - MIT Licenseでの `LICENSE` ファイル追加
  - `git init` による初期化

- Phase 0.2: 依存ライブラリの追加を完了しました。
  - `mix.exs` に `horde`, `libcluster`, `quantum`, `expty` を追加
  - `mix deps.get` および `mix compile` で正常にビルドできることを確認

- Phase 0.3: 開発環境の検証を完了しました。
  - `.tool-versions` に Elixir 1.19.5, Erlang 28.0 を固定
  - `expty` が `cc_precompiler` によって各アーキテクチャの NIF バイナリを適切に解決できることを確認

- Phase 1.1: OTP スーパーバイザーツリーを実装しました。
  - `Eliterm.Application` に `Horde.Registry`, `Horde.DynamicSupervisor` を登録。
  - `Eliterm.ClusterManager`, `Eliterm.SessionSupervisor`, `Eliterm.DataSync` の骨格を作成。

- Phase 1.2: クラスタ管理ロジックを実装しました。
  - `Eliterm.Cluster` モジュールに `init`, `join`, `leave`, `list_nodes`, `node_info`, `ping` を実装。
  - `libcluster` の戦略として Gossip を採用。
  - 将来の厳格なCA認証（v0.6）を仕様書ロードマップに追記。

- Phase 1.3: PTY・bash セッションのコアロジックを実装しました。
  - `Eliterm.PTY` にて `ExPTY` 経由での bash 起動・環境変数設定（HOME等）を実装。
  - Unix Domain Socket 経由での送受信ロジック（PTYのI/Oプロキシ）を実装。
  - `Eliterm.ShellSession` スーパーバイザーの作成と `start_session/2` のバックエンド機能を提供。

