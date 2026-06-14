defmodule Eliterm.ClusterManager do
  @moduledoc """
  ノード参加・離脱・マイグレーションのフローを制御するGenServer。
  """
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Eliterm.ClusterManager...")
    {:ok, %{}}
  end

  def migrate_session(session_id, target_node) do
    case Horde.Registry.lookup(Eliterm.Registry, "session_#{session_id}") do
      [{pid, _}] ->
        GenServer.cast(__MODULE__, {:migrate, session_id, pid, target_node})
      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def handle_cast({:migrate, session_id, _session_pid, target_node}, state) do
    Task.start(fn ->
      do_migration(session_id, target_node)
    end)
    {:noreply, state}
  end

  defp do_migration(session_id, target_node) do
    Logger.info("Starting migration of session #{session_id} to #{target_node}")
    home_dir = Path.join([Eliterm.base_dir(), "sessions", session_id, "home"])

    # 1. Capacity check
    {:ok, %{total: _total_size}} = Eliterm.DataSync.calc_size(home_dir)
    
    # 2. Stop Quantum & Disconnect PTY
    pty_pid = case Horde.Registry.lookup(Eliterm.Registry, "pty_#{session_id}") do
      [{pid, _}] -> pid
      _ -> nil
    end

    if pty_pid do
      Logger.info("Capturing snapshot for #{session_id}")
      Eliterm.SessionSnapshot.capture(session_id, home_dir, pty_pid)
    end

    Logger.info("Stopping session process on source node")
    Eliterm.stop_session(session_id)

    # 3. Readonly & Rsync
    Logger.info("Setting readonly and syncing data...")
    Eliterm.DataSync.set_readonly(home_dir, true)
    
    target_host = to_string(target_node) |> String.split("@") |> List.last()
    src_dir = Path.dirname(home_dir) 
    
    case Eliterm.DataSync.rsync_copy(src_dir, target_host, Path.dirname(src_dir)) do
      :ok ->
        Logger.info("Rsync successful. Verifying checksum...")
        {:ok, src_hash} = Eliterm.DataSync.verify_checksum(home_dir)
        {:ok, tgt_hash} = :rpc.call(target_node, Eliterm.DataSync, :verify_checksum, [home_dir])
        
        if src_hash == tgt_hash do
          Logger.info("Checksum matches! Starting session on target node...")
          Eliterm.DataSync.set_readonly(home_dir, false)
          
          # 4. Start on target node
          :rpc.call(target_node, Eliterm, :start_session, [session_id])
          
          Logger.info("Migration completed successfully.")
        else
          Logger.error("Checksum mismatch! Aborting migration.")
          Eliterm.DataSync.set_readonly(home_dir, false)
          Eliterm.start_session(session_id)
        end
      {:error, reason} ->
        Logger.error("Rsync failed: #{inspect(reason)}")
        Eliterm.DataSync.set_readonly(home_dir, false)
        Eliterm.start_session(session_id)
    end
  end
end
