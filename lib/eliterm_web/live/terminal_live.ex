defmodule ElitermWeb.TerminalLive do
  use ElitermWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      session = ensure_session()
      Phoenix.PubSub.subscribe(Eliterm.PubSub, "pty:#{session.id}")
      {:ok, assign(socket, session_id: session.id)}
    else
      {:ok, assign(socket, session_id: "default")}
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
