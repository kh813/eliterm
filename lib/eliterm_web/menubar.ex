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

  def handle_event("new_terminal", menu) do
    # On Mac, open a new instance using the open command
    if match?({:unix, :darwin}, :os.type()) do
      System.cmd("open", ["-n", "-a", "Eliterm"])
    end
    {:noreply, menu}
  end

  def handle_event("copy", menu) do
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "menu_actions", :menu_copy)
    {:noreply, menu}
  end

  def handle_event("paste", menu) do
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "menu_actions", :menu_paste)
    {:noreply, menu}
  end

  def handle_event("set_theme_" <> theme, menu) do
    colors = case theme do
      "default" -> %{}
      "monokai" -> %{"background" => "#272822", "foreground" => "#f8f8f2", "cursor" => "#f8f8f0"}
      "solarized" -> %{"background" => "#002b36", "foreground" => "#839496", "cursor" => "#93a1a1"}
      "dracula" -> %{"background" => "#282a36", "foreground" => "#f8f8f2", "cursor" => "#ff79c6"}
      "solarized_light" -> %{"background" => "#fdf6e3", "foreground" => "#657b83", "cursor" => "#586e75"}
      "gruvbox_light" -> %{"background" => "#fbf1c7", "foreground" => "#3c3836", "cursor" => "#af3a03"}
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
    <menubar>
      <menu label="Eliterm">
        <item onclick="new_terminal" shortcut="Cmd+N">New Terminal</item>
        <hr/>
        <item onclick="quit" shortcut="Cmd+Q">Quit</item>
      </menu>
      <menu label="Edit">
        <item onclick="copy" shortcut="Cmd+C">Copy</item>
        <item onclick="paste" shortcut="Cmd+V">Paste</item>
      </menu>
      <menu label="View">
        <menu label="Color Scheme">
          <item onclick="set_theme_default">Default</item>
          <item onclick="set_theme_monokai">Monokai</item>
          <item onclick="set_theme_solarized">Solarized Dark</item>
          <item onclick="set_theme_dracula">Dracula</item>
          <item onclick="set_theme_solarized_light">Solarized Light</item>
          <item onclick="set_theme_gruvbox_light">Gruvbox Light (Soft)</item>
        </menu>
      </menu>
    </menubar>
    """
  end
end
