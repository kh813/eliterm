# eliterm — ポータブル分散ターミナル環境

**仕様書** / Version 1.0 Draft

> プロジェクト名 **eliterm** 正式決定（Elixir Terminal の略）

---

## 目次

1. [プロジェクト概要](#1-プロジェクト概要)
2. [要件定義](#2-要件定義)
3. [システムアーキテクチャ](#3-システムアーキテクチャ)
4. [セッションモデル](#4-セッションモデル)
5. [マイグレーション設計](#5-マイグレーション設計)
6. [home/ ディレクトリ設計](#6-home-ディレクトリ設計)
7. [cron 統合設計（Quantum）](#7-cron-統合設計quantum)
8. [PTY 設計](#8-pty-設計)
9. [データ同期設計（将来）](#9-データ同期設計将来)
10. [アプリケーション管理設計（将来）](#10-アプリケーション管理設計将来)
11. [CLI 設計](#11-cli-設計)
12. [クラスタ構成](#12-クラスタ構成)
13. [インストール設計](#13-インストール設計)
14. [将来ロードマップ](#14-将来ロードマップ)

---

## 1. プロジェクト概要

### 1.1 背景と目的

自分のPCをスリープさせる前に、作業中のターミナルセッションとcronジョブを別のノードに移送し、PCを閉じた後も処理を継続させたい。次にPCを開いたときは、そのセッションに再接続して作業を再開できる。

**eliterm** はこのユースケースを実現する、Elixir/OTP ベースのポータブルターミナル環境である。

- bash セッション（cwd・環境変数・履歴）をノード間でマイグレートできる
- cron ジョブ（Quantum）をセッションとともに移送し、別ノードで継続実行できる
- `home/` ディレクトリ（スクリプト・venv・CLIアプリ等）をまるごと持ち運べる
- インタラクティブモード（bash + cron）とヘッドレスモード（cron のみ）を提供する

### 1.2 想定ユースケース

```
[自分のPC]                        [常時稼働ノード]
  eliterm start
  作業中...
  eliterm migrate remote-node  →   セッション・cron・home/ を移送
  PCをスリープ                        cron継続実行

  PCを再起動
  eliterm attach session-1     ←   セッションにアタッチ
  作業再開
```

---

## 2. 要件定義

### 2.1 機能要件

#### セッション管理
- bash セッションを起動・終了・アタッチ・デタッチできること
- セッションは名前（session-id）で識別できること
- 複数セッションの同時管理ができること
- ヘッドレスモード（bash なし、cron のみ）で起動できること

#### マイグレーション
- `eliterm migrate <node>` コマンドで手動マイグレートできること
- マイグレート前にデータサイズを表示し、ユーザー確認を求めること
- マイグレート中は `home/` を書き込み禁止にすること
- 実行中の cron ジョブ完了を待ってからマイグレートすること
- マイグレート中にスケジュール時刻が来た場合はマイグレート先で実行すること
- マイグレート後、元ノードのセッション・cron・home/ は停止・無効化されること

#### home/ ディレクトリ
- `home/` ディレクトリ一式をマイグレート先にコピーできること
- 想定サイズは数十〜数百 MB（ユーザーが管理する、プログラム側で制限しない）
- コピー方式は rsync 相当（差分転送・整合性チェックあり）

#### cron 統合
- `home/crontab` を読み込んで Quantum スケジューラを起動できること
- sh スクリプトは `bash --posix` で実行すること
- マイグレート時は cron を停止し、マイグレート先で再起動すること

#### クラスタ
- マイグレート先は事前に eliterm をインストールしクラスタを構成しておく必要があること
- クラスタ構成はセキュアチャンネル（TLS）を前提とすること

### 2.2 非機能要件

| 分類 | 要件 |
|---|---|
| 移送可能な状態 | cwd・環境変数・シェル変数・エイリアス・コマンド履歴 |
| 移送できない状態 | 実行中コマンド（vim等）・パイプ内データ・バックグラウンドジョブ |
| データサイズ | ユーザーが自己判断。プログラムは警告のみで制限しない |
| bash バージョン | 5.x 以上（macOS は eliterm インストール時に自動セットアップ） |
| 実行権限 | **一般ユーザー権限のみで動作すること。root・sudo は不要** |
| インストール先 | **XDG標準（`~/.config/eliterm/`等）またはプロジェクトルート以下。システム領域への書き込みは行わない** |
| cron 実行権限 | **Quantum によるジョブ実行はアプリケーション起動ユーザーの権限で動作する** |

### 2.3 スコープ外（v0.1）

| 項目 | 区分 |
|---|---|
| 実行中コマンドのマイグレート（vim 等） | 永続的スコープ外（OS レベルで不可能） |
| 自動スリープ検知によるマイグレート | 将来実装 |
| home/ のリアルタイム同期 | 将来実装 |
| アプリケーション管理（仮想化環境） | 将来実装 |
| デスクトップ GUI | 将来実装 |

---

## 3. システムアーキテクチャ

### 3.1 全体構成

```
┌─────────────────────────────────────────────────────┐
│                   eliterm クラスタ                    │
│                                                       │
│  ┌──────────────────┐       ┌──────────────────┐     │
│  │  ノードA（自分のPC）│       │  ノードB（サーバー）│     │
│  │                  │       │                  │     │
│  │ ShellSession ●  │ ────→ │ ShellSession ○  │     │
│  │ Quantum (active) │       │ Quantum (standby)│     │
│  │ home/ (rw)       │       │ home/ (syncing)  │     │
│  │                  │       │                  │     │
│  └──────────────────┘       └──────────────────┘     │
│              Horde / libcluster                       │
└─────────────────────────────────────────────────────┘
         ↑
   eliterm attach / eliterm CLI
```

### 3.2 OTP スーパーバイザーツリー

eliterm は Elixir/OTP の分散プロセス管理機能を活用する。
**Horde** はクラスタ全体にまたがる分散 Supervisor / Registry を提供し、
ノード障害時のプロセス再起動やセッションの名前解決をクラスタ透過的に扱える。
**libcluster** はノード間の自動検出とクラスタ形成を担う。
**Eliterm.ClusterManager** はノード参加・離脱・マイグレーションのフローを制御する GenServer である。

```
Eliterm.Application  (Supervisor: one_for_one)
├── Horde.Registry                    分散レジストリ（セッション名前解決・クラスタ全体で有効）
├── Horde.DynamicSupervisor           分散スーパーバイザー（セッション管理・ノード障害時に自動再配置）
├── Eliterm.ClusterManager            ノード参加・離脱・マイグレーションのフロー制御
├── Eliterm.SessionSupervisor         セッション群の管理
│   └── Eliterm.ShellSession          bash + Quantum の1セッション分（GenServer）
│       ├── Eliterm.PTY               bash の入出力（ExPTY ベース NIF）
│       └── Eliterm.CronManager       crontab 読み込み・Quantum 制御
└── Eliterm.DataSync                  home/ のコピー・同期
```

### 3.3 主要ライブラリ

| ライブラリ | 役割 | 採用理由 |
|---|---|---|
| horde | 分散 Supervisor / Registry | Erlang クラスタ全体でプロセスを透過的に管理できる。ノード障害時の自動再配置も提供 |
| libcluster | ノード自動検出・クラスタ形成 | DNS・mDNS・Gossip など複数の検出戦略に対応。設定ファイルだけでクラスタを構成できる |
| quantum-core | cron スケジューラ | OS 非依存・全 OS 対応（詳細はセクション7参照） |
| ExPTY | PTY（擬似端末）制御 | Linux・macOS・WSL 対応 NIF（詳細はセクション8参照） |

---

## 4. セッションモデル

### 4.1 セッション状態

```
IDLE ──start──→ RUNNING ──migrate──→ MIGRATING ──完了──→ (別ノードで RUNNING)
                    ↑                     │
                 attach               cancel
                    │                     ↓
                DETACHED            RUNNING（元ノードに戻る）
```

| 状態 | 説明 |
|---|---|
| `RUNNING` | bash・cron が稼働中。アタッチ可能 |
| `DETACHED` | bash・cron は稼働中だがターミナル接続なし |
| `MIGRATING` | マイグレーション処理中。書き込み禁止 |
| `IDLE` | 停止中 |

### 4.2 スナップショット（移送できる状態）

```elixir
%Eliterm.SessionSnapshot{
  session_id:  "session-1",
  cwd:         "/home/user/project",     # home/ 内の相対パスに正規化
  env:         %{"PATH" => "...", "VIRTUAL_ENV" => "..."},
  shell_vars:  "declare -p の出力",      # declare -p で取得
  aliases:     "alias の出力",           # alias で取得
  history:     ["cmd1", "cmd2", ...],    # HISTFILE から読み込み
  captured_at: ~U[2025-01-01 12:00:00Z]
}
```

**注:** cwd は `home/` ディレクトリ内の相対パスとして保存する。
マイグレート先での `home/` パスが異なっても正しく復元できる。

### 4.3 セッション ID の命名規則

セッション ID は「形容詞 + 名詞」のランダム組み合わせで自動生成する（Docker スタイル）。

```
brave-newton
hungry-hopper
sleepy-turing
```

UUID より覚えやすく、連番より衝突しにくい。`--session <name>` で任意名の指定も可能。

### 4.4 移送できないもの（設計上の割り切り）

| 状態 | 理由 |
|---|---|
| 実行中コマンド（vim 等） | OS プロセスはノードをまたいで fork できない |
| パイプ内データ | バッファはカーネル管理 |
| バックグラウンドジョブ | 同上 |
| 開いているファイルディスクリプタ | 同上 |

マイグレート実行時に実行中コマンドがあれば、警告を表示してユーザーに確認する。

---

## 5. マイグレーション設計

### 5.1 マイグレーション手順（正常系）

```
1.  eliterm migrate <node> 実行
2.  home/ サイズ計算・内訳表示
3.  ユーザー確認（y/N）
4.  実行中 Quantum ジョブの完了待ち（タイムアウト: 5分、設定変更可）
5.  home/ を書き込み禁止に設定
6.  新規 Quantum ジョブの起動を停止（キューイング開始）
7.  home/ をマイグレート先ノードにコピー転送（rsync・プログレス表示）
8.  マイグレート先で Quantum 起動（キューに溜まったジョブも実行）
9.  セッションスナップショットをマイグレート先に転送
10. マイグレート先で bash セッション復元
11. マイグレート元のセッション・Quantum を停止
12. eliterm attach で再接続可能な状態になる
```

### 5.2 マイグレーション中のスケジュール時刻到来

```
マイグレーション中（ステップ 4〜10）にスケジュール時刻が来た場合：
→ マイグレート先のキューに積む
→ ステップ 8 でマイグレート先の Quantum 起動時に実行
```

**二重実行の防止:** キューイング停止後にコピー開始のため、元ノードでは実行されない。

### 5.3 タイムアウト設計（Quantum ジョブ待機）

| フェーズ | デフォルト | 動作 |
|---|---|---|
| 自動待機 | 5分 | 黙って待つ（進捗表示あり） |
| 警告・選択 | 5分超 | ユーザーに選択肢を提示 |
| ハードリミット | 30分 | `--force-timeout <分>` で変更可 |

5分超時の選択肢：

```
警告: cron ジョブが 5分以上実行中です（backup.sh: 00:05:23）
選択してください：
  [w] 続けて待つ
  [f] 強制中断してマイグレート（ジョブは FAILED として記録）
  [c] マイグレートをキャンセル
```

閾値は `eliterm.toml` で変更可能。

### 5.4 ユーザー確認画面（例）

```
$ eliterm migrate remote-node

セッション: session-1
転送先:     eliterm@remote-server
home/ サイズ: 342 MB（転送時間の目安: 約2分）

内訳:
  scripts/    12 MB
  venv/      280 MB
  work/       50 MB

続行しますか？ [y/N] _
```

### 5.5 失敗時のロールバック

| 失敗ステップ | 動作 |
|---|---|
| コピー転送中に失敗 | 転送済みデータを削除、元ノードの書き込み禁止を解除 |
| マイグレート先での起動失敗 | 同上 |
| ネットワーク切断 | タイムアウト後に元ノードに戻る（書き込み禁止を解除） |

### 5.6 `@reboot` ジョブの扱い

`home/crontab` に `@reboot` が定義されている場合、マイグレート先での Quantum 起動時に実行する。

**理由:** `@reboot` はメモリ解放・初期化処理を想定したものであり、マイグレート先での環境立ち上げ時にも同様の初期化が必要と考えるのが順当。

### 5.7 複数セッションのマイグレーション

```bash
eliterm migrate remote-node                  # 全セッションを移送
eliterm migrate remote-node --session <id>   # 指定セッションのみ移送
```

`--session` 省略時は全セッションを順番に移送する。全セッション移送の場合、cron ジョブ待機・転送は各セッションを順次処理する。

### 6.1 ディレクトリ名の選定

`data/` から **`home/`** に変更する。

**理由:** eliterm における bash のホームディレクトリそのものであるため。
bash 起動時に `HOME` 環境変数をこのパスに設定し、`~` がここを指す。

```bash
# eliterm が bash を起動するとき
HOME=/path/to/eliterm-session/home bash
```

### 6.2 ディレクトリ構成

eliterm はすべてのデータをユーザーのホームディレクトリ以下に配置する。
システム領域（`/usr/`, `/etc/`, `/var/` 等）への書き込みは一切行わない。

```
~/.config/eliterm/                   (elitermの管理ルート・インストール先。ローカル開発時は ./.eliterm/)
├── bin/                          elitermバイナリ本体（ERTS同梱）
├── eliterm.toml                  全体設定
├── eliterm.pid                   デーモンの PID ファイル
└── sessions/
    └── session-1/                (セッション単位)
        ├── home/                 ← bash の HOME ディレクトリ
        │   ├── .bashrc           bash 設定
        │   ├── .bash_history     コマンド履歴
        │   ├── crontab           このセッションの cron 定義
        │   ├── scripts/          cron から呼ばれるスクリプト
        │   ├── venv/             Python 仮想環境など
        │   └── work/             作業ファイル
        └── .session/             内部管理データ（ユーザーが触らない）
            ├── snapshot.json     セッションスナップショット
            ├── eliterm.sock      Unix socket（パーミッション 0600）
            └── sync.log          同期ログ
```

### 6.3 サイズに関する方針

- **プログラム側でサイズ制限はしない。** 数十〜数百MB は通常の使用範囲。
- 数GBになる場合はNAS等に置くべきで、ユーザーが判断する。
- マイグレート前に内訳付きでサイズを表示する。

### 6.4 コピー方式（v0.1）

v0.1 のマイグレーション時は `rsync` による一括コピーを行う。

- 転送後に SHA256 チェックサムで整合性を確認する。
- 転送中はプログレスバーを表示する。
- Elixir からは `System.cmd("rsync", [...])` で呼び出す。

リアルタイム同期（lsyncd）は将来実装（セクション9参照）。

---

## 7. cron 統合設計（Quantum）

### 7.1 OS crond を使わない理由

| OS | OS 標準 cron | 問題点 |
|---|---|---|
| Linux | `crond` / `cron` | ディストリ間でオプションが異なる |
| macOS | `launchd` | crontab 書式が非標準。`crond` は非推奨扱い |
| WSL | `cron`（Ubuntu系） | WSL 環境によって挙動が不安定 |

全 OS で一貫した動作を保証するため、**Quantum（Elixir ネイティブの cron ライブラリ）** を採用する。

Quantum は eliterm プロセス内部で動作するため、ジョブの実行権限は **eliterm を起動したユーザーの権限そのもの**になる。OS の cron デーモン（root 管理）とは完全に独立しており、sudo や特権昇格は一切不要である。

### 7.2 crontab 書式の互換性

Quantum は標準 crontab 5フィールド書式に対応しており、`home/crontab` をそのまま読み込める。

```
# home/crontab の例（標準 crontab 書式）
*/5 * * * *  ~/scripts/backup.sh
0 2 * * *    ~/scripts/cleanup.sh
@reboot      ~/scripts/on_start.sh
```

`~` は `home/` ディレクトリに解決される。

### 7.3 ジョブ名の定義規約

標準 crontab にはジョブ名フィールドがない。eliterm は行直前の `# name:` コメントをジョブ名として解釈する。

```
# name: backup
*/5 * * * *  ~/scripts/backup.sh

# name: cleanup
0 2 * * *    ~/scripts/cleanup.sh

# name: weekly-report
0 9 * * 1    ~/scripts/report.sh

@reboot      ~/scripts/on_start.sh
```

- `# name:` コメントがない行は `job_1`、`job_2` と自動採番する
- この規約は標準 crontab と完全互換（eliterm なしで `crontab` コマンドで読んでも壊れない）
- `eliterm job run <name>` / `eliterm job disable <name>` 等でジョブ名を使って操作できる

### 7.4 sh スクリプトの実行

`#!/bin/sh` または `SHELL` 未指定のスクリプトは `bash --posix` で実行する。

```elixir
System.cmd("bash", ["--posix", script_path], env: session_env)
```

### 7.5 `@reboot` ジョブの扱い

`@reboot` ジョブはマイグレート先での Quantum 起動時に実行する。

**理由:** `@reboot` はメモリ解放・初期化処理のために使われるケースが多く、新しい実行環境（マイグレート先ノード）でも同様に実行するのが順当である。

```
マイグレート先で Quantum が起動
→ @reboot ジョブをキューに積む
→ 通常のキュー処理と同様に実行
```

### 7.6 マイグレーション時の Quantum 状態

| フェーズ | マイグレート元 | マイグレート先 |
|---|---|---|
| 待機中 | 実行中ジョブ完了待ち | 待機 |
| コピー中 | Quantum 停止・書き込み禁止 | 待機 |
| 起動後 | 停止済み | Quantum 起動（キュー処理） |

---

## 8. PTY 設計

### 8.1 採用ライブラリ：ExPTY

**ExPTY**（`cocoa-xu/ExPTY`）を採用する。`microsoft/node-pty` ベースの NIF 実装で Linux・macOS・WSL に対応。

```elixir
{:ok, pty} = ExPTY.spawn("bash", [],
  name: "xterm-256color",
  cols: 220,
  rows: 50,
  on_data: fn _pty, _pid, data -> forward_to_client(data) end,
  on_exit: fn _pty, _pid, exit_code, _signal -> handle_exit(exit_code) end
)

ExPTY.write(pty, user_input)
ExPTY.resize(pty, new_cols, new_rows)
```

### 8.2 認証方針

`eliterm attach` の認証は **Unix socket のパーミッション（0600）** で行う。

- socket ファイルを `0600`（所有者のみ読み書き可）で作成する
- OS レベルで同一ユーザー以外の接続を自動的に弾く
- 特別な認証ロジックは不要。同一ユーザーであれば無条件にアタッチできる

### 8.3 クライアント接続方式

CLI クライアント（`eliterm attach`）は Unix socket 経由で PTY の入出力を中継する。

```
[ユーザーの端末]
     ↕ stdin/stdout（raw モード）
[eliterm CLI プロセス]
     ↕ Unix socket / TCP
[Eliterm.PTY GenServer（サーバーノード）]
     ↕ ExPTY
[bash プロセス（HOME=home/）]
```

---

## 9. 自動マイグレーションとスリープ検知

### 9.1 スリープ検知のクロスプラットフォーム方針

OS がスリープ（サスペンド）する直前にセッションを退避させるため、OS のスリープイベントをフックし、マイグレーションが完了するまでスリープを遅延させる機能を提供する。
外部依存を最小限にするため、各 OS のネイティブな仕組みを活用する。

| OS | スリープ検知・遅延の手段 | 採用技術・実装方針 |
|---|---|---|
| **macOS** | `NSWorkspace.willSleepNotification` と `IOPMAssertion` | **Swift**<br>小さなヘルパープログラムを Swift で実装する。GitHub Actions 経由で事前コンパイルされたバイナリを配布することで、ユーザー環境でのコンパイル時間を削減し、安定した動作を提供する。 |
| **Linux** | `systemd-inhibit` (DBus) | **OS標準 CLI**<br>C や Rust を用いず、Elixir から `systemd-inhibit --mode=delay` コマンドを実行するだけでスリープ遅延を実現する。 |
| **Windows** | `SystemEvents.PowerModeChanged` (C#) | **C# スクリプト**<br>`.NET` の `SystemEvents.PowerModeChanged` を監視する C# スクリプトを実装する。こちらも GitHub Actions 経由で事前コンパイル（`.exe`化）して配布する。 |

### 9.2 アーキテクチャ

`Eliterm.SleepWatcher` モジュール（Elixir）が、設定ファイル（`eliterm.toml`）に基づいてバックグラウンドで OS 固有のウォッチャープロセスを起動する。

1. ウォッチャープロセスが OS のスリープイベントを検知。
2. ウォッチャーがスリープを一時的にブロックし、Elixir デーモンにシグナル（または標準出力経由でメッセージ）を送信。
3. `Eliterm.SleepWatcher` が `eliterm.toml` に定義されたターゲットノードへ全セッションを `migrate`。
4. マイグレーション完了（またはタイムアウト）後、ウォッチャープロセスに完了を通知し、スリープブロックを解除させる。

---

## 10. データ同期設計（将来）

> **v0.1 はスコープ外。** マイグレーション時の rsync 一括コピーのみ実装する。
> 以下は将来バージョンの設計方針として記録する。

### 9.1 lsyncd を採用する理由

将来のリアルタイム同期には **lsyncd** を採用する方針とする。

| 比較軸 | lsyncd | rsync デーモンモード |
|---|---|---|
| トリガー | inotify / fsevents（イベント駆動） | ポーリング or 手動 |
| macOS 対応 | ✅ fsevents 対応 | ✅（ただしスケジュール管理が別途必要） |
| 設定の簡潔さ | Lua スクリプト1ファイル | rsync + cron/systemd の組み合わせ |
| Elixir からの制御 | `System.cmd` で起動・停止 | 同左 |
| 遅延 | 数秒以内（イベント集約あり） | ポーリング間隔に依存 |

**採用理由:** イベント駆動で遅延が小さく、Linux（inotify）・macOS（fsevents）両対応。
eliterm は「ほぼリアルタイムに近い」同期で十分であり、lsyncd の設計思想と一致する。

### 9.2 lsyncd の設定イメージ

```lua
-- eliterm が自動生成する lsyncd.conf.lua
settings {
  logfile    = "/tmp/eliterm-sync.log",
  statusFile = "/tmp/eliterm-sync.status",
}

sync {
  default.rsync,
  source = "/path/to/session-1/home/",
  target = "user@remote-node:/path/to/session-1/home/",
  rsync  = { archive = true, compress = true }
}
```

### 9.3 常時同期とマイグレーションの関係

常時同期が有効なノード間では、マイグレーション時の転送コストがほぼゼロになる。
（差分のみの転送になるため）

---

## 10. アプリケーション管理設計（将来）

> **v0.1 はスコープ外。** 以下は将来バージョンの設計方針として記録する。

### 10.1 設計の目標

各ノードで同じアプリケーション群がインストールされた状態を再現する。
ノードの OS やアーキテクチャが異なっても、アプリケーションリストから同等の環境を構築できること。

### 10.2 アーキテクチャの課題

eliterm が動作する環境の組み合わせ：

| OS | アーキテクチャ | 備考 |
|---|---|---|
| Linux | x86_64 / aarch64 | サーバー・デスクトップ |
| macOS | Apple Silicon (aarch64) | M1/M2/M3 |
| macOS | Intel (x86_64) | 旧Mac |
| WSL | x86_64 | Windows上 |

x86_64 バイナリは macOS Apple Silicon でネイティブ動作しないため、
**アーキテクチャごとに適切なパッケージを選択する仕組み**が必要。

### 10.3 採用方針：コンテナ（Debian slim ベース）

Alpine Linux の検討結果：

| 検討案 | 評価 |
|---|---|
| Alpine Linux + apk | ❌ **musl 非互換問題あり。** Python 等のネイティブライブラリがmusl非対応のケースが多く、「動くはずのパッケージが動かない」リスクが高い |
| Debian slim + apt | ✅ glibc ベース。Python・その他ネイティブライブラリの互換性が高い |
| pacman (Arch系) | △ ローリングリリースで最新パッケージが揃うが、安定性がやや劣る |

**採用: Debian slim + apt** をコンテナのベースとする。

### 10.4 コンテナ実行バックエンド

コンテナバックエンドとして、全OS（Linux / macOS / WSL）共通で **Podman (rootless)** を標準とする。

| ホスト OS | バックエンド | 備考 |
|---|---|---|
| Linux | Podman (rootless) | VM 不要・軽量・ユーザー権限のみ |
| WSL | Podman (rootless) | Linux と同様 |
| macOS | Podman Machine | 内部的に QEMU/Apple Hypervisor を用いた軽量 VM を管理し、自動的にディレクトリマウントなどを提供 |

Docker はデーモンが root 権限で動作するため eliterm のユーザー権限方針と相容れず、採用しない。
Virtualization.framework を自前で制御するアプローチ（Apple container machine 相当）は将来フェーズ（Phase 5等）へ見送り、まずは Podman にOS間の差異を吸収させる構成で堅牢な環境を提供する。

**フォールバック（ローカル実行）モード**
コンテナエンジン（Podman または Docker）がユーザー環境にインストールされていない場合でも、アプリケーションがクラッシュせず即座に利用できるよう、**ローカルの bash シェルへ自動的にフォールバックする機能**を備える。これにより、コンテナ環境未構築のユーザーでもGUI/CLIを通常のローカルターミナルとして利用開始できる。

**Elixir 側の抽象レイヤー：**

```
Eliterm.Container（抽象）
└── Eliterm.Container.Podman          Linux / WSL / macOS 共通バックエンド
```

コンテナイメージ（Debian slim）を用い、ホスト側の `home/` を `-v` (bind mount) でコンテナ内にマウントする。

#### コンテナ内のユーザー・ホスト名・Sudo権限の自動構成
開発体験とセキュリティの双方を最適化するため、コンテナ起動時に以下の構成を自動で行います：
- **ホスト名の固定**: コンテナのホスト名を `eliterm` に固定し、プロンプトを `user@eliterm` の形式に整えます。
- **一般ユーザーでの実行とUID/GIDの同期**: ホストOS側のUID/GIDを起動時に自動で検出し、コンテナ内へ同じ権限を持つ非root一般ユーザー `user` を自動作成します。マウントした `home/` ディレクトリ配下のファイル権限競合を未然に防ぎます。
- **パスワードレスSudoの設定**: `debian:stable-slim` 内に `sudo` パッケージを自動インストールし、`/etc/sudoers.d/user` に `user ALL=(ALL) NOPASSWD:ALL` (パーミッション `0440`) を定義します。これにより、一般ユーザー権限でありながら、対話シェル内からパスワードなしで `sudo apt install ...` などの管理者用コマンドを実行できます。

### 10.5 アプリケーションリスト管理

インストール済みアプリケーションは `home/.eliterm-apps` として管理し、マイグレーション時に転送する。

```toml
# home/.eliterm-apps
[packages]
apt = ["git", "curl", "jq", "ripgrep", "fzf", "python3", "nodejs"]

[pip]
packages = ["requests", "pandas"]

[npm]
global = ["typescript", "prettier"]
```

新しいノードでセッションを復元する際、`eliterm-apps` を読み込んでパッケージを自動インストールする。
アーキテクチャに依存するバイナリ（例: x86_64 専用 CLI ツール）については、
利用可能なバリアントを `eliterm-apps` に記述できるようにする。

```toml
[packages.arch_specific]
aarch64 = ["some-arm-tool"]
x86_64  = ["some-x86-tool"]
```

---

## 11. デスクトップ GUI アプリ設計

### 11.1 アーキテクチャと技術スタック

CLIからの利用に加え、ネイティブなデスクトップアプリとして利用できる GUI モードを提供する。

- **対応OS**: macOS, Windows（Linuxは非サポート）
  - ※ 隔離された `home/` およびミニマルな Debian 環境の提供をコンセプトとするため、ローカルシェル（WSL や bash 等）へのフォールバック起動は廃止する。起動時に Docker または Podman がインストール・稼働していない場合は、ネイティブの警告ダイアログを表示してユーザーにインストールを促し、アプリケーションの実行を停止する。
- **設定永続化の仕組み**: 
  - `Eliterm.Config` モジュールを導入し、`~/.config/eliterm/eliterm.toml` への設定の読み書きを一元管理する。
  - アプリケーション起動時のウィンドウのサイズ（幅・高さ）および位置（X・Y座標）は `[gui.window]` セクションに自動的に永続化され、次回起動時に復元される。
- **技術スタック**:
  - `elixir-desktop`: Elixir プログラムを OS ネイティブのウィンドウアプリとして起動・パッケージングするフレームワーク
  - `Phoenix LiveView`: UI のレンダリングとバックエンドプロセス（Eliterm デーモン）とのリアルタイム通信
  - `xterm.js`: LiveView 内の WebView に描画されるターミナルエミュレータコンポーネント
  - ※ Windows環境においては、ネイティブメニューやウェブビュー全体の過剰なスケーリングによるアンチエイリアス（ぼやけ）を防ぐため、ランチャーにて `__COMPAT_LAYER=HighDpiAware` を設定して OS ネイティブの DPI スケーリングに準拠させている。
  - ※ Eliterm は cron ジョブ（Quantum）やセッション同期などのバックグラウンドタスクを継続させるため、**常駐アプリケーション（システムトレイ/メニューバー アプリ）**として動作する。
  - ※ ウィンドウの「×」ボタンや `exit` コマンドでターミナルを閉じた場合はアプリケーションを終了せず、ウィンドウを非表示にするだけとする。
  - ※ システムトレイやメニューバー（`Cmd+Q` / `Ctrl+Q`）から明示的に `Quit`（完全終了）が選択された場合、実行中のバックグラウンドセッションやcronジョブがすべて強制終了されるため、ユーザーに本当に終了するか確認するネイティブのダイアログ（`wxMessageDialog`、デフォルト「いいえ」選択）を表示し、確認された場合のみクリーンに終了（残存する `epmd.exe` をキルして `System.halt(0)`）する仕組みを備えている。

CLI 実行時と同じ `Eliterm.Application` のスーパーバイザーツリーを起動しつつ、CLI の代わりに GUI ウィンドウを表示（および常駐化）する構成とする。

### 11.2 UI コンポーネントとカラースキーム

- `xterm.js` を用いて、一般的なターミナルと同等の描画性能とキーボード入力処理を実現する。
- メニューバーはOSの標準的なアプリケーションのレイアウトに準拠する。
  - **Eliterm (App)**: `New Terminal`（新規ウィンドウ立ち上げ）や `Quit` などを配置する。
  - **Edit**: コピペ（Cmd+C/Cmd+V, Ctrl+C/Ctrl+V等）のOSネイティブ連携項目を配置し、GUIからシームレスに文字列操作ができるようにする。
  - **View**: メジャーなカラースキーム（Monokai, Solarized, Dracula, GitHub, Catppuccin など）のプリセットをワンクリックで選択・リアルタイム反映できる `Color Scheme` サブメニューや、ターミナルのフォントファミリーを動的に切り替えられる `Font` サブメニューを配置する。
  - ※ フォントメニューはOSごとに標準インストールされているターミナル向けフォントのみをデフォルト選択肢として表示する（例: Macは `Menlo`, `Monaco` 等、Windowsは `Consolas` 等）。
  - ※ ユーザーがサードパーティ製フォント（Fira Code, JetBrains Mono, Hack など）を利用できるよう、メニューに `Scan & update font list` 項目を配置する。これを実行するとシステムにインストールされている既知の開発者向けフォントをスキャンし、結果を `~/.config/eliterm/eliterm.toml` に永続化してメニューの選択肢に追加する。
  - ※ フォント未インストール時に明朝体などの意図しないフォントで描画されるのを防ぐため、指定されたフォントが存在しない場合でも常に `, monospace` をCSS側でフォールバックとして適用する。
  - ※ フォント変更時は、Webフォント等の読み込み遅延によるサイズ再計算のズレ（`vi`等での桁ずれ）を防ぐため、`document.fonts.ready` を待機してから `fitAddon.fit()` を実行し、直ちに `terminal_resize` イベントをバックエンドのPTYプロセスに送信する仕組みとする。
- `~/.config/eliterm/eliterm.toml` に `[gui.colors]` セクションを設け、ユーザーが任意の色（16色パレット、背景・文字色等）をカスタマイズできるようにする。
- 高度な描画カスタマイズ（GPUレンダリングや独自シェーダー等）を求めるユーザーには CLI 版（お気に入りのターミナルエミュレータ）の利用を推奨し、GUI 版は「開いてすぐ使える便利さ」を最優先する。
- OSネイティブのクリップボード（Cmd+C/Cmd+V, Ctrl+C/Ctrl+V）連携を実装し、GUI上でのシームレスな文字のコピー＆ペーストをサポートする。

### 11.3 ターミナル I/O の連携

1. `xterm.js` でのキーボード入力を LiveView の Hook 経由で Elixir に送信。
2. Elixir 側で `Eliterm.PTY.write/2` を呼び出し、bash / コンテナへ入力。
3. `Eliterm.PTY` からの出力データを LiveView の `push_event` 経由でブラウザ側に送信。
4. `xterm.js` の `write()` メソッドで描画。
5. **文字コード（エンコーディング）の固定**:
   - バックエンドが完全に Docker/Podman 上の Debian コンテナとして隔離・統一されているため、OSやローカル環境の差異に関わらず、フロントエンドとバックエンドの通信はすべて **UTF-8 (BOMなし)** に固定する。
   - GUI側で Shift-JIS や UTF-16 等へのエンコーディング切り替え機能は「あえて提供しない」仕様とする。もしコンテナ内から古いレガシーサーバーへSSH接続するなどして文字コード変換が必要になった場合は、フロントエンドのGUIで対応するのではなく、Linuxの標準的なベストプラクティスに従い、コンテナ側で `luit` や `tmux` 等のCUIツールを用いて変換を行うアプローチをユーザーに推奨する。

### 11.4 ウィンドウ管理とマルチプレクサ設計思想

- **タブ機能は実装しない**: Eliterm の GUI は「1ウィンドウ ＝ 1セッション」のシンプルな状態を維持し、GUI側に独自のタブ管理機能や画面分割機能は実装しない。
- **ターミナルマルチプレクサの推奨**: 画面の分割、タブ（ウィンドウ）管理、セッションの永続化などの高度な機能については、コンテナ内で動作する `tmux` や `zellij` の利用を強く推奨する。
- **設計の意図とマイグレーションとの親和性**: 
  - 複雑なタブ状態をGUI側で管理すると、クラッシュ時の全画面リロードや非表示要素に対するxterm.jsの再計算バグなどフロントエンドが肥大化する。
  - P2Pマイグレーション（PC間でのセッション移動）を実行した際、コンテナ内で `tmux` が動いていれば、分割されたペイン状態や履歴を含めてそのままの姿で別ノードへ移送可能となり、Eliterm のロケーション透過なアーキテクチャと完璧な相乗効果を発揮するため。

---

## 12. CLI 設計

### 11.1 コマンド体系

一覧表示は `list` サブコマンドに統一し、各対象への操作は `session` / `job` / `node` サブコマンドで行う。

```
eliterm
├── start                    セッション起動（デーモン未起動なら自動起動）
├── attach                   セッションにアタッチ
├── detach                   セッションをデタッチ
├── stop [--daemon]          セッション停止（--daemon でデーモン本体を停止）
├── migrate                  セッションを別ノードに移送
│
├── list
│   ├── nodes                クラスタのノード一覧
│   ├── sessions             セッション一覧（全ノード横断）
│   ├── jobs                 Quantum に登録されている全ジョブ定義
│   └── procs                実行中の cron ジョブ一覧
│
├── session
│   ├── rename               セッション名変更
│   └── info                 セッション詳細
│
├── job
│   ├── run                  ジョブを今すぐ手動実行
│   ├── disable              ジョブを一時停止
│   ├── enable               ジョブを再開
│   └── log                  ジョブの実行ログ表示
│
├── node
│   ├── info                 ノード詳細
│   └── ping                 ノードへの疎通確認
│
└── cluster
    ├── init                 クラスタを初期化（非起動時はローカル初期化）
    ├── join                 クラスタに参加（--cookie オプション対応）
    ├── leave                クラスタから離脱
    ├── rename               ノード接頭辞の変更
    └── info                 自ノードのノード名とクッキーの表示
```

### 11.2 コマンドリファレンス

#### デーモン管理

eliterm 本体（OTP アプリ）はバックグラウンドデーモンとして動作する。
`eliterm start` はデーモンが未起動なら自動的に起動してからセッションを作成する。

```bash
eliterm start [--headless] [--session <id>]
  # デーモンが未起動なら起動。bash + cron セッションを新規作成。
  # --headless は cron のみ（bash セッションなし）
  # デーモンはバックグラウンドで継続動作し、PID を ~/.config/eliterm/eliterm.pid に保存

eliterm stop [<session-id>]
  # session-id 指定: 指定セッションのみ停止
  # session-id 省略: 全セッションを停止。セッションがゼロになってもデーモンは継続

eliterm stop --daemon
  # デーモン本体を停止（全セッション強制終了）
```

#### セッション操作

```bash
eliterm attach [<session-id>]
  # 稼働中のセッションにアタッチ（session-id 省略時は唯一のセッションに接続）

eliterm detach
  # セッションをデタッチ（セッション・cron はバックグラウンドで継続）

eliterm migrate <node> [--session <id>] [--force-timeout <min>]
  # --session 指定: 指定セッションのみを移送
  # --session 省略: 全セッションを移送
```

#### 一覧表示

```bash
eliterm list nodes
  # クラスタのノード一覧（状態・OS・アーキテクチャ）

eliterm list sessions
  # 全ノードのセッション一覧（状態・起動時刻・所在ノード）

eliterm list jobs
  # Quantum に登録されている全ジョブ定義（スケジュール・有効/無効）

eliterm list procs
  # 現在実行中の cron ジョブ一覧（開始時刻・経過時間）
```

#### セッション管理

```bash
eliterm session rename <old-id> <new-id>
  # セッション名を変更

eliterm session info <session-id>
  # セッション詳細（cwd・env・スナップショット取得時刻等）
```

#### ジョブ管理

```bash
eliterm job run <job-name>
  # ジョブを今すぐ手動実行（スケジュールとは独立）

eliterm job disable <job-name>
  # ジョブを一時停止（定義は残す）

eliterm job enable <job-name>
  # 停止中のジョブを再開

eliterm job log <job-name> [--lines <n>]
  # ジョブの実行ログを表示（デフォルト: 最新20行）
```

#### ノード管理

```bash
eliterm node info <node>
  # ノード詳細（OS・アーキテクチャ・空きディスク・稼働時間）

eliterm node ping <node>
  # ノードへの疎通確認とレイテンシ計測
```

#### クラスタ管理

```bash
eliterm cluster init
  # クラスタを初期化（デーモン非起動時はローカルに直接クッキーを作成、既存クッキーあり時は再初期化確認プロンプトを表示。ホスト側だけでなくゲストコンテナ内からも実行可能）

eliterm cluster join <node> [--cookie <cookie>]
  # 既存クラスタに参加（--cookie 指定時はクッキーを設定ファイルに保存して動的適用）

eliterm cluster leave
  # クラスタから離脱

eliterm cluster rename <prefix>
  # 実行中のノード接頭辞を動的に変更し、eliterm.tomlに保存して永続化

eliterm cluster info
  # 自身のノード名とクラスタクッキー情報を表示
```

### 11.3 出力例

#### `eliterm list nodes`

```
$ eliterm list nodes

NODE                      状態        OS           ARCH      稼働時間
eliterm@my-laptop         ● このノード  macOS 15.2   aarch64   3時間
eliterm@home-server       ● オンライン  Linux 6.8    x86_64    12日
eliterm@vps               ● オンライン  Linux 6.8    x86_64    47日
```

#### `eliterm list sessions`

```
$ eliterm list sessions

SESSION      状態        所在ノード              起動       cron
session-1    RUNNING     eliterm@my-laptop      3時間前    2ジョブ稼働中
session-2    DETACHED    eliterm@home-server    1日前      1ジョブ稼働中
```

#### `eliterm list jobs`

```
$ eliterm list jobs

JOB           スケジュール    状態      前回実行     次回実行
backup        */5 * * * *    有効      2分前        3分後
cleanup       0 2 * * *      有効      22時間前     2時間後
report        0 9 * * 1      無効      -            -
```

#### `eliterm list procs`

```
$ eliterm list procs

JOB           開始時刻     経過時間   PID
backup.sh     12:34:01     00:00:43   18423
```

#### `eliterm node info <node>`

```
$ eliterm node info eliterm@home-server

ノード:       eliterm@home-server
状態:         オンライン
OS:           Linux 6.8.0 (Ubuntu 24.04)
アーキテクチャ: x86_64
eliterm:      v0.1.0
稼働時間:     12日 4時間
空きディスク:  48 GB / 200 GB
セッション数:  1
```

---

## 12. クラスタ構成

### 12.1 前提条件

マイグレート先ノードには以下が必要：

1. eliterm がインストール済みであること
2. `eliterm cluster join` で事前にクラスタを組んでいること
3. 同一クラスタ名・共有 cookie で認証されていること

### 12.2 クラスタ形成

```bash
# プライマリノード（最初の1台）
eliterm cluster init

# 追加ノード
eliterm cluster join eliterm@primary-node

# ノード一覧確認
eliterm list nodes

# 離脱
eliterm cluster leave
```

### 12.3 セキュリティ

- ノード間通信は TLS 暗号化（Erlang Distribution の TLS モード）
- クラスタ参加には共有シークレット（cookie）を要求
- mTLS は将来バージョンで対応

---

## 13. インストール設計

### 13.1 対応環境とフェーズ

| フェーズ | OS | アーキテクチャ | bash 調達元 |
|---|---|---|---|
| **v0.1** | Linux | x86_64 / aarch64 | システム標準（5.x） |
| **v0.1** | WSL | x86_64 | システム標準（Linux と同様） |
| **v0.2 以降** | macOS (Apple Silicon) | aarch64 | Debian VM 内（Virtualization.framework 経由） |
| **v0.2 以降** | macOS (Intel) | x86_64 | 同上 |

**macOS は v0.2 以降で対応する。**

v0.1 で macOS をサポートしない理由：
- macOS ホストの bash はデフォルト 3.2 であり、brew install bash が別途必要
- Virtualization.framework + Debian VM を使えば bash を含め環境が VM 内で完結し、macOS ホストを汚さない
- コアロジック（セッション・cron・マイグレーション）を Linux/WSL で先に固める方が実装効率がよい

v0.2 以降では macOS ホストへの bash インストールは不要。すべて Debian VM 内で完結する。

### 13.2 配布形式

- ERTS（Erlang VM）同梱の自己完結バイナリとして配布する
- ユーザー側に Elixir/Erlang のインストールは不要
- ExPTY は NIF のため、プリコンパイル済みバイナリを各プラットフォーム向けに同梱する
- インストール先は `~/.config/eliterm/bin/` であり、**システム領域への書き込みは行わない**
- `~/.bashrc` / `~/.zshrc` への PATH 追記のみ案内する（実行はユーザーの判断に委ねる）

---

## 14. 将来ロードマップ

### フェーズ別計画

| フェーズ | 主な対象 | 内容 |
|---|---|---|
| **v0.1** | Linux / WSL | コア機能（セッション・cron・マイグレーション） |
| **v0.2** | macOS 追加 | Virtualization.framework + Debian VM によるフル対応 |
| **v0.3** | 同期・自動化 | lsyncd によるリアルタイム同期・自動マイグレート |
| **v0.4** | アプリ管理 | Podman (rootless) によるパッケージ管理 |
| **v0.5** | GUI | Elixir Desktop によるデスクトップアプリ化 |
| **v0.6** | セキュリティ | 厳密な認証局（CA）によるTLS証明書認証のサポート |

### v0.2：macOS 対応

- Virtualization.framework 上で Debian slim VM を起動
- bash を含む実行環境がすべて VM 内で完結。macOS ホストを汚さない
- `home/` は VM に bind mount して共有
- macOS (Apple Silicon / Intel) 両対応

### v0.3：同期・自動化

- **lsyncd** によるノード間リアルタイム同期（常時差分同期でマイグレーション転送コストをほぼゼロに）
- 自動マイグレート：macOS は `NSWorkspace.willSleepNotification`、Linux は `systemd-inhibit` でスリープ直前にフック
- 指定ノードがオフラインになった場合の自動フェイルオーバー

### v0.4：アプリケーション管理

- `Eliterm.Container` 抽象レイヤーの実装
  - `Eliterm.Container.Podman`（Linux / WSL / macOS 25以下）
  - `Eliterm.Container.AppleContainer`（macOS 26以上）
- Debian slim コンテナイメージの管理
- `home/` のマウント（Podman: bind mount、Apple container: 自動共有）
- `home/.eliterm-apps` からの apt パッケージ自動インストール
- pip / npm グローバルパッケージのインストール対応
- アーキテクチャ別パッケージ指定（aarch64 / x86_64）の対応
- マイグレーション時の `eliterm-apps` 転送・再現

### v0.5：デスクトップ GUI（Elixir Desktop）

- **elixir-desktop** ライブラリによる Phoenix LiveView ベースのデスクトップアプリ化
- wxWidgets + LiveView でネイティブウィンドウを提供（Windows・macOS）
- **ビルド・配布アーキテクチャ**:
  - GitHub Actions にて CLI 版 (escript) と GUI 版 (OS ネイティブアプリ) の両方をビルド。
  - **macOS GUI**: `.app` バンドルを生成し、`.dmg` 形式で配布。
  - **Windows GUI**: ERTS 同梱のリリースビルドを生成し、起動用ランチャーを含めて `.zip` 形式で配布。
- CLI と同じバックエンドロジックを共有
- ghostty_ex（GenServer ベース PTY・VT パーサ）への移行も同時に検討

### v0.6：セキュリティ強化

- Erlang Distribution の TLS 設定において、自己署名証明書だけでなく、厳密な認証局（CA）を利用した証明書検証のサポート
- より高度なエンタープライズ・パブリックネットワーク環境での安全なノード間通信の実現

### v0.7：セルフアップデート機能 (Self-Update Feature)

- **自動アップデート機能 (`selfupdate` コマンド)**
  - GitHub Releases API (`https://api.github.com/repos/kh813/eliterm/releases/latest`) から最新リリースバージョンおよびアセット情報を取得。
  - 現在の実行バイナリのバージョンと最新タグを比較し、更新が必要な場合に適切なアセットをバックグラウンドダウンロードします。
  - **CLI (escript) の更新**: `bin/eliterm` バイナリを上書き更新します。
  - **SleepWatcher バイナリの自動同期**: escript CLI 実行時には runtime priv ディレクトリが存在しない制約があるため、`selfupdate` 実行時に `eliterm_sleep_watcher`（または `.exe`）も自動で取得して `~/.local/bin/` へインストール・配置します。
- **GUI の更新通知と統合**
  - アプリケーション起動時にバージョン確認を走り書きで行い、更新がある場合はダイアログを表示して新規 `.dmg` / `.zip` パッケージのダウンロードを案内します。

### SleepWatcher のバイナリ内蔵・配布方針

- **GUI パッケージにおける内蔵 (Built-in)**
  - GUI アプリケーションのリリース作成時（`scripts/package_mac_gui.sh` および `package_win_gui.ps1`）に、Swift / C# のソースコードから SleepWatcher バイナリを自動コンパイルして `priv/` フォルダへバンドルします。
  - これにより、GUI 版（`Eliterm-macOS.dmg` および `Eliterm-Windows.zip`）を利用する一般ユーザー側では、一切追加インストールを行う必要なく、SleepWatcher 機能が透過的（内蔵）に動作します。
- **CLI (escript) パッケージにおけるフォールバック**
  - escript には `priv/` ディレクトリが存在しないため、`Eliterm.SleepWatcher` はフォールバック先として `~/.local/bin/eliterm_sleep_watcher`（または `.exe`）を探します。
  - CLI ユーザー向けに、リリースページからスタンドアロンバイナリを個別ダウンロードして配置できるようにするほか、上記 `selfupdate` コマンドによって自動配置されるように設計します。

---

*eliterm_specs.md — Version 1.0 Draft*

## クリップボード・アーキテクチャ (Clipboard Architecture)
- セキュリティ・ブラウザ制限（Secure Context / ユーザー操作必須の制約）を完全に回避するため、Eliterm ではクリップボードの読み書きを主に **Elixir バックエンド経由** で行います。
- **アーキテクチャ詳細:**
  - `Eliterm.Clipboard` を単独の常駐 `GenServer` として実装し、プロセスを跨いだ安全な `wx_env` コンテキストを維持します。これにより LiveView プロセスからも `wxClipboard` の機能へ透過的にアクセス可能となります。
  - **macOS (Darwin) における制約回避:** macOS の `wxWebView` / `wxWidgets` 環境では、GUIのメインスレッド以外から `wxClipboard` を呼び出すと動作しない（または警告なく失敗する）制約があるため、macOS 環境に限り OS 標準の CLI ツールである `pbcopy` (ポート経由で標準入力に書き込み) および `pbpaste` (コマンド実行経由で取得) を使用してクリップボードを操作します。
  - OS ネイティブでメニュー（`wxMenuBar`）が `Cmd+C` などをキャッチした場合、一時的に OS のクリップボードがロックされる競合状態（Race Condition）を防ぐため、`Eliterm.Clipboard` の `wxWidgets` 処理内部に最大 500ms (10回) のリトライ機構を搭載しています。
  - **フロントエンドとメニューバーの連携:** macOS/Cocoa 等の環境下では、メニューバーのショートカットアクセラレータ（`\tCmd+C` 等）とブラウザのキーイベントが重複して発火し二重ペースト等が発生するため、キーボードによるショートカット `Cmd+C` / `Cmd+V`（および `Ctrl` キー相当）は `app.js` の `attachCustomKeyEventHandler` で排他的にフックして処理します。メニューバー (`lib/eliterm_web/menubar.ex`) にはアクセラレータを設定せず、マウスによるメニュー項目選択時のみ PubSub 経由で `app.js` 側へコピー・ペーストを要求する設計として、動作の整合性と一意性を保証しています。
  - **ペースト時のエスケープと背景色:** ペースト時は生の文字列をバックエンドへ送るのではなく、`xterm.js` の `this.term.paste(text)` API を経由させます。これにより Bracketed Paste Mode が有効なシェルに対して適切に `\x1b[200~` などのシーケンスが付与されます。しかし、bash 5.1以降などではこのモードによってペーストしたテキストが自動的にハイライト（背景色反転など）されてしまうため、`~/.bashrc` にて `bind 'set enable-active-region off'` を自動設定し、ターミナル背景色で正しく描画されるように対策しています。
