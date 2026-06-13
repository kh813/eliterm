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

    sock_path = Path.join([home_dir, "..", ".session", "eliterm.sock"]) |> Path.expand()
    File.mkdir_p!(Path.dirname(sock_path))
    _ = File.rm(sock_path) # Remove stale socket

    bash_path = System.find_executable("bash") || "/bin/bash"

    env = [
      {"HOME", home_dir},
      {"SHELL", bash_path},
      {"TERM", "xterm-256color"}
    ]

    me = self()

    on_data = fn _pty, _os_pid, data ->
      send(me, {:pty_data, data})
    end

    on_exit = fn _pty, _os_pid, exit_code, _signal ->
      send(me, {:pty_exit, exit_code})
    end

    {:ok, pty} = ExPTY.spawn(bash_path, [],
      env: env,
      cwd: home_dir,
      name: "xterm-256color",
      cols: 80,
      rows: 24,
      on_data: on_data,
      on_exit: on_exit
    )

    # Start Unix Domain Socket listener
    {:ok, listen_sock} = :gen_tcp.listen(0, [
      :binary,
      {:ifaddr, {:local, String.to_charlist(sock_path)}},
      {:active, true},
      {:packet, 0}
    ])

    File.chmod!(sock_path, 0o600)

    # Accept the first connection asynchronously
    send(self(), :accept_client)

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

  @impl true
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
    {:noreply, state}
  end

  def handle_info({:pty_exit, exit_code}, state) do
    Logger.info("PTY for session #{state.session_id} exited with code #{exit_code}")
    # Close all clients
    Enum.each(state.clients, fn client ->
      :gen_tcp.close(client)
    end)
    # Usually we would stop the session, but maybe we just restart the shell?
    # For now, let the GenServer terminate.
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
