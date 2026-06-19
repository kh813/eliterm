defmodule Eliterm.CLI do
  @moduledoc """
  eliterm コマンドラインクライアントのエントリポイント。
  escript としてビルドされ、バックグラウンドの eliterm デーモンに RPC リクエストを送信する。
  """

  def main(args) do
    {opts, command, _} = OptionParser.parse(args, switches: [node: :string, cookie: :string, role: :string, token: :string, port: :integer])

    short_host = Eliterm.local_host()
    client_name = String.to_atom("cli_#{:rand.uniform(10000)}@#{short_host}")
    case Node.start(client_name, :shortnames) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} ->
        unless Node.alive?() do
          IO.puts(:stderr, "Failed to start Node: #{inspect(reason)}")
        end
    end

    cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
    if File.exists?(cookie_path) do
      Node.set_cookie(String.to_atom(File.read!(cookie_path)))
    end

    daemon_node = if opts[:node] do
      String.to_atom(opts[:node])
    else
      prefix = Eliterm.Config.get(["cluster", "node_prefix"], "eliterm")
      String.to_atom("#{prefix}@#{short_host}")
    end

    case command do
      ["cluster", "init" | rest] -> 
        cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
        if File.exists?(cookie_path) do
          IO.puts(:stderr, "Error: Cluster is already initialized. Please run 'eliterm cluster reset' first.")
          System.halt(1)
        else
          prefix = List.first(rest)
          execute_rpc(daemon_node, Eliterm.Cluster, :init, [prefix])
        end
      ["cluster", "join", target] -> 
        cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
        if File.exists?(cookie_path) do
          IO.puts(:stderr, "Error: Cluster is already initialized. Please run 'eliterm cluster reset' first.")
          System.halt(1)
        else
          role = opts[:role] || "member"
          cookie_or_token = opts[:cookie] || opts[:token]
          port = opts[:port] || 4000
          execute_rpc(daemon_node, Eliterm.Cluster, :join, [target, cookie_or_token, role, port])
        end
      ["cluster", "invite"] ->
        cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
        if not File.exists?(cookie_path) do
          IO.puts(:stderr, "Error: Cluster is not initialized. Please run 'eliterm cluster init' first.")
          System.halt(1)
        else
          execute_rpc(daemon_node, Eliterm.Cluster, :invite, [])
        end
      ["cluster", "token"] ->
        cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
        if not File.exists?(cookie_path) do
          IO.puts(:stderr, "Error: Cluster is not initialized. Please run 'eliterm cluster init' first.")
          System.halt(1)
        else
          execute_rpc(daemon_node, Eliterm.Cluster, :invite, [])
        end
      ["cluster", "reset"] -> 
        if confirm_reset?(daemon_node) do
          execute_rpc(daemon_node, Eliterm.Cluster, :reset, [])
        else
          IO.puts "Aborted."
        end
      ["cluster", "leave"] -> 
        execute_rpc(daemon_node, Eliterm.Cluster, :leave, [])
      ["cluster", "rename", prefix] ->
        execute_rpc(daemon_node, Eliterm.Cluster, :rename, [prefix])
      ["cluster", "info"] ->
        execute_rpc(daemon_node, Eliterm.Cluster, :info, [])
      ["list", "nodes"] -> 
        execute_rpc(daemon_node, Eliterm.Cluster, :list_nodes, [])
      ["list", "sessions"] -> 
        execute_rpc(daemon_node, Eliterm, :list_sessions, [])
      ["start", session_id] -> 
        execute_rpc(daemon_node, Eliterm, :start_session, [session_id])
      ["stop", session_id] -> 
        execute_rpc(daemon_node, Eliterm, :stop_session, [session_id])
      ["migrate", session_id, target_node] -> 
        execute_rpc(daemon_node, Eliterm.ClusterManager, :migrate_session, [session_id, target_node])
      ["list", "jobs", session_id] ->
        execute_rpc(daemon_node, Eliterm.CronManager, :list_jobs, [session_id])
      ["job", "run", session_id, job_name] ->
        execute_rpc(daemon_node, Eliterm.CronManager, :run_job, [session_id, job_name])
      ["job", "disable", session_id, job_name] ->
        execute_rpc(daemon_node, Eliterm.CronManager, :disable_job, [session_id, job_name])
      ["job", "enable", session_id, job_name] ->
        execute_rpc(daemon_node, Eliterm.CronManager, :enable_job, [session_id, job_name])
      ["job", "log", session_id, job_name] ->
        execute_rpc(daemon_node, Eliterm.CronManager, :job_log, [session_id, job_name])
      ["app", "install", session_id, pkg] ->
        execute_rpc(daemon_node, Eliterm.AppManager, :install_app, [session_id, pkg])
      ["app", "list", session_id] ->
        execute_rpc(daemon_node, Eliterm.AppManager, :list_apps, [session_id])
      ["config", "auto-migrate", target] ->
        config_path = Path.join([Eliterm.base_dir(), "config.json"])
        config = if File.exists?(config_path) do
          Jason.decode!(File.read!(config_path))
        else
          %{}
        end
        new_config = Map.put(config, "auto_migrate", %{"target_node" => target})
        File.write!(config_path, Jason.encode!(new_config, pretty: true))
        IO.puts "Auto-migrate target set to #{target}"
      _ ->
        print_usage()
    end
  end

  defp execute_rpc(daemon_node, mod, fun, args) do
    if Node.connect(daemon_node) do
      case :rpc.call(daemon_node, mod, fun, args) do
        {:badrpc, :nodedown} when fun in [:init, :rename, :reset] ->
          IO.puts "Connection closed (node is restarting/resetting)... Success."
        {:badrpc, reason} -> 
          IO.puts "RPC Error: #{inspect(reason)}"
        :ok -> 
          IO.puts "Success."
        {:ok, token, expires_at} when fun == :invite ->
          port = case :rpc.call(daemon_node, Application, :get_env, [:eliterm, ElitermWeb.Endpoint, []]) do
            config when is_list(config) ->
              Keyword.get(config, :http, []) |> Keyword.get(:port, 4000)
            _ ->
              4000
          end

          IO.puts "Generated invite token: #{token}"
          expires_time = DateTime.from_unix!(expires_at)
          IO.puts "Waiting for a node to join... (Expires at #{DateTime.to_string(expires_time)} UTC)"
          IO.puts "Primary Web Port: #{port}"
          IO.puts "Press ESC or Ctrl+C to cancel."
          start_invite_loop(daemon_node, token)

        %{cluster_name: c, node: n, full_node: f, cookie: cookie} ->
          IO.puts "Cluster Name: #{c}"
          IO.puts "Node:         #{n}"
          IO.puts "Join Target:  #{f}"
          IO.puts "Cookie:       #{cookie}"
        {:ok, result} when is_binary(result) -> 
          IO.puts result
        {:ok, result} -> 
          IO.inspect(result, pretty: true)
        {:error, :not_initialized} ->
          IO.puts(:stderr, "Error: Cluster is not initialized. Please run 'eliterm cluster init' first.")
          System.halt(1)
        {:error, :not_allowed_on_secondary} -> 
          IO.puts(:stderr, "Error: This action is only allowed on the primary (management) node.")
        {:error, reason} -> 
          IO.puts "Error: #{inspect(reason)}"
        other -> 
          IO.inspect(other, pretty: true)
      end
    else
      cond do
        mod == Eliterm.Cluster and fun == :init ->
          IO.puts "Eliterm daemon is not running on #{daemon_node}."
          IO.puts "Initializing cluster configuration locally on host OS..."
          prefix = List.first(args)
          case Eliterm.Cluster.init(prefix) do
            :ok -> IO.puts "Success. Cluster configuration initialized locally."
            {:error, :already_initialized} ->
              IO.puts(:stderr, "Error: Cluster is already initialized. Please run 'eliterm cluster reset' first.")
          end
        mod == Eliterm.Cluster and fun == :reset ->
          IO.puts "Eliterm daemon is not running on #{daemon_node}."
          IO.puts "Resetting cluster configuration locally on host OS..."
          case Eliterm.Cluster.reset() do
            :ok -> IO.puts "Success. Cluster configuration reset locally."
            {:error, :not_allowed_on_secondary} ->
              IO.puts(:stderr, "Error: This action is only allowed on the primary (management) node.")
          end
        mod == Eliterm.Cluster and fun == :info ->
          IO.puts "Eliterm daemon is not running on #{daemon_node}."
          IO.puts "Reading cluster configuration locally on host OS..."
          %{cluster_name: c, node: n, full_node: f, cookie: cookie} = Eliterm.Cluster.info()
          IO.puts "Cluster Name: #{c}"
          IO.puts "Node:         #{n}"
          IO.puts "Join Target:  #{f}"
          IO.puts "Cookie:       #{cookie}"
        mod == Eliterm.Cluster and fun == :invite ->
          IO.puts "Error: Eliterm daemon is not running on #{daemon_node}."
          IO.puts "An active daemon is required to start the HTTP invite server."
        true ->
          IO.puts "Error: Eliterm daemon is not running on #{daemon_node}."
          IO.puts "Make sure the daemon is started using 'mix run --no-halt' or via release daemon script."
      end
    end
  end

  defp print_usage do
    IO.puts """
    Usage: eliterm <command>

    Cluster:
      cluster init [<prefix>]
      cluster join <node> [--cookie <cookie>] [--role <role>]
      cluster leave
      cluster rename <prefix>
      cluster reset
      cluster info
      list nodes

    Sessions:
      start <session_id>
      stop <session_id>
      list sessions
      migrate <session_id> <target_node>

    Jobs (Cron):
      list jobs <session_id>
      job run <session_id> <job_name>
      job disable <session_id> <job_name>
      job enable <session_id> <job_name>
      job log <session_id> <job_name>

    Apps:
      app install <session_id> <pkg_name>
      app list <session_id>
    """
  end

  defp confirm_reset?(daemon_node) do
    other_nodes = if Node.connect(daemon_node) do
      case :rpc.call(daemon_node, Node, :list, []) do
        list when is_list(list) -> list
        _ -> []
      end
    else
      []
    end

    cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
    if File.exists?(cookie_path) do
      if other_nodes != [] do
        node_strs = Enum.map(other_nodes, &to_string/1) |> Enum.join(", ")
        IO.puts "Warning: The following connected nodes will also be forced to leave the cluster and reset:"
        IO.puts "  #{node_strs}"
        IO.puts "This will stop Erlang distribution and delete the cookie file on this node and all other nodes."
        IO.write "Are you sure you want to proceed? [y/N]: "
      else
        IO.puts "Warning: This will stop Erlang distribution and delete the cookie file."
        IO.write "Are you sure you want to reset the cluster? [y/N]: "
      end

      case IO.gets("") |> to_string() |> String.trim() |> String.downcase() do
        "y" -> true
        "yes" -> true
        _ -> false
      end
    else
      true
    end
  end

  defp start_invite_loop(daemon_node, token) do
    parent = self()
    {:ok, input_pid} = Task.start(fn ->
      set_raw_mode()
      read_loop(parent)
    end)

    {:ok, timer_ref} = :timer.send_interval(1000, :poll_status)

    try do
      loop(daemon_node, token, input_pid, timer_ref)
    after
      :timer.cancel(timer_ref)
      cleanup_terminal(input_pid)
    end
  end

  defp loop(daemon_node, token, input_pid, timer_ref) do
    receive do
      {:key, <<27>>} ->
        :rpc.call(daemon_node, Eliterm.Cluster, :cancel_invite, [])
        IO.puts "\r\nInvite canceled. Token invalidated."
      {:key, <<3>>} ->
        :rpc.call(daemon_node, Eliterm.Cluster, :cancel_invite, [])
        IO.puts "\r\nInvite canceled. Token invalidated."
      :poll_status ->
        case :rpc.call(daemon_node, Eliterm.Cluster, :get_invite_status, []) do
          nil ->
            IO.puts "\r\nJoined successfully or invite expired."
          %{token: current_token} when current_token != token ->
            IO.puts "\r\nInvite token superseded by a new one."
          _ ->
            loop(daemon_node, token, input_pid, timer_ref)
        end
      _ ->
        loop(daemon_node, token, input_pid, timer_ref)
    end

  end

  defp read_loop(parent) do
    case IO.read(:stdio, 1) do
      :eof -> :ok
      {:error, _} -> :ok
      data ->
        send(parent, {:key, data})
        read_loop(parent)
    end
  end

  defp set_raw_mode do
    if match?({:unix, _}, :os.type()) do
      System.cmd("stty", ["raw", "-echo"])
    end
  end

  defp cleanup_terminal(input_pid) do
    Process.exit(input_pid, :kill)
    if match?({:unix, _}, :os.type()) do
      System.cmd("stty", ["-raw", "echo"])
    end
  end
end
