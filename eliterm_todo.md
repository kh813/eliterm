# eliterm — ToDoリスト

Version 0.1 / 仕様書 v0.8 対応

凡例: `[ ]` 未着手 / `[~]` 進行中 / `[x]` 完了 / `[-]` 将来フェーズ

---

## Phase 0: プロジェクトセットアップ

### 0.1 リポジトリ・プロジェクト初期化
- [x] `mix new eliterm --sup` でプロジェクト作成
- [x] `.gitignore` 設定
- [x] `README.md` 初稿作成
- [x] ライセンス選定・`LICENSE` ファイル追加

### 0.2 依存ライブラリの追加
- [x] `horde` を `mix.exs` に追加
- [x] `libcluster` を `mix.exs` に追加
- [x] `quantum-core` を `mix.exs` に追加
- [x] `ExPTY` を `mix.exs` に追加
- [x] 各ライブラリの動作確認（`mix deps.get` / `mix compile`）

### 0.3 開発環境の検証
- [x] Elixir / OTP バージョン確認・固定（`.tool-versions` 等）
- [x] ExPTY の NIF がビルドできることを確認（Linux x86_64）
- [x] ExPTY の NIF がビルドできることを確認（Linux aarch64）

---

## Phase 1: コア基盤（v0.1）

### 1.1 OTP スーパーバイザーツリー
- [x] `Eliterm.Application` の初期実装
- [x] `Horde.Registry` の起動・設定
- [x] `Horde.DynamicSupervisor` の起動・設定
- [x] `Eliterm.ClusterManager` GenServer の骨格実装
- [x] `Eliterm.SessionSupervisor` の実装
- [x] `Eliterm.DataSync` モジュールの骨格実装

### 1.2 クラスタ管理
- [x] `eliterm cluster init` — クラスタ初期化・cookie 生成・保存（`~/.eliterm/`）
- [x] `eliterm cluster join <node>` — 既存クラスタへの参加
- [x] `eliterm cluster leave` — クラスタ離脱・プロセス停止
- [x] `eliterm list nodes` — クラスタノード一覧表示
- [x] `eliterm node info <node>` — ノード詳細表示（OS・アーキテクチャ・空きディスク・稼働時間）
- [x] `eliterm node ping <node>` — 疎通確認・レイテンシ計測
- [x] libcluster の設定（Gossip または mDNS 戦略）
- [x] Erlang Distribution の TLS 設定

### 1.3 PTY・bash セッション
- [x] `Eliterm.PTY` GenServer の実装（ExPTY ラッパー）
- [x] bash 起動時の環境設定（`HOME=home/`・`SHELL` パス・`bash --norc` オプション検討）
- [x] `.bashrc` のロード設定
- [x] PTY リサイズ対応（`SIGWINCH` ハンドリング）
- [x] Unix socket 経由のクライアント接続実装
- [x] デーモン起動・バックグラウンド化の実装（`mix release` + `--no-halt`）
- [x] PID ファイル管理（`~/.eliterm/eliterm.pid`）
- [x] `eliterm stop --daemon` — デーモン本体の停止実装
- [x] `eliterm start` 時のデーモン起動済みチェック
- [x] `eliterm start --headless` — セッション起動（ヘッドレスモード）
- [x] `eliterm attach [<session-id>]` — セッションへのアタッチ
- [x] `eliterm detach` — セッションのデタッチ
- [x] `eliterm stop [<session-id>]` — セッション停止
- [x] `eliterm list sessions` — セッション一覧表示
- [x] `eliterm session info <session-id>` — セッション詳細表示
- [x] `eliterm session rename <old> <new>` — セッション名変更

### 1.4 セッションスナップショット
- [x] `Eliterm.SessionSnapshot` 構造体の定義
- [x] `declare -p` によるシェル変数の取得
- [x] `alias` によるエイリアスの取得
- [x] `HISTFILE` からのコマンド履歴取得
- [x] cwd の取得と `home/` 内相対パスへの正規化
- [x] 環境変数（`env`）の取得
- [x] スナップショットの JSON シリアライズ・デシリアライズ
- [x] `~/.eliterm/sessions/<id>/.session/snapshot.json` への保存

### 1.5 home/ ディレクトリ管理
- [x] `~/.eliterm/sessions/<id>/home/` ディレクトリの初期化
- [x] `home/crontab` の初期テンプレート生成
- [x] `home/scripts/` ディレクトリの初期化
- [x] `home/` サイズ計算・内訳表示の実装
- [x] `home/` の書き込み禁止・解除（`chmod` ベース）
- [x] rsync による `home/` 一括コピーの実装（`System.cmd("rsync", ...)`）
- [x] コピー後の SHA256 チェックサム検証
- [x] rsync プログレスバー表示

### 1.6 Quantum（cron）統合
- [x] `Eliterm.CronManager` GenServer の実装
- [x] `home/crontab` の読み込み・パース
- [x] `# name:` コメント規約のパース実装（名前なし行は `job_1`, `job_2` と自動採番）
- [x] Quantum へのジョブ動的登録
- [x] `@reboot` ジョブのマイグレート先での自動実行
- [x] `#!/bin/sh` スクリプトを `bash --posix` で実行する設定
- [x] crontab の `~` を `home/` パスに解決する処理
- [x] Quantum の起動・停止制御
- [x] `eliterm list jobs` — ジョブ定義一覧表示（スケジュール・有効/無効・前回/次回実行）
- [x] `eliterm list procs` — 実行中ジョブ一覧表示
- [x] `eliterm job run <name>` — ジョブ手動実行
- [x] `eliterm job disable <name>` — ジョブ一時停止
- [x] `eliterm job enable <name>` — ジョブ再開
- [x] `eliterm job log <name> [--lines <n>]` — ジョブ実行ログ表示
- [x] ジョブ実行ログの `sync.log` への記録

### 1.7 マイグレーション
- [x] `Eliterm.ClusterManager` へのマイグレーションフロー実装
- [x] ターゲットノードの空き容量確認 (`calc_size` と比較)
- [x] ソースノードでの Quantum 停止・bash PTY 切断
- [x] スナップショット作成処理の呼び出し
- [x] `home/` の書き込み保護処理の呼び出し
- [x] rsync による転送とチェックサム検証の呼び出し
- [x] `home/` の書き込み保護解除
- [x] ターゲットノードでのプロセス再構築（`Horde.DynamicSupervisor` を使用）
- [x] スナップショット状態の復元と bash プロセスの再開
- [x] Quantum スケジューラの再開・ジョブ再登録

### 1.8 分散ステート・フェイルオーバー
- [x] Horde / libcluster を使ったセッションレジストリ共有
- [x] ネットワーク分断時のスプリットブレイン対応方針（仕様確認・ドキュメント化）
- [x] ノードダウン検知時のリカバリフロー（仕様確認・実装）

### 1.9 CLI インターフェース統合
- [x] `OptionParser` を用いたコマンドライン引数パース
- [x] `eliterm` バイナリの構築（escript または mix release）
- [x] 各種コマンドの実装
  - [x] `eliterm cluster init/join/leave`
  - [x] `eliterm list nodes/sessions/jobs/procs`
  - [x] `eliterm start/stop/attach/detach`
  - [x] `eliterm job run/disable/enable/log`
  - [x] `eliterm migrate <node>`

---

## Phase 2: 検証・安定化

### 2.1 E2E テスト・挙動検証
- [x] ローカル2ノード（`node1`, `node2`）でのクラスタリングテスト
- [x] セッション起動と bash 変数設定・crontab 登録の動作確認
- [x] `node1` → `node2` へのマイグレーション実行テスト
- [x] ターゲットノードでのジョブ自動再開の確認
- [x] ディレクトリ権限・サイズ計算・rsync 転送の正常性確認

### 2.2 リリースビルド
- [x] `mix release` 設定の最適化（`rel/env.sh.eex` などの調整）
- [x] インストールスクリプト（`install.sh`）の作成
- [x] `PATH` への `eliterm` コマンド自動追加処理

### 2.3 未決定事項の確定
- [x] PTY 接続方式の最終決定（Unix socket / TCP）
- [x] rsync プログレスバーの CLI 表示方式の確定
- [x] `crontab` へのジョブ名定義方法（コメント規約 `# name: backup` 等）
- [x] クラスタ cookie のファイル保存場所・ノード間共有方法

---

## Phase 3: コンテナ・アプリケーション管理（v0.2）

- [ ] Podman コマンドの存在チェックと利用可能検証（Mac の場合は podman machine 状態確認含む）
- [ ] `Eliterm.Container` 抽象レイヤーの設計・実装
- [ ] `Eliterm.Container.Podman` の実装（Linux / macOS 共通）
- [ ] Debian slim コンテナイメージの管理（Pull）
- [ ] コンテナ内での bash プロセス起動と PTY アタッチの切り替え
- [ ] コンテナへの `home/` バインドマウント設定
- [ ] `home/.eliterm-apps` スキーマ定義
- [ ] `eliterm-apps` からの `apt` パッケージ自動インストール機能実装
- [ ] マイグレーション時の `eliterm-apps` 転送と再構築

---

## Phase 4: 同期・自動化（v0.3）

- [x] スリープ検知のクロスプラットフォーム設計（Swift / systemd-inhibit）の策定
- [ ] macOS 向けネイティブスリープ検知ヘルパー（Swift）の実装
- [ ] インストール時の Swift ヘルパーコンパイル処理の追加
- [ ] `Eliterm.SleepWatcher` Elixir モジュールの実装
- [ ] `eliterm.toml` への自動マイグレーション設定（`target_node`）追加
- [ ] スリープ検知時の自動全セッションマイグレートフローの統合
- [ ] ノードオフライン時の自動フェイルオーバー（将来拡張）

---

## Phase 5: macOS ネイティブ仮想化対応（将来構想）

- [ ] Virtualization.framework + Debian slim VM の起動・停止実装
- [ ] VM 内 `home/` の virtio-fs マウント設定
- [ ] Podman Machine を使わない macOS ネイティブ動作環境の提供

---

## Phase 6: デスクトップ GUI（v0.5）

- [-] elixir-desktop ライブラリの導入
- [-] Phoenix LiveView による UI 実装
- [-] CLI と同一バックエンドとの接続
- [-] ghostty_ex への PTY バックエンド移行検討
- [-] 全プラットフォーム向けインストーラ生成（`mix desktop.deploy`）

---

*eliterm_todo.md — Version 0.1*
