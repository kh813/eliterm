defmodule Eliterm.Cluster do
  @moduledoc """
  クラスタの初期化、参加、離脱、ノード情報取得などのコアロジックを担当するモジュール。
  """
  require Logger

  @eliterm_dir Eliterm.base_dir()

  def init(prefix \\ nil) do
    cookie_path = Path.join(@eliterm_dir, "cookie")
    if File.exists?(cookie_path) do
      {:error, :already_initialized}
    else
      Eliterm.Config.put(["cluster", "role"], "primary")

      # Determine the node prefix
      node_prefix = if prefix && is_binary(prefix) && String.trim(prefix) != "" do
        Eliterm.Config.put(["cluster", "node_prefix"], prefix)
        prefix
      else
        Eliterm.Config.get(["cluster", "node_prefix"], "eliterm")
      end

      # Track if the node was already alive before starting distribution
      was_alive = Node.alive?()

      # Start Erlang distribution if not already running
      unless was_alive do
        short_host = Eliterm.local_host()
        node_name = String.to_atom("#{node_prefix}@#{short_host}")
        case Node.start(node_name, :shortnames) do
          {:ok, _} -> Logger.info("Started Erlang distribution as #{node_name}")
          {:error, reason} -> Logger.error("Failed to start Erlang distribution: #{inspect(reason)}")
        end
      end

      # If distribution was already alive and a new prefix is supplied, dynamically rename
      if was_alive && prefix && is_binary(prefix) && String.trim(prefix) != "" do
        rename(prefix)
      end

      File.mkdir_p!(@eliterm_dir)
      # ランダムなクッキーを生成
      cookie = :crypto.strong_rand_bytes(24) |> Base.url_encode64()
      File.write!(cookie_path, cookie)
      File.chmod!(cookie_path, 0o600)
      Logger.info("Generated new cluster cookie at #{cookie_path}")

      if Node.alive?() do
        Node.set_cookie(String.to_atom(File.read!(cookie_path)))
      end

      Logger.info("Cluster initialized.")
      broadcast_state_change()
      :ok
    end
  end

  def join(node_name, cookie_or_token \\ nil, role \\ "member", port \\ 4000) do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    if File.exists?(cookie_path) do
      {:error, :already_initialized}
    else
      role_str = if role in ["secondary", "member"], do: role, else: "member"

      # Start Erlang distribution if not already running
      unless Node.alive?() do
        prefix = Eliterm.Config.get(["cluster", "node_prefix"], "eliterm")
        short_host = Eliterm.local_host()
        my_node_name = String.to_atom("#{prefix}@#{short_host}")
        case Node.start(my_node_name, :shortnames) do
          {:ok, _} -> Logger.info("Started Erlang distribution as #{my_node_name} for joining")
          {:error, reason} -> Logger.error("Failed to start Erlang distribution for joining: #{inspect(reason)}")
        end
      end

      if token?(cookie_or_token) do
        join_with_token(node_name, cookie_or_token, role_str, port)
      else
        join_with_cookie(node_name, cookie_or_token, role_str)
      end
    end
  end

  defp token?(string) when is_binary(string) do
    String.match?(string, ~r/^\d{3}-\d{3}$/)
  end
  defp token?(_), do: false

  defp join_with_cookie(node_name, cookie, role_str) do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    node_atom = if is_binary(node_name), do: String.to_atom(node_name), else: node_name

    if cookie do
      cookie_atom = if is_binary(cookie), do: String.to_atom(cookie), else: cookie
      if Node.alive?() do
        Node.set_cookie(cookie_atom)
      end

      File.write!(cookie_path, to_string(cookie))
      File.chmod!(cookie_path, 0o600)
      Logger.info("Persisted new cluster cookie from join command.")
    end

    case Node.connect(node_atom) do
      true ->
        Eliterm.Config.put(["cluster", "role"], role_str)
        Logger.info("Successfully joined node: #{node_atom} as #{role_str}")
        broadcast_state_change()
        :ok
      false ->
        Logger.error("Failed to join node: #{node_atom}")
        {:error, :connect_failed}
      :ignored ->
        Logger.error("Local node is not alive")
        {:error, :ignored}
    end
  end

  defp join_with_token(node_name, token, role_str, port) do
    node_str = to_string(node_name)
    [prefix, host_with_port] = case String.split(node_str, "@") do
      [p, h] -> [p, h]
      _ -> [node_str, "localhost"]
    end

    {host, port} = case String.split(host_with_port, ":") do
      [h, p_str] -> {h, String.to_integer(p_str)}
      _ -> {host_with_port, port}
    end

    # Generate temporary asymmetric keys
    {private_key, public_key_der} = Eliterm.Crypto.generate_keypair()
    public_key_base64 = Base.url_encode64(public_key_der)

    # API Request configuration
    url = "http://#{host}:#{port}/api/cluster/join"
    headers = [{~c"content-type", ~c"application/json"}]
    body_map = %{
      "token" => token,
      "node_name" => to_string(Node.self()),
      "public_key" => public_key_base64
    }

    # Ensure httpc is started
    :inets.start()
    :ssl.start()

    case :httpc.request(:post, {to_charlist(url), headers, ~c"application/json", to_charlist(Jason.encode!(body_map))}, [], []) do
      {:ok, {{_version, 200, _msg}, _headers, response_body}} ->
        case Jason.decode!(to_string(response_body)) do
          %{"status" => "ok", "cookie" => encrypted_cookie_base64} ->
            cookie = Eliterm.Crypto.decrypt_cookie(encrypted_cookie_base64, private_key)
            cookie_path = Path.join(Eliterm.base_dir(), "cookie")
            
            if Node.alive?() do
              Node.set_cookie(String.to_atom(cookie))
            end
            File.write!(cookie_path, cookie)
            File.chmod!(cookie_path, 0o600)
            Logger.info("Persisted new cluster cookie decrypted from token response.")

            # Connect distribution
            node_atom = String.to_atom("#{prefix}@#{host}")
            case Node.connect(node_atom) do
              true ->
                Eliterm.Config.put(["cluster", "role"], role_str)
                Eliterm.Config.put(["cluster", "node_prefix"], prefix)
                Logger.info("Successfully joined node: #{node_atom} as #{role_str} using token.")
                broadcast_state_change()
                :ok
              false ->
                Logger.error("Failed to connect to primary node: #{node_atom} after decrypting cookie.")
                {:error, :connect_failed}
              :ignored ->
                Logger.error("Local node is not alive to join using token: #{node_atom}")
                {:error, :ignored}
            end
          
          other ->
            Logger.error("API response status was not ok: #{inspect(other)}")
            {:error, :api_error}
        end

      {:ok, {{_version, status, _msg}, _headers, response_body}} ->
        Logger.error("API request failed with status #{status}: #{response_body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("HTTP request to #{url} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def reset do
    if not primary?() do
      {:error, :not_allowed_on_secondary}
    else
      # 自分が primary の場合のみ、接続されている他ノードを leave させる (Cascade Leave)
      if primary?() and Node.alive?() do
        other_nodes = Node.list()
        for node <- other_nodes do
          Logger.info("Remote signaling leave to node: #{node}")
          :rpc.cast(node, __MODULE__, :leave, [])
        end
      end

      cookie_path = Path.join(Eliterm.base_dir(), "cookie")
      if File.exists?(cookie_path) do
        File.rm!(cookie_path)
      end

      Eliterm.Config.put(["cluster", "node_prefix"], "eliterm")
      Eliterm.Config.put(["cluster", "role"], "primary")

      if Node.alive?() do
        Node.stop()

        short_host = Eliterm.local_host()
        default_node_name = String.to_atom("eliterm@#{short_host}")

        case Node.start(default_node_name, :shortnames) do
          {:ok, _} ->
            Logger.info("Reset distribution and restarted as default node: #{default_node_name}")
          {:error, reason} ->
            Logger.error("Failed to restart default distribution after reset: #{inspect(reason)}")
        end
      end

      Logger.info("Cluster reset successfully. Cookie file removed and configuration restored to default.")
      broadcast_state_change()
      :ok
    end
  end

  def leave do
    case Node.stop() do
      {:error, _} -> Logger.warning("Failed to stop distribution")
      _ -> Logger.info("Left cluster")
    end

    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    if File.exists?(cookie_path) do
      File.rm!(cookie_path)
    end
    Eliterm.Config.put(["cluster", "role"], "primary")
    broadcast_state_change()
    :ok
  end

  def rename(new_prefix) when is_binary(new_prefix) do
    if not primary?() do
      {:error, :not_allowed_on_secondary}
    else
      Eliterm.Config.put(["cluster", "node_prefix"], new_prefix)
      Logger.info("Saved new node prefix: #{new_prefix}")

      if Node.alive?() do
        Node.stop()

        short_host = Eliterm.local_host()
        node_name = String.to_atom("#{new_prefix}@#{short_host}")

        case Node.start(node_name, :shortnames) do
          {:ok, _} ->
            cookie_path = Path.join(Eliterm.base_dir(), "cookie")
            if File.exists?(cookie_path) do
              Node.set_cookie(String.to_atom(File.read!(cookie_path)))
            end
            Logger.info("Dynamically renamed node and restarted distribution as #{node_name}")
            broadcast_state_change()
            {:ok, node_name}
          {:error, reason} ->
            Logger.error("Failed to restart distribution with new name: #{inspect(reason)}")
            {:error, reason}
        end
      else
        Logger.info("Node is not running in distributed mode. Node prefix saved to config.")
        broadcast_state_change()
        :ok
      end
    end
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

  def info do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    cookie = if File.exists?(cookie_path), do: File.read!(cookie_path), else: "not_initialized"

    node_name = if Node.alive?() and Node.self() != :nonode@nohost and not String.starts_with?(to_string(Node.self()), "cli_") do
      Node.self()
    else
      # If distribution is not alive or we are running on a temporary CLI node, build the expected join name
      prefix = Eliterm.Config.get(["cluster", "node_prefix"], "eliterm")
      short_host = Eliterm.local_host()
      String.to_atom("#{prefix}@#{short_host}")
    end

    # Extract prefix and host from full node name (e.g. prefix@host)
    node_str = to_string(node_name)
    [prefix, host] = case String.split(node_str, "@") do
      [p, h] -> [p, h]
      _ -> [node_str, "localhost"]
    end

    %{
      cluster_name: prefix,
      node: host,
      full_node: node_name,
      cookie: cookie
    }
  end

  def primary? do
    Eliterm.Config.get(["cluster", "role"], "primary") == "primary"
  end

  def admin? do
    role = Eliterm.Config.get(["cluster", "role"], "primary")
    role in ["primary", "secondary"]
  end

  def invite do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    if File.exists?(cookie_path) do
      Eliterm.ClusterManager.start_invite()
    else
      {:error, :not_initialized}
    end
  end

  def cancel_invite do
    Eliterm.ClusterManager.cancel_invite()
  end

  def verify_and_use_token(token, public_key_der) do
    Eliterm.ClusterManager.verify_and_use_token(token, public_key_der)
  end

  def get_invite_status do
    Eliterm.ClusterManager.get_invite_status()
  end

  defp broadcast_state_change do
    if Process.whereis(Eliterm.PubSub) do
      Phoenix.PubSub.broadcast(Eliterm.PubSub, "cluster", :cluster_state_changed)
    else
      :ok
    end
  end
end
