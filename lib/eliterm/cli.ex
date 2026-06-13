defmodule Eliterm.CLI do
  @moduledoc """
  eliterm コマンドラインクライアントのエントリポイント。
  escript としてビルドされ、バックグラウンドの eliterm デーモンに RPC リクエストを送信する。
  """

  def main(args) do
    {opts, command, _} = OptionParser.parse(args, switches: [node: :string])

    client_name = "cli_#{:rand.uniform(10000)}" |> String.to_atom()
    {:ok, _} = Node.start(client_name, :shortnames)

    cookie_path = Path.join([System.user_home!(), ".eliterm", "cookie"])
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
        execute_rpc(daemon_node, Eliterm.Cluster, :init, [])
      ["cluster", "join", target] -> 
        execute_rpc(daemon_node, Eliterm.Cluster, :join, [target])
      ["cluster", "leave"] -> 
        execute_rpc(daemon_node, Eliterm.Cluster, :leave, [])
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
      ["config", "auto-migrate", target] ->
        config_path = Path.join([System.user_home!(), ".eliterm", "config.json"])
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
      IO.puts "Error: Eliterm daemon is not running on #{daemon_node}."
      IO.puts "Make sure the daemon is started using 'mix run --no-halt' or via release daemon script."
    end
  end

  defp print_usage do
    IO.puts """
    Usage: eliterm <command>

    Cluster:
      cluster init
      cluster join <node>
      cluster leave
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
    """
  end
end
