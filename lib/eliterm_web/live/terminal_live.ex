defmodule ElitermWeb.TerminalLive do
  use ElitermWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eliterm.PubSub, "theme")
    end
    {:ok, assign(socket, session_id: "default", colors: get_colors())}
  end



  defp get_colors do
    path = Path.join([Eliterm.base_dir(), "eliterm.toml"])
    if File.exists?(path) do
      case Toml.decode(File.read!(path)) do
        {:ok, parsed} -> get_in(parsed, ["gui", "colors"]) || %{}
        _ -> %{}
      end
    else
      %{}
    end
  end

  @impl true
  def handle_event("terminal_input", %{"data" => data}, socket) do
    Eliterm.PTY.write(socket.assigns.session_id, data)
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("terminal_resize", %{"cols" => cols, "rows" => rows}, socket) do
    socket = if not Map.has_key?(socket.assigns, :pty_started) do
      case Eliterm.start_session(socket.assigns.session_id, cols: cols, rows: rows) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> Eliterm.PTY.resize(socket.assigns.session_id, cols, rows)
      end
      Phoenix.PubSub.subscribe(Eliterm.PubSub, "pty:#{socket.assigns.session_id}")
      
      # Try to focus the window natively on Mac
      Task.start(fn ->
        Process.sleep(100)
        Desktop.Window.show(ElitermWindow)
      end)
      
      assign(socket, pty_started: true)
    else
      Eliterm.PTY.resize(socket.assigns.session_id, cols, rows)
      socket
    end
    {:noreply, socket}
  end

  @impl true
  def handle_info({:theme_updated, colors}, socket) do
    {:noreply, push_event(socket, "terminal_theme", %{colors: colors})}
  end

  @impl true
  def handle_info({:pty_data, data}, socket) do
    b64_data = Base.encode64(data)
    {:noreply, push_event(socket, "terminal_output", %{data: b64_data})}
  end

  @impl true
  def handle_info({:pty_exit, _exit_code}, socket) do
    if Code.ensure_loaded?(Desktop.Window) do
      Desktop.Window.quit()
    else
      System.stop(0)
    end
    {:noreply, socket}
  end

end
