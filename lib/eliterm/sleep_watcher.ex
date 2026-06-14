defmodule Eliterm.SleepWatcher do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case :os.type() do
      {:unix, :darwin} ->
        start_port(Path.join([System.user_home!(), ".local", "bin", "eliterm_sleep_watcher"]))
      {:win32, :nt} ->
        start_port(Path.join([System.user_home!(), ".local", "bin", "eliterm_sleep_watcher.exe"]))
      _ ->
        Logger.info("SleepWatcher is not supported on this OS yet.")
        :ignore
    end
  end

  defp start_port(bin_path) do
    if File.exists?(bin_path) do
      Logger.info("Starting SleepWatcher port...")
      if :os.type() == {:unix, :darwin} do
        System.cmd("xattr", ["-d", "com.apple.quarantine", bin_path], stderr_to_stdout: true)
      end
      port = Port.open({:spawn_executable, bin_path}, [:binary, :exit_status, line: 256])
      {:ok, %{port: port, status: :ready}}
    else
      Logger.warning("Sleep watcher binary not found at #{bin_path}")
      :ignore
    end
  end

  @impl true
  def handle_info({port, {:data, {:eol, "SLEEP_DETECTED"}}}, %{port: port} = state) do
    Logger.warning("OS Sleep detected! Initiating automatic migration...")
    
    target_node = get_target_node()
    if target_node do
      Logger.info("Migrating all sessions to #{target_node}...")
      
      # Spawn a task to handle migration so we don't block GenServer
      Task.start(fn ->
        case migrate_all(target_node) do
          :ok -> 
            Logger.info("Auto-migration complete.")
          {:error, reason} -> 
            Logger.error("Auto-migration failed: #{inspect(reason)}")
        end
        # Notify the swift watcher to release the sleep block
        Port.command(port, "MIGRATION_DONE\n")
      end)
    else
      Logger.info("No target_node configured for auto migration. Proceeding to sleep.")
      Port.command(port, "MIGRATION_DONE\n")
    end

    {:noreply, state}
  end

  def handle_info({port, {:data, {:eol, "READY"}}}, %{port: port} = state) do
    Logger.info("SleepWatcher is ready.")
    {:noreply, state}
  end

  def handle_info({port, {:data, {:eol, "ACK_SLEEP"}}}, %{port: port} = state) do
    Logger.info("SleepWatcher released sleep assertion.")
    {:noreply, state}
  end

  def handle_info({port, {:data, {:eol, "TIMEOUT_SLEEP"}}}, %{port: port} = state) do
    Logger.warning("SleepWatcher timed out waiting for migration.")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("SleepWatcher port exited with status #{status}")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp get_target_node do
    config_file = Path.join([Eliterm.base_dir(), "config.json"])
    if File.exists?(config_file) do
      try do
        config = Jason.decode!(File.read!(config_file))
        case config["auto_migrate"]["target_node"] do
          nil -> nil
          node_str -> String.to_atom(node_str)
        end
      rescue
        _ -> nil
      end
    else
      nil
    end
  end

  defp migrate_all(target_node) do
    sessions = Eliterm.list_sessions()
    results = 
      Enum.map(sessions, fn %{id: session_id} -> 
        Logger.info("Migrating session: #{session_id}")
        Eliterm.ClusterManager.migrate_session(session_id, target_node)
      end)

    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      {:error, "Some migrations failed"}
    end
  end
end
