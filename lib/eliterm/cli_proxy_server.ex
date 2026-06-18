defmodule Eliterm.CLIProxyServer do
  @moduledoc """
  各セッションのホームディレクトリに Unix ドメインソケットを作成し、
  ゲストコンテナ内からの CLI コマンド要求を受信してホスト側の CLI として実行・中継する。
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    home_dir = Keyword.fetch!(opts, :home_dir)
    
    # ソケットファイルはホームディレクトリ配下（コンテナからマウントされている場所）に配置
    socket_path = Path.join(home_dir, ".eliterm-cli.sock")

    # 既存のソケットファイルを削除
    File.rm(socket_path)

    # Unix ドメインソケットの Listen
    # `:ifaddr` に `{:local, charlist}` を指定することで Unix ドメインソケットになる
    case :gen_tcp.listen(0, [:binary, active: false, packet: :line, ifaddr: {:local, String.to_charlist(socket_path)}]) do
      {:ok, listen_socket} ->
        # コンテナ内の一般ユーザーから読み書きできるようにパーミッションを設定
        File.chmod!(socket_path, 0o666)
        
        # 接続の受け入れループを開始
        send(self(), :accept)
        {:ok, %{listen_socket: listen_socket, socket_path: socket_path, session_id: session_id}}
      {:error, reason} ->
        Logger.error("Failed to listen on CLI proxy socket #{socket_path}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, state) do
    case :gen_tcp.accept(state.listen_socket, 1000) do
      {:ok, client_socket} ->
        # 別タスクで接続をハンドリング
        Task.start(fn -> handle_client(client_socket) end)
        send(self(), :accept)
        {:noreply, state}
      {:error, :timeout} ->
        send(self(), :accept)
        {:noreply, state}
      {:error, reason} ->
        Logger.error("CLI proxy socket accept error: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    File.rm(state.socket_path)
    :ok
  end

  # クライアント接続のハンドリング
  defp handle_client(socket) do
    # 1. 最初の行（引数の個数）を読み込む (packet: :line なので行単位で読み込める)
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        case Integer.parse(String.trim(line)) do
          {num_args, ""} ->
            # 2. パケットモードを raw に切り替えて、残りの引数データを読み込む
            :inet.setopts(socket, [packet: :raw])
            
            # 引数データを取得（引数はヌル文字で区切られている）
            args = read_args(socket, num_args, [])
            
            # 3. IOServer（I/Oサーバ）を起動
            {:ok, io_server} = Eliterm.IOServer.start_link(socket)
            
            # 4. 新しい Task で CLI の main/1 を実行し、グループリーダーを設定
            task = Task.async(fn ->
              Process.group_leader(self(), io_server)
              # CLIを実行
              Eliterm.CLI.main(args)
            end)
            
            # 実行完了を待つ
            Task.await(task, :infinity)
            
            # 終了処理
            GenServer.stop(io_server)
          _ ->
            :gen_tcp.send(socket, "Error: Invalid argument count\n")
        end
      {:error, _} ->
        :ok
    end
    :gen_tcp.close(socket)
  end

  defp read_args(_socket, 0, acc), do: Enum.reverse(acc)
  defp read_args(socket, count, acc) do
    case read_until_null(socket, "") do
      {:ok, arg} ->
        read_args(socket, count - 1, [arg | acc])
      {:error, _} ->
        Enum.reverse(acc)
    end
  end

  defp read_until_null(socket, acc) do
    case :gen_tcp.recv(socket, 1) do
      {:ok, <<0>>} -> {:ok, acc}
      {:ok, char} -> read_until_null(socket, acc <> char)
      error -> error
    end
  end
end
