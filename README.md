# Eliterm (Elixir Terminal)

Eliterm は、作業中のターミナルセッション、cronジョブ、および `home/` ディレクトリを別のPCやサーバーへそのまま移送（マイグレート）できる、ポータブルな分散ターミナル環境です。
「PCを閉じる（スリープさせる）と同時に作業状態をサーバーへ飛ばし、次に開いたときにそのまま再開する」といった次世代のワークフローを実現します。

## 特徴

- **セッション・マイグレート**: bash セッション（カレントディレクトリ、環境変数、コマンド履歴）をそのまま別ノードへ移送できます。
- **ポータブルな cron ジョブ**: 各セッションに紐づく cron ジョブも移送され、移動先で自動的にスケジュール実行が引き継がれます。
- **データ・環境の持ち運び**: `home/` ディレクトリ内のスクリプト群や設定、Docker/Podman コンテナを利用した独立環境をまるごとコピーします。
- **OS スリープ検知と自動退避**: Mac や Windows のスリープ（PCを閉じたタイミング）を自動検知し、安全にセッションをサーバーへ退避させます。
- **一般ユーザー権限で動作**: `root` や `sudo` 権限は一切不要です（コンテナ実行時はOS側の権限設定に依存します）。

---

## インストール

Eliterm は、手軽に使える **デスクトップ GUI 版** と、CUI 環境で動作する **CLI 版** の両方を提供しています。通常は GUI 版のご利用をおすすめします。

### 【推奨】デスクトップ GUI 版のインストール

#### macOS

1. [Releases ページ](https://github.com/kh813/eliterm/releases/latest) から `Eliterm-macOS.dmg` をダウンロードします。
2. ダウンロードしたファイルを開き、中にある `Eliterm.app` を `アプリケーション` (`/Applications`) フォルダへドラッグ＆ドロップします。
3. `アプリケーション` フォルダから `Eliterm` をダブルクリックして起動します。

#### Windows

1. [Releases ページ](https://github.com/kh813/eliterm/releases/latest) から `Eliterm-Windows.zip` をダウンロードします。
2. ダウンロードした ZIP ファイルを展開し、任意のフォルダに保存します。
3. 展開したフォルダ内の `Eliterm.exe` をダブルクリックして起動します。

---

### CLI 版のインストール (Linux / ターミナル向け)

GUIを必要としないサーバー環境や、カスタマイズ性の高いターミナル環境を好む方向けです。事前に [Elixir (v1.15以上)](https://elixir-lang.org/install.html) が必要です。

**macOS / Linux:**
```bash
curl -fL -o eliterm.zip https://github.com/kh813/eliterm/archive/refs/heads/main.zip
unzip eliterm.zip
cd eliterm-main
./install.sh
```

**Windows (PowerShell):**
```powershell
curl.exe -fL -o eliterm.zip https://github.com/kh813/eliterm/archive/refs/heads/main.zip
Expand-Archive -Path "eliterm.zip" -DestinationPath "."
cd eliterm-main
.\install.ps1
```
> **注意**: 実行すると `bin/eliterm` (escript) が生成されます。必要に応じて PATH を通してください。


---

## 初期セットアップ（クラスタの構築）

Eliterm は複数台の端末間（自分のPCとサーバーなど）でクラスタを組むことで真価を発揮します。クラスタ間は Erlang 分散通信の仕組みを用い、共通の「Cookie（認証キー）」と固有の「ノード名」で相互接続します。

### Step 1: 1台目（例: サーバー側）での初期化と確認

1. **クラスタを初期化します**
   ```bash
   bin/eliterm cluster init
   ```
   これにより、クラスタ接続用のランダムな Cookie が生成され、ノードが起動します。すでに初期化済みの場合は、本当に再初期化するかを確認するプロンプトが表示されます。

2. **接続情報を確認します**
   ```bash
   bin/eliterm cluster info
   ```
   出力例：
   ```
   Node: eliterm@server-host
   Cookie: AVERYSECRETRANDOMCOOKIEVALUE...
   ```
   ここに表示される `Node` 名（例: `eliterm@server-host`）と `Cookie` の値を、2台目の接続の際に使用します。

### Step 2: 2台目（例: 手元のノートPC側）での参加

2台目のPCから、1台目のサーバーに向けて Cookie を指定して参加リクエストを送ります。

```bash
bin/eliterm cluster join <1台目のNode名> --cookie <1台目のCookie値>
```

**実行例:**
```bash
bin/eliterm cluster join eliterm@server-host --cookie AVERYSECRETRANDOMCOOKIEVALUE...
```
これにより、2台目のPCにも同じ Cookie が永続化され、自動的にクラスタへ参加します。

### (オプション) ノード名の変更
デフォルトではノード名は `eliterm@<ホスト名>` となります。もし変更したい場合は、以下のコマンドで接頭辞を変更できます。

```bash
bin/eliterm cluster rename <新しい接頭辞>
```
**実行例:**
```bash
bin/eliterm cluster rename mylaptop
# ノード名が mylaptop@<ホスト名> に変更されます
```

---

## 基本的な使い方

### 1. セッションの開始とアタッチ
```bash
# セッションを起動し、バックグラウンドデーモンを立ち上げる
bin/eliterm start

# 起動したセッション（bash）にアタッチして操作する
bin/eliterm attach
```
アタッチすると、通常のターミナルのように操作できます。作業を中断したい場合は、通常の `Ctrl-d` などでデタッチします。

### 2. セッションのマイグレート（移送）
現在のノードで動いているセッションとデータを、別のノードへ移送します。
```bash
bin/eliterm migrate eliterm@<ターゲットノード名>
```
実行すると、データの同期、セッション状態のスナップショット作成が行われ、移送先で即座に処理が再開されます。

### 3. スリープ検知の自動マイグレート設定
PCがスリープした際に自動でセッションを逃すには、以下のコマンドでターゲットノードを登録します。
```bash
bin/eliterm config auto-migrate eliterm@<ターゲットノード名>
```
この設定をしておくと、Mac で画面を閉じたり、Windows がスリープに入った瞬間に、自動的に指定ノードへマイグレーションが行われます。

### 4. ジョブとノードの確認
```bash
# 現在のクラスタに接続されているノード一覧
bin/eliterm list nodes

# アクティブなセッション一覧
bin/eliterm list sessions

# 登録されている cron ジョブ一覧
bin/eliterm list jobs
```

---

## 開発環境とアーキテクチャ

- **言語**: Elixir (OTP)
- **分散処理**: Horde / libcluster
- **スリープ監視**: Swift (macOS) / C# (Windows) のネイティブヘルパーを GitHub Actions で事前コンパイル

## ライセンス

[MIT License](LICENSE)
