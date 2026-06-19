#!/bin/bash
set -e

# Setup isolated data directory
export ELITERM_DATA_DIR="$(pwd)/.eliterm_test_e2e"
rm -rf "$ELITERM_DATA_DIR"
mkdir -p "$ELITERM_DATA_DIR"

cleanup() {
  echo "Cleaning up nodes..."
  kill $NODE1_PID >/dev/null 2>&1 || true
  kill $NODE2_PID >/dev/null 2>&1 || true
  rm -rf "$ELITERM_DATA_DIR" node1.log node2.log
}
trap cleanup EXIT

# Compile latest
mix compile
mix escript.build

# Start node1
elixir --sname node1 -S mix run --no-halt > node1.log 2>&1 &
NODE1_PID=$!

# Start node2
elixir --sname node2 -S mix run --no-halt > node2.log 2>&1 &
NODE2_PID=$!

sleep 4

HOST=$(hostname -s)
CLI="bin/eliterm"

echo "=== Nodes ==="
$CLI --node node1@$HOST list nodes

echo "=== Starting Session on node1 ==="
$CLI --node node1@$HOST start test_session_1

sleep 2
echo "=== Migrating Session to node2 ==="
$CLI --node node1@$HOST migrate test_session_1 node2@$HOST

sleep 2
echo "=== Sessions on node2 ==="
$CLI --node node2@$HOST list sessions

echo "E2E Test Completed!"

