#!/bin/bash
# test_docker_cluster.sh
# 複数の Docker コンテナを起動し、E2E のクラスタ機能（init / invite / join via token）をテストするスクリプト

set -e

# Cleanup handler on exit
cleanup() {
  echo "Cleaning up containers and network..."
  # Dump logs on failure/exit if containers exist and were running
  if docker ps -a --format '{{.Names}}' | grep -q "eliterm-primary"; then
    echo "=== eliterm-primary logs ==="
    docker logs eliterm-primary || true
  fi
  if docker ps -a --format '{{.Names}}' | grep -q "eliterm-member"; then
    echo "=== eliterm-member logs ==="
    docker logs eliterm-member || true
  fi
  docker rm -f eliterm-primary eliterm-member >/dev/null 2>&1 || true
  docker network rm eliterm-net >/dev/null 2>&1 || true
  # 一時データの削除
  rm -rf .eliterm_test_primary .eliterm_test_member
}
trap cleanup EXIT

# 1. 準備
cleanup

echo "=== Preparing test environments ==="
# ホスト側で最新コードをコンパイルし、escript をビルド
mix compile
mix escript.build

# テスト用ネットワーク作成
docker network create eliterm-net

# テスト用データディレクトリの作成（コンテナごとのデータ隔離）
mkdir -p .eliterm_test_primary
mkdir -p .eliterm_test_member

# 2. プライマリコンテナの起動
echo "=== Starting Primary node (eliterm-primary) ==="
docker run -d \
  --name eliterm-primary \
  --hostname eliterm-primary \
  --network eliterm-net \
  -v "$(pwd)":/app \
  -v "$(pwd)/.eliterm_test_primary":/root/.eliterm \
  -e ELITERM_DATA_DIR=/root/.eliterm \
  -e ELITERM_HEADLESS=true \
  -e MIX_BUILD_PATH=/tmp/_build \
  -w /app \
  elixir:latest \
  sh -c "mix local.hex --force && mix local.rebar --force && elixir --erl \"-eliterm start_gui false -eliterm check_dependencies false -eliterm start_sleep_watcher false\" --sname primary -S mix run --no-halt"

# 3. メンバーコンテナの起動
echo "=== Starting Member node (eliterm-member) ==="
docker run -d \
  --name eliterm-member \
  --hostname eliterm-member \
  --network eliterm-net \
  -v "$(pwd)":/app \
  -v "$(pwd)/.eliterm_test_member":/root/.eliterm \
  -e ELITERM_DATA_DIR=/root/.eliterm \
  -e ELITERM_HEADLESS=true \
  -e MIX_BUILD_PATH=/tmp/_build \
  -w /app \
  elixir:latest \
  sh -c "mix local.hex --force && mix local.rebar --force && elixir --erl \"-eliterm start_gui false -eliterm check_dependencies false -eliterm start_sleep_watcher false\" --sname member -S mix run --no-halt"


# デーモンの起動待機（Eliterm アプリが起動完了するまで待つ）
echo "Waiting for primary daemon to compile and start..."
DAEMON_UP=false
for i in {1..60}; do
  if docker exec -e MIX_BUILD_PATH=/tmp/_build -e ELITERM_HEADLESS=true eliterm-primary elixir --sname test_ping -e "
    if Node.connect(:'primary@eliterm-primary') do
      apps = :rpc.call(:'primary@eliterm-primary', Application, :started_applications, [])
      if is_list(apps) and Keyword.has_key?(apps, :eliterm) do
        IO.puts(\"ALIVE\")
      end
    end
  " 2>/dev/null | grep -q "ALIVE"; then
    echo "Primary daemon is up!"
    DAEMON_UP=true
    break
  fi
  echo -n "."
  sleep 2
done
echo ""

if [ "$DAEMON_UP" = false ]; then
  echo "ERROR: Primary daemon did not start within timeout."
  exit 1
fi

# 4. プライマリクラスター初期化
echo "=== Initializing cluster on primary ==="
docker exec -e ELITERM_DATA_DIR=/root/.eliterm -e ELITERM_HEADLESS=true eliterm-primary bin/eliterm --node primary@eliterm-primary cluster init my-cluster

# 確認
echo "Primary cluster info:"
docker exec -e ELITERM_DATA_DIR=/root/.eliterm -e ELITERM_HEADLESS=true eliterm-primary bin/eliterm --node primary@eliterm-primary cluster info

# 5. プライマリで招待トークンを発行およびポート取得
echo "=== Generating invite token and getting port on primary ==="
# デーモンと通信する一時ノードを起動し、RPC でトークンと HTTP ポートを取得する
# クラスター初期化によりクッキーが変更されているため、ファイルを読み込んで Node.set_cookie にセットする
INFO_OUT=$(docker exec -e ELITERM_HEADLESS=true eliterm-primary elixir --sname token_gen -e "
  cookie = File.read!(\"/root/.eliterm/cookie\") |> String.trim() |> String.to_atom()
  Node.set_cookie(cookie)
  Node.connect(:'primary@eliterm-primary')
  {:ok, token, _} = :rpc.call(:'primary@eliterm-primary', Eliterm.Cluster, :invite, [])
  port = :rpc.call(:'primary@eliterm-primary', Application, :get_env, [:eliterm, ElitermWeb.Endpoint])
         |> Keyword.get(:http)
         |> Keyword.get(:port)
  IO.puts(\"#{token} #{port}\")

")
TOKEN=$(echo "$INFO_OUT" | tail -n 1 | awk '{print $1}')
PORT=$(echo "$INFO_OUT" | tail -n 1 | awk '{print $2}')
echo "Generated token: $TOKEN"
echo "Primary HTTP port: $PORT"

# 6. メンバーノードがトークンを使って参加 (Join)
echo "=== Joining cluster from member node ==="
docker exec -e ELITERM_DATA_DIR=/root/.eliterm -e ELITERM_HEADLESS=true eliterm-member bin/eliterm --node member@eliterm-member cluster join primary@eliterm-primary --token "$TOKEN" --port "$PORT"


# 接続待機
sleep 3

# 7. 接続確認
echo "=== Verifying cluster connection ==="
NODES_OUT=$(docker exec -e ELITERM_DATA_DIR=/root/.eliterm -e ELITERM_HEADLESS=true eliterm-primary bin/eliterm --node primary@eliterm-primary list nodes)
echo "$NODES_OUT"

# 接続が確立されていれば、Node.list() に相手が含まれているはず
if echo "$NODES_OUT" | grep -q "member@eliterm-member"; then
  echo "SUCCESS: Cluster join test passed! Nodes are successfully connected."
else
  echo "FAILED: Member node is not in the primary's node list."
  exit 1
fi
