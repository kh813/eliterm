defmodule Eliterm.ClusterManager do
  @moduledoc """
  ノード参加・離脱・マイグレーションのフローを制御するGenServer。
  """
  use GenServer
  require Logger

  def start_invite do
    GenServer.call(__MODULE__, :start_invite)
  end

  def cancel_invite do
    GenServer.call(__MODULE__, :cancel_invite)
  end

  def verify_and_use_token(token, public_key_der) do
    GenServer.call(__MODULE__, {:verify_and_use_token, token, public_key_der})
  end

  def get_invite_status do
    GenServer.call(__MODULE__, :get_invite_status)
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Eliterm.ClusterManager...")
    {:ok, %{invite_token: nil, timer: nil, expires_at: nil, cookie: nil}}
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

  @impl true
  def handle_call(:start_invite, _from, state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    # 100-100 to 999-999 (random token)
    token = "#{:rand.uniform(900) + 99}-#{:rand.uniform(900) + 99}"
    
    # 5 minutes timer
    timer = Process.send_after(self(), {:invite_timeout, token}, 300_000)
    expires_at = DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix()

    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    cookie = if File.exists?(cookie_path), do: File.read!(cookie_path), else: ""

    new_state = %{state | invite_token: token, timer: timer, expires_at: expires_at, cookie: cookie}
    Logger.info("Cluster invite mode started. Token: #{token}")
    {:reply, {:ok, token, expires_at}, new_state}
  end

  def handle_call(:cancel_invite, _from, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    
    new_state = %{state | invite_token: nil, timer: nil, expires_at: nil, cookie: nil}
    Logger.info("Cluster invite mode canceled.")
    {:reply, :ok, new_state}
  end

  def handle_call({:verify_and_use_token, token, public_key_der}, _from, state) do
    cond do
      is_nil(state.invite_token) ->
        {:reply, {:error, :no_active_invite}, state}

      state.invite_token != token ->
        {:reply, {:error, :invalid_token}, state}

      true ->
        if state.timer, do: Process.cancel_timer(state.timer)

        cookie = state.cookie || ""
        
        case Eliterm.Crypto.encrypt_cookie(cookie, public_key_der) do
          encrypted_cookie ->
            new_state = %{state | invite_token: nil, timer: nil, expires_at: nil, cookie: nil}
            Logger.info("Invite token #{token} verified and consumed.")
            {:reply, {:ok, encrypted_cookie}, new_state}
        end
    end
  end

  def handle_call(:get_invite_status, _from, state) do
    if state.invite_token do
      {:reply, %{token: state.invite_token, expires_at: state.expires_at}, state}
    else
      {:reply, nil, state}
    end
  end

  @impl true
  def handle_info({:invite_timeout, token}, state) do
    if state.invite_token == token do
      Logger.info("Invite token #{token} expired.")
      {:noreply, %{state | invite_token: nil, timer: nil, expires_at: nil, cookie: nil}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
