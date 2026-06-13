defmodule ElitermWeb.TerminalLive do
  use ElitermWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    colors = get_colors()
    if connected?(socket) do
      session = ensure_session()
      Phoenix.PubSub.subscribe(Eliterm.PubSub, "pty:#{session.id}")
      {:ok, assign(socket, session_id: session.id, colors: colors)}
    else
      {:ok, assign(socket, session_id: "default", colors: colors)}
    end
  end

  defp get_colors do
    path = Path.join([System.user_home!(), ".eliterm", "eliterm.toml"])
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
    Eliterm.PTY.resize(socket.assigns.session_id, cols, rows)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:pty_data, data}, socket) do
    {:noreply, push_event(socket, "terminal_output", %{data: data})}
  end

  defp ensure_session do
    case Eliterm.list_sessions() do
      [] -> 
        id = "default"
        Eliterm.start_session(id)
        %{id: id}
      [first | _] -> 
        first
    end
  end
end
