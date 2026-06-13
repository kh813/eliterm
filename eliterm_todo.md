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
- [ ] `horde` を `mix.exs` に追加
- [ ] `libcluster` を `mix.exs` に追加
- [ ] `quantum-core` を `mix.exs` に追加
- [ ] `ExPTY` を `mix.exs` に追加
- [ ] 各ライブラリの動作確認（`mix deps.get` / `mix compile`）

### 0.3 開発環境の検証
- [ ] Elixir / OTP バージョン確認・固定（`.tool-versions` 等）
- [ ] ExPTY の NIF がビルドできることを確認（Linux x86_64）
- [ ] ExPTY の NIF がビルドできることを確認（Linux aarch64）

---

## Phase 1: コア基盤（v0.1）

### 1.1 OTP スーパーバイザーツリー
- [ ] `Eliterm.Application` の初期実装
- [ ] `Horde.Registry` の起動・設定
- [ ] `Horde.DynamicSupervisor` の起動・設定
- [ ] `Eliterm.ClusterManager` GenServer の骨格実装
- [ ] `Eliterm.SessionSupervisor` の実装
- [ ] `Eliterm.DataSync` モジュールの骨格実装

### 1.2 クラスタ管理
- [ ] `eliterm cluster init` — クラスタ初期化・cookie 生成・保存（`~/.eliterm/`）
- [ ] `eliterm cluster join <node>` — 既存クラスタへの参加
- [ ] `eliterm cluster leave` — クラスタ離脱・プロセス停止
- [ ] `eliterm list nodes` — クラスタノード一覧表示
- [ ] `eliterm node info <node>` — ノード詳細表示（OS・アーキテクチャ・空きディスク・稼働時間）
- [ ] `eliterm node ping <node>` — 疎通確認・レイテンシ計測
- [ ] libcluster の設定（Gossip または mDNS 戦略）
- [ ] Erlang Distribution の TLS 設定

### 1.3 PTY・bash セッション
- [ ] `Eliterm.PTY` GenServer の実装（ExPTY ラッパー）
- [ ] bash 起動時の環境設定（`HOME=home/`・`SHELL` パス・`bash --norc` オプション検討）
- [ ] `.bashrc` のロード設定
- [ ] PTY リサイズ対応（`SIGWINCH` ハンドリング）
- [ ] Unix socket 経由のクライアント接続実装
- [ ] デーモン起動・バックグラウンド化の実装（`mix release` + `--no-halt`）
- [ ] PID ファイル管理（`~/.eliterm/eliterm.pid`）
- [ ] `eliterm stop --daemon` — デーモン本体の停止実装
- [ ] `eliterm start` 時のデーモン起動済みチェック
- [ ] `eliterm start --headless` — セッション起動（ヘッドレスモード）
- [ ] `eliterm attach [<session-id>]` — セッションへのアタッチ
- [ ] `eliterm detach` — セッションのデタッチ
- [ ] `eliterm stop [<session-id>]` — セッション停止
- [ ] `eliterm list sessions` — セッション一覧表示
- [ ] `eliterm session info <session-id>` — セッション詳細表示
- [ ] `eliterm session rename <old> <new>` — セッション名変更

### 1.4 セッションスナップショット
- [ ] `Eliterm.SessionSnapshot` 構造体の定義
- [ ] `declare -p` によるシェル変数の取得
- [ ] `alias` によるエイリアスの取得
- [ ] `HISTFILE` からのコマンド履歴取得
- [ ] cwd の取得と `home/` 内相対パスへの正規化
- [ ] 環境変数（`env`）の取得
- [ ] スナップショットの JSON シリアライズ・デシリアライズ
- [ ] `~/.eliterm/sessions/<id>/.session/snapshot.json` への保存

### 1.5 home/ ディレクトリ管理
- [ ] `~/.eliterm/sessions/<id>/home/` ディレクトリの初期化
- [ ] `home/crontab` の初期テンプレート生成
- [ ] `home/scripts/` ディレクトリの初期化
- [ ] `home/` サイズ計算・内訳表示の実装
- [ ] `home/` の書き込み禁止・解除（`chmod` ベース）
- [ ] rsync による `home/` 一括コピーの実装（`System.cmd("rsync", ...)`）
- [ ] コピー後の SHA256 チェックサム検証
- [ ] rsync プログレスバー表示

### 1.6 Quantum（cron）統合
- [ ] `Eliterm.CronManager` GenServer の実装
- [ ] `home/crontab` の読み込み・パース
- [ ] `# name:` コメント規約のパース実装（名前なし行は `job_1`, `job_2` と自動採番）
- [ ] Quantum へのジョブ動的登録
- [ ] `@reboot` ジョブのマイグレート先での自動実行
- [ ] `#!/bin/sh` スクリプトを `bash --posix` で実行する設定
- [ ] crontab の `~` を `home/` パスに解決する処理
- [ ] Quantum の起動・停止制御
- [ ] `eliterm list jobs` — ジョブ定義一覧表示（スケジュール・有効/無効・前回/次回実行）
- [ ] `eliterm list procs` — 実行中ジョブ一覧表示
- [ ] `eliterm job run <name>` — ジョブ手動実行
- [ ] `eliterm job disable <name>` — ジョブ一時停止
- [ ] `eliterm job enable <name>` — ジョブ再開
- [ ] `eliterm job log <name> [--lines <n>]` — ジョブ実行ログ表示
- [ ] ジョブ実行ログの `sync.log` への記録

### 1.7 マイグレーション
- [ ] `Eliterm.ClusterManager` へのマイグレーションフロー実装
- [ ] `eliterm migrate <node>` コマンドの実装
- [ ] `--session` 指定時は指定セッションのみ、省略時は全セッションを移送する分岐
- [ ] `home/` サイズ表示・ユーザー確認プロンプト（y/N）
- [ ] 実行中 Quantum ジョブの完了待ち（5分自動待機）
- [ ] 5分超時のユーザー選択プロンプト（[w]/[f]/[c]）
- [ ] ハードリミット（デフォルト30分）による強制中断
- [ ] `home/` 書き込み禁止への切り替え
- [ ] 新規ジョブキューイング開始
- [ ] `home/` rsync 転送（プログレス表示付き）
- [ ] マイグレート先での Quantum 起動・キュー処理
- [ ] セッションスナップショットの転送
- [ ] マイグレート先での bash セッション復元
- [ ] マイグレート元のセッション・Quantum 停止・無効化
- [ ] マイグレーション失敗時のロールバック実装
  - [ ] 転送済みデータの削除
  - [ ] 書き込み禁止の解除
  - [ ] ネットワーク切断時のタイムアウト処理

### 1.8 設定ファイル
- [ ] `eliterm.toml` のスキーマ定義
  - [ ] bash パス
  - [ ] タイムアウト値（cron ジョブ待機・ハードリミット）
  - [ ] クラスタ設定
- [ ] `eliterm.toml` の読み込み・バリデーション実装
- [ ] `~/.eliterm/eliterm.toml` の初期生成（`eliterm cluster init` 時）

### 1.9 CLI フレームワーク
- [ ] CLI ライブラリの選定（`optparse` / `cli` / 独自実装）
- [ ] サブコマンドルーティングの実装
- [ ] エラーメッセージの整形・表示
- [ ] `--help` オプションの実装（全コマンド）
- [ ] `--version` オプションの実装

---

## Phase 2: 品質・配布（v0.1 リリース前）

### 2.1 テスト
- [ ] `Eliterm.SessionSnapshot` のユニットテスト
- [ ] `Eliterm.CronManager` のユニットテスト（Quantum ジョブ登録・削除）
- [ ] `Eliterm.DataSync` のユニットテスト（rsync コマンド生成・チェックサム）
- [ ] マイグレーションフローの統合テスト（ローカル2ノード構成）
- [ ] クラスタ join/leave のテスト
- [ ] ロールバック処理のテスト

### 2.2 配布バイナリ
- [ ] `mix release` によるリリースビルド設定
- [ ] ERTS 同梱の自己完結バイナリ生成（Linux x86_64）
- [ ] ERTS 同梱の自己完結バイナリ生成（Linux aarch64）
- [ ] ExPTY プリコンパイル済み NIF の同梱（各プラットフォーム）
- [ ] インストールスクリプト作成（`~/.eliterm/bin/` へ展開）
- [ ] PATH 追記の案内メッセージ実装（`~/.bashrc` / `~/.zshrc`）

### 2.3 未決定事項の確定（実装中に決める）
- [ ] PTY 接続方式の最終決定（Unix socket / TCP）
- [ ] セッション ID の自動生成形式（例: `session-1`、UUID、形容詞+名詞など）
- [ ] `crontab` へのジョブ名定義方法（コメント規約 `# name: backup` 等）
- [ ] クラスタ cookie のファイル保存場所・ノード間共有方法

---

## Phase 3: macOS 対応（v0.2）

- [-] Virtualization.framework + Debian slim VM の起動・停止実装
- [-] VM 内 `home/` の virtio-fs マウント設定
- [-] macOS 向けバイナリビルド（aarch64 / x86_64）
- [-] ExPTY NIF の macOS 向けプリコンパイル
- [-] Podman Machine を使わない macOS ネイティブ動作の確認
- [-] macOS 向けインストールスクリプト整備

---

## Phase 4: 同期・自動化（v0.3）

- [-] lsyncd による `home/` リアルタイム同期の実装
- [-] lsyncd 設定ファイルの自動生成
- [-] macOS スリープ検知（`NSWorkspace.willSleepNotification`）連携
- [-] Linux スリープ検知（`systemd-inhibit`）連携
- [-] スリープ検知時の自動マイグレートフロー
- [-] ノードオフライン時の自動フェイルオーバー

---

## Phase 5: アプリケーション管理（v0.4）

- [-] `Eliterm.Container` 抽象レイヤーの設計・実装
- [-] `Eliterm.Container.Podman` の実装（Linux / WSL / macOS 25以下）
- [-] `Eliterm.Container.AppleContainer` の実装（macOS 26以上）
- [-] `home/.eliterm-apps` スキーマ定義
- [-] Debian slim コンテナイメージの管理
- [-] `home/` のマウント（Podman: bind mount、Apple container: 自動共有）
- [-] `eliterm-apps` からの apt パッケージ自動インストール
- [-] pip / npm グローバルパッケージのインストール対応
- [-] アーキテクチャ別パッケージ指定（aarch64 / x86_64）の対応
- [-] マイグレーション時の `eliterm-apps` 転送・再現

---

## Phase 6: デスクトップ GUI（v0.5）

- [-] elixir-desktop ライブラリの導入
- [-] Phoenix LiveView による UI 実装
- [-] CLI と同一バックエンドとの接続
- [-] ghostty_ex への PTY バックエンド移行検討
- [-] 全プラットフォーム向けインストーラ生成（`mix desktop.deploy`）

---

*eliterm_todo.md — Version 0.1*
