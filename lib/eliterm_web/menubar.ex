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

  def handle_event("set_theme_" <> theme, menu) do
    colors = case theme do
      "default" -> %{}
      "monokai" -> %{"background" => "#272822", "foreground" => "#f8f8f2", "cursor" => "#f8f8f0"}
      "solarized" -> %{"background" => "#002b36", "foreground" => "#839496", "cursor" => "#93a1a1"}
      "dracula" -> %{"background" => "#282a36", "foreground" => "#f8f8f2", "cursor" => "#ff79c6"}
    end

    update_toml_colors(colors)
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "theme", {:theme_updated, colors})
    {:noreply, menu}
  end

  defp update_toml_colors(colors) do
    path = Path.join([Eliterm.base_dir(), "eliterm.toml"])
    File.mkdir_p!(Path.dirname(path))
    
    content = if File.exists?(path), do: File.read!(path), else: ""
    
    # Strip existing [gui.colors] section
    content = String.replace(content, ~r/\[gui\.colors\][^\[]*/s, "")
    
    # Append new [gui.colors]
    if colors != %{} do
      color_lines = Enum.map(colors, fn {k, v} -> "#{k} = \"#{v}\"" end)
      new_section = "\n[gui.colors]\n" <> Enum.join(color_lines, "\n") <> "\n"
      File.write!(path, String.trim(content) <> "\n" <> new_section)
    else
      File.write!(path, String.trim(content) <> "\n")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <menu id="menubar">
      <menu label="Eliterm">
        <item onclick="quit" shortcut="Cmd+Q">Quit</item>
      </menu>
      <menu label="View">
        <menu label="Color Scheme">
          <item onclick="set_theme_default">Default</item>
          <item onclick="set_theme_monokai">Monokai</item>
          <item onclick="set_theme_solarized">Solarized Dark</item>
          <item onclick="set_theme_dracula">Dracula</item>
        </menu>
      </menu>
    </menu>
    """
  end
end
