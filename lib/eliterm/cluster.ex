defmodule Eliterm.Cluster do
  @moduledoc """
  クラスタの初期化、参加、離脱、ノード情報取得などのコアロジックを担当するモジュール。
  """
  require Logger

  @eliterm_dir Eliterm.base_dir()

  def init do
    File.mkdir_p!(@eliterm_dir)
    cookie_path = Path.join(@eliterm_dir, "cookie")

    unless File.exists?(cookie_path) do
      # ランダムなクッキーを生成
      cookie = :crypto.strong_rand_bytes(24) |> Base.url_encode64()
      File.write!(cookie_path, cookie)
      File.chmod!(cookie_path, 0o600)
      Logger.info("Generated new cluster cookie at #{cookie_path}")
    end

    if Node.alive?() do
      Node.set_cookie(String.to_atom(File.read!(cookie_path)))
    end

    # NOTE: 将来的に自己署名TLS証明書を自動生成するロジックをここに追加する。
    Logger.info("Cluster initialized.")
    :ok
  end

  def join(node_name) do
    node_atom = if is_binary(node_name), do: String.to_atom(node_name), else: node_name
    case Node.connect(node_atom) do
      true ->
        Logger.info("Successfully joined node: #{node_atom}")
        :ok
      false ->
        Logger.error("Failed to join node: #{node_atom}")
        {:error, :connect_failed}
      :ignored ->
        Logger.error("Local node is not alive")
        {:error, :ignored}
    end
  end

  def leave do
    case Node.stop() do
      {:error, _} -> Logger.warning("Failed to stop distribution")
      _ -> Logger.info("Left cluster")
    end
    :ok
  end

  def list_nodes do
    [Node.self() | Node.list()]
  end

  def node_info(node) do
    node_atom = if is_binary(node), do: String.to_atom(node), else: node
    if node_atom == Node.self() do
      do_node_info()
    else
      :rpc.call(node_atom, __MODULE__, :do_node_info, [])
    end
  end

  @doc false
  def do_node_info do
    {os_family, os_name} = :os.type()
    arch = :erlang.system_info(:system_architecture)
    {uptime, _} = :erlang.statistics(:wall_clock)
    %{
      node: Node.self(),
      os: "#{os_family}/#{os_name}",
      architecture: to_string(arch),
      uptime_ms: uptime
    }
  end

  def ping(node) do
    node_atom = if is_binary(node), do: String.to_atom(node), else: node
    start_time = System.monotonic_time(:millisecond)
    case Node.ping(node_atom) do
      :pong ->
        end_time = System.monotonic_time(:millisecond)
        {:ok, end_time - start_time}
      :pang ->
        {:error, :pang}
    end
  end
end
