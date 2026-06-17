defmodule ElitermWeb.TerminalLive do
  use ElitermWeb, :live_view
  require Logger


  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eliterm.PubSub, "theme")
      Phoenix.PubSub.subscribe(Eliterm.PubSub, "menu_actions")
    end
    {:ok, assign(socket, session_id: "default", colors: get_colors(), font: get_font(), pty_status: :initializing)}
  end



  defp get_colors do
    Eliterm.Config.get(["gui", "colors"], %{})
  end

  defp get_font do
    Eliterm.Config.get(["gui", "font"], "")
  end

  @impl true
  def handle_event("terminal_input", %{"data" => data}, socket) do
    Eliterm.PTY.write(socket.assigns.session_id, data)
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("terminal_resize", %{"cols" => cols, "rows" => rows}, socket) do
    socket = if not Map.has_key?(socket.assigns, :pty_started) do
      session_id = socket.assigns.session_id
      self_pid = self()

      Task.start(fn ->
        case Eliterm.start_session(session_id, cols: cols, rows: rows) do
          {:ok, _} -> send(self_pid, :session_started)
          {:error, {:already_started, _}} -> send(self_pid, :session_started)
          {:error, reason} -> send(self_pid, {:session_failed, reason})
        end
      end)

      Phoenix.PubSub.subscribe(Eliterm.PubSub, "pty:#{session_id}")
      
      # Try to focus the window natively on Mac
      Task.start(fn ->
        Process.sleep(100)
        Desktop.Window.show(ElitermWindow)
      end)
      
      assign(socket, pty_started: true, pty_status: :initializing)
    else
      if socket.assigns.pty_status == :ready do
        Eliterm.PTY.resize(socket.assigns.session_id, cols, rows)
      end
      socket
    end
    {:noreply, socket}
  end

  @impl true
  def handle_event("clipboard_copy", %{"text" => text}, socket) do
    Logger.info("Received clipboard_copy event with text: #{inspect(text)}")
    Eliterm.Clipboard.copy(text)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clipboard_paste", _params, socket) do
    case Eliterm.Clipboard.paste() do
      {:ok, text} when text != "" ->
        {:noreply, push_event(socket, "terminal_paste", %{text: text})}
      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:theme_updated, colors}, socket) do
    {:noreply, push_event(socket, "terminal_theme", %{colors: colors})}
  end

  @impl true
  def handle_info({:font_updated, font}, socket) do
    {:noreply, push_event(socket, "terminal_font", %{font: font})}
  end

  @impl true
  def handle_info(:menu_copy, socket) do
    Logger.info("Received :menu_copy broadcast, pushing request_copy event to JS")
    {:noreply, push_event(socket, "request_copy", %{})}
  end

  @impl true
  def handle_info(:menu_paste, socket) do
    case Eliterm.Clipboard.paste() do
      {:ok, text} when text != "" ->
        {:noreply, push_event(socket, "terminal_paste", %{text: text})}
      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:session_started, socket) do
    # When session finishes starting, tell JS to focus the terminal
    {:noreply, assign(socket, pty_status: :ready) |> push_event("session_ready", %{})}
  end

  @impl true
  def handle_info({:session_failed, reason}, socket) do
    {:noreply, assign(socket, pty_status: {:failed, reason})}
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
      System.halt(0)
    end
    {:noreply, socket}
  end

end
