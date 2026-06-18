defmodule Eliterm.CLIProxyServer do
  @moduledoc """
  各セッションで一時的な TCP ポートを開いて待ち受け、
  ゲストコンテナ内からの CLI コマンド要求をトークン認証付きで受信し、
  ホスト側の CLI として実行・中継する。
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
    
    port_path = Path.join(home_dir, ".eliterm-cli.port")

    # 既存のポートファイルを削除
    File.rm(port_path)

    # 0.0.0.0 で空きポートを TCP Listen
    case :gen_tcp.listen(0, [:binary, active: false, packet: :line, ip: {0, 0, 0, 0}, reuseaddr: true]) do
      {:ok, listen_socket} ->
        {:ok, port} = :inet.port(listen_socket)
        # セキュアなワンタイムトークンを生成
        token = :crypto.strong_rand_bytes(16) |> Base.encode16()

        # ポートとトークンを共有ディレクトリ内のファイルに保存
        File.write!(port_path, "#{port}\n#{token}")
        File.chmod!(port_path, 0o600)
        
        # 接続の受け入れループを開始
        send(self(), :accept)
        {:ok, %{listen_socket: listen_socket, port_path: port_path, token: token, session_id: session_id}}
      {:error, reason} ->
        Logger.error("Failed to listen on CLI proxy TCP socket: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, state) do
    case :gen_tcp.accept(state.listen_socket, 1000) do
      {:ok, client_socket} ->
        # 別タスクで接続をハンドリング
        token = state.token
        Task.start(fn -> handle_client(client_socket, token) end)
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
    File.rm(state.port_path)
    :ok
  end

  # クライアント接続のハンドリング
  defp handle_client(socket, expected_token) do
    # 1. 最初の行（トークン）を読み込む
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        token = String.trim(line)
        if token == expected_token do
          # 2. 次の行（引数の個数）を読み込む
          case :gen_tcp.recv(socket, 0) do
            {:ok, line2} ->
              case Integer.parse(String.trim(line2)) do
                {num_args, ""} ->
                  # パケットモードを raw に切り替えて、残りの引数データを読み込む
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
        else
          Logger.warning("CLI proxy socket received unauthorized connection attempt")
          :gen_tcp.send(socket, "Error: Unauthorized CLI connection\n")
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
