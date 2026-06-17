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

- Phase 1.4: セッションスナップショット機能の実装を完了しました。
  - `Eliterm.SessionSnapshot` 構造体と `capture/3` メソッドを実装。
  - `~/.bashrc` に SIGUSR1 トラップを自動生成し、bash側から自発的に環境変数・cwd・変数をファイルに吐き出させる機構を追加。
  - スナップショットの JSON 化と `.session/snapshot.json` への保存処理を追加。

- Phase 1.5: `home/` ディレクトリ管理機能の実装を完了しました。
  - `Eliterm.DataSync` にて `init_home/1` を実装し、初期ディレクトリやcrontabテンプレートを生成。
  - `calc_size/1` で `du` コマンドを使ったサイズ・内訳計算を実装。
  - `set_readonly/2` で `chmod` ベースのディレクトリ保護機能を実装。
  - `rsync_copy/3` で `--info=progress2` を用いたプログレス付きディレクトリ転送を実装。
  - `verify_checksum/1` にて `tar | shasum` を用いた高速かつパーミッション考慮のチェックサム機能を追加。

- Phase 1.6: Quantum（cron）統合機能の実装を完了しました。
  - `Eliterm.Scheduler` および `Eliterm.CronManager` の実装と `application.ex` への組み込み。
  - `crontab` のカスタムパース (`# name:` 対応、`~` の `home/` 置換) を実装。
  - Quantum へのジョブの動的追加・有効化・無効化のAPI基盤を追加。
  - `bash --posix` を用いたジョブ実行と、`sync.log` への標準出力および終了コードの記録を実装。

- Phase 1.7: セッションマイグレーション機能の実装を完了しました。
  - `Eliterm.ClusterManager` に `migrate_session/2` のフローを実装。
  - ソースノードでのプロセス停止・スナップショット取得・ディレクトリ保護・rsync同期・チェックサム検証のシーケンスを実装。
  - ターゲットノードでのプロセス再起動・スナップショットからの bash 環境変数/cwd復元の自動化を実装。

- Phase 1.8: 分散ステート・フェイルオーバーの方針策定を完了しました。
  - `FAILOVER.md` を作成し、本システムの特性（home/ディレクトリのノードローカル依存）に基づくスプリットブレイン対応およびフェイルオーバーの制約をドキュメント化しました。

- Phase 1.9: CLI インターフェース統合の実装を完了しました。
  - `mix escript.build` によるスタンドアロンCLIバイナリ生成基盤を構築。
  - `Eliterm.CLI` にて、裏側で動作するバックグラウンドデーモンに対するローカルRPCクライアントを実装。
  - cluster, list, session, job, migrate 操作を一通りサポート。

- Phase 2: 検証・安定化フェーズを完了しました。
  - `test_e2e.sh` を作成し、2つのローカルノード間でのクラスタ接続とマイグレーションが正常に動作することを確認。
  - `install.sh` を作成し、`escript` でビルドした `eliterm` コマンドのインストールと `PATH` の自動設定を追加。
  - プロトコルを Unix Domain Socket、rsyncプログレスを `--info=progress2` で標準出力に流す方針で確定。

## 2026-06-17
- Phase 7: GUI安定化・機能補強（v0.1.16）の計画を開始し、以下の改善を実装・ドキュメント化しました。
  - GUIアプリ内でのネイティブクリップボード連携によるコピペ（Cmd+C/Cmd+V, Ctrl+C/Ctrl+V）対応を実装。
  - `TerminalLive` の表示領域計算のバグを修正（flexレイアウトとbox-sizingの調整により、vi等で最下行が見切れる問題を解決）。
  - macOSの GUIアプリから起動した場合でも Docker Desktop/Podman を正しく検出できるよう、`/opt/homebrew/bin/` 等のパス探索ロジックを追加。
  - コンテナ（Debian）起動時に自動で `apt-get update` を実行し、ユーザーがすぐに `apt-get install` できるよう改善。
