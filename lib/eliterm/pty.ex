defmodule Eliterm.PTY do
  @moduledoc """
  ExPTY を使用した bash プロセスの管理および Unix Domain Socket 経由でのクライアント通信を行う GenServer。
  """
  use GenServer
  require Logger

  # Client API

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  def via_tuple(session_id) do
    {:via, Horde.Registry, {Eliterm.Registry, "pty_#{session_id}"}}
  end

  def write(session_id, data) do
    GenServer.cast(via_tuple(session_id), {:write, data})
  end

  def resize(session_id, cols, rows) do
    GenServer.cast(via_tuple(session_id), {:resize, cols, rows})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    home_dir = Keyword.fetch!(opts, :home_dir)

    File.mkdir_p!(home_dir)

    bashrc_path = Path.join(home_dir, ".bashrc")
    unless File.exists?(bashrc_path) do
      trap_code = """
      trap 'pwd > ~/.session/cwd; env > ~/.session/env; declare -p > ~/.session/vars; alias > ~/.session/aliases' SIGUSR1
      export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"
      """
      File.write!(bashrc_path, trap_code)
    end

    sock_path = Path.join([home_dir, "..", ".session", "eliterm.sock"]) |> Path.expand()
    File.mkdir_p!(Path.dirname(sock_path))
    _ = File.rm(sock_path) # Remove stale socket

    bash_path = System.find_executable("bash") || "/bin/bash"

    env = [
      {"HOME", home_dir},
      {"SHELL", bash_path},
      {"TERM", "xterm-256color"}
    ]

    session_dir = Path.join([home_dir, "..", ".session"]) |> Path.expand()
    snapshot = Eliterm.SessionSnapshot.load(session_dir)

    env_map = Map.new(env)
    
    {bash_args, cwd, env_map} =
      if snapshot do
        s_cwd = Path.join("/home/user", snapshot.cwd)
        s_env_map = Map.merge(env_map, snapshot.env)
        
        restore_rc = Path.join(home_dir, ".restore.rc")
        File.write!(restore_rc, """
        source ~/.bashrc
        #{snapshot.shell_vars}
        #{snapshot.aliases}
        rm ~/.restore.rc
        """)
        
        File.rm(Path.join(session_dir, "snapshot.json"))
        {["--rcfile", "/home/user/.restore.rc"], s_cwd, s_env_map}
      else
        {[], "/home/user", env_map}
      end
    
    # No need to convert to list, ExPTY expects map

    me = self()

    on_data = fn _pty, _os_pid, data ->
      send(me, {:pty_data, data})
    end

    on_exit = fn _pty, _os_pid, exit_code, _signal ->
      send(me, {:pty_exit, exit_code})
    end

    is_fallback = Eliterm.ContainerWorker.is_fallback?(session_id)
    bin = Eliterm.Container.Engine.executable()

    {final_bin, final_args, final_env} =
      if is_fallback or is_nil(bin) do
        # Fallback to local bash: must inherit system environment so PATH works!
        bash_path = System.find_executable("bash") || "/bin/bash"
        sys_env = System.get_env()
        merged_env = Map.merge(sys_env, env_map)
        {bash_path, bash_args, merged_env}
      else
        podman_args = ["exec", "-it"]
        env_args = Enum.flat_map(env_map, fn {k, v} -> ["-e", "#{k}=#{v}"] end)
        cwd_args = ["-w", cwd]
        final_args = podman_args ++ env_args ++ cwd_args ++ ["eliterm-#{session_id}", "bash"] ++ bash_args
        sys_env = System.get_env()
        
        # Wait for container to be ready before trying to exec into it
        wait_for_container(bin, "eliterm-#{session_id}")
        
        {bin, final_args, sys_env}
      end

    cols = Keyword.get(opts, :cols, 80)
    rows = Keyword.get(opts, :rows, 24)

    {:ok, pty} = ExPTY.spawn(final_bin, final_args,
      env: final_env,
      cwd: home_dir,
      name: "xterm-256color",
      cols: cols,
      rows: rows,
      on_data: on_data,
      on_exit: on_exit,
      closeFDs: true
    )

    # Start Unix Domain Socket listener (may fail on Windows due to :eafnosupport)
    listen_sock = case :gen_tcp.listen(0, [
      :binary,
      {:ifaddr, {:local, String.to_charlist(sock_path)}},
      {:active, true},
      {:packet, 0}
    ]) do
      {:ok, sock} ->
        File.chmod!(sock_path, 0o600)
        # Accept the first connection asynchronously
        send(self(), :accept_client)
        sock
      {:error, reason} ->
        Logger.warning("Failed to start Unix Domain Socket for PTY: #{inspect(reason)}. Local sock clients disabled.")
        nil
    end

    {:ok, %{
      session_id: session_id,
      pty: pty,
      listen_sock: listen_sock,
      clients: []
    }}
  end

  @impl true
  def handle_cast({:write, data}, state) do
    ExPTY.write(state.pty, data)
    {:noreply, state}
  end

  def handle_cast({:resize, cols, rows}, state) do
    ExPTY.resize(state.pty, cols, rows)
    {:noreply, state}
  end

  defp wait_for_container(bin, name, retries \\ 120)
  defp wait_for_container(_bin, _name, 0), do: :ok
  defp wait_for_container(bin, name, retries) do
    case System.cmd(bin, ["ps", "--format", "{{.Names}}", "--filter", "name=#{name}"]) do
      {output, 0} ->
        if String.contains?(output, name) do
          :ok
        else
          Process.sleep(500)
          wait_for_container(bin, name, retries - 1)
        end
      _ ->
        Process.sleep(500)
        wait_for_container(bin, name, retries - 1)
    end
  end

  @impl true
  def handle_info(:accept_client, %{listen_sock: nil} = state), do: {:noreply, state}
  def handle_info(:accept_client, state) do
    # Accept one client connection
    case :gen_tcp.accept(state.listen_sock, 0) do
      {:ok, client_sock} ->
        # Send a welcome message or current state? For now, just add.
        Logger.info("Client connected to session #{state.session_id}")
        send(self(), :accept_client) # Ready for next client
        {:noreply, %{state | clients: [client_sock | state.clients]}}
      {:error, reason} ->
        Logger.warning("Accept failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({:pty_data, data}, state) do
    # Broadcast to all connected clients
    Enum.each(state.clients, fn client ->
      :gen_tcp.send(client, data)
    end)
    
    # Broadcast to Phoenix PubSub for LiveView
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "pty:#{state.session_id}", {:pty_data, data})
    
    {:noreply, state}
  end

  def handle_info({:pty_exit, exit_code}, state) do
    Logger.info("PTY for session #{state.session_id} exited with code #{exit_code}")
    # Close all clients
    Enum.each(state.clients, fn client ->
      :gen_tcp.close(client)
    end)
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "pty:#{state.session_id}", {:pty_exit, exit_code})
    {:stop, :normal, state}
  end

  def handle_info({:tcp, _sock, data}, state) do
    # Data received from a client -> write to PTY
    ExPTY.write(state.pty, data)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, sock}, state) do
    Logger.info("Client disconnected from session #{state.session_id}")
    {:noreply, %{state | clients: List.delete(state.clients, sock)}}
  end

  def handle_info({:tcp_error, sock, _reason}, state) do
    {:noreply, %{state | clients: List.delete(state.clients, sock)}}
  end
end
