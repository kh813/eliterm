defmodule Eliterm.CLI do
  @moduledoc """
  eliterm コマンドラインクライアントのエントリポイント。
  escript としてビルドされ、バックグラウンドの eliterm デーモンに RPC リクエストを送信する。
  """

  def main(args) do
    {opts, command, _} = OptionParser.parse(args, switches: [node: :string, cookie: :string])

    client_name = "cli_#{:rand.uniform(10000)}" |> String.to_atom()
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
      {:ok, hostname} = :inet.gethostname()
      short_host = to_string(hostname) |> String.split(".") |> List.first()
      String.to_atom("eliterm@#{short_host}")
    end

    case command do
      ["cluster", "init"] -> 
        if confirm_reinit?() do
          execute_rpc(daemon_node, Eliterm.Cluster, :init, [])
        else
          IO.puts "Aborted."
        end
      ["cluster", "join", target] -> 
        execute_rpc(daemon_node, Eliterm.Cluster, :join, [target, opts[:cookie]])
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
        {:badrpc, reason} -> 
          IO.puts "RPC Error: #{inspect(reason)}"
        :ok -> 
          IO.puts "Success."
        {:ok, result} when is_binary(result) -> 
          IO.puts result
        {:ok, result} -> 
          IO.inspect(result, pretty: true)
        {:error, reason} -> 
          IO.puts "Error: #{inspect(reason)}"
        other -> 
          IO.inspect(other, pretty: true)
      end
    else
      if mod == Eliterm.Cluster and fun == :init do
        IO.puts "Eliterm daemon is not running on #{daemon_node}."
        IO.puts "Initializing cluster configuration locally on host OS..."
        Eliterm.Cluster.init()
        IO.puts "Success. Cluster configuration initialized locally."
      else
        IO.puts "Error: Eliterm daemon is not running on #{daemon_node}."
        IO.puts "Make sure the daemon is started using 'mix run --no-halt' or via release daemon script."
      end
    end
  end

  defp print_usage do
    IO.puts """
    Usage: eliterm <command>

    Cluster:
      cluster init
      cluster join <node> [--cookie <cookie>]
      cluster leave
      cluster rename <prefix>
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

  defp confirm_reinit? do
    cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
    if File.exists?(cookie_path) do
      IO.puts "Warning: Cluster is already initialized (cookie file exists)."
      IO.puts "Re-initializing will generate a new cookie, which will disconnect this node from all other nodes in the cluster."
      IO.write "Do you want to proceed? [y/N]: "
      case IO.gets("") |> to_string() |> String.trim() |> String.downcase() do
        "y" -> true
        "yes" -> true
        _ -> false
      end
    else
      true
    end
  end
end
