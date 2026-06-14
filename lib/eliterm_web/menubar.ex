defmodule ElitermWeb.MenuBar do
  use Desktop.Menu

  @impl true
  def mount(menu) do
    {:ok, menu}
  end

  @impl true
  def handle_info(_msg, menu) do
    {:noreply, menu}
  end

  @impl true
  def handle_event("quit", menu) do
    System.stop(0)
    {:noreply, menu}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <menu id="menubar">
      <menu label="Eliterm">
        <item onclick="quit" shortcut="Cmd+Q">Quit</item>
      </menu>
    </menu>
    """
  end
end
