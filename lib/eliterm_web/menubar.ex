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
      "github_light" -> %{"background" => "#ffffff", "foreground" => "#24292f", "cursor" => "#044289"}
      "github_dark" -> %{"background" => "#0d1117", "foreground" => "#c9d1d9", "cursor" => "#58a6ff"}
      "catppuccin_mocha" -> %{"background" => "#1e1e2e", "foreground" => "#cdd6f4", "cursor" => "#f5e0dc"}
      "catppuccin_latte" -> %{"background" => "#eff1f5", "foreground" => "#4c4f69", "cursor" => "#dc8a78"}
    end

    update_toml_colors(colors)
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "theme", {:theme_updated, colors})
    {:noreply, menu}
  end

  def handle_event("set_font_" <> font_id, menu) do
    font = case font_id do
      "default" -> ""
      "menlo" -> "Menlo"
      "monaco" -> "Monaco"
      "consolas" -> "Consolas"
      "fira_code" -> "Fira Code"
      "source_code_pro" -> "Source Code Pro"
      "hack" -> "Hack"
    end

    update_toml_font(font)
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "theme", {:font_updated, font})
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

  defp update_toml_font(font) do
    path = Path.join([Eliterm.base_dir(), "eliterm.toml"])
    File.mkdir_p!(Path.dirname(path))
    
    content = if File.exists?(path), do: File.read!(path), else: ""
    
    # Simple regex to replace or add [gui] font line. If [gui] doesn't exist, we just append it.
    # Note: parsing and rewriting TOML properly is hard, so we do a simple regex for `font = "..."`
    # For a robust solution, we should parse the whole TOML, but since eliterm.toml is managed here it's okay.
    content = String.replace(content, ~r/\n?\[gui\]\nfont = "[^"]*"/, "")
    
    if font != "" do
      new_section = "\n[gui]\nfont = \"#{font}\"\n"
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
        <menu label="Font">
          <item onclick="set_font_default">Default</item>
          <hr/>
          <item onclick="set_font_menlo">Menlo</item>
          <item onclick="set_font_monaco">Monaco</item>
          <item onclick="set_font_consolas">Consolas</item>
          <item onclick="set_font_fira_code">Fira Code</item>
          <item onclick="set_font_source_code_pro">Source Code Pro</item>
          <item onclick="set_font_hack">Hack</item>
        </menu>
        <menu label="Color Scheme">
          <item onclick="set_theme_default">Default</item>
          <hr/>
          <item onclick="set_theme_github_light">GitHub Light</item>
          <item onclick="set_theme_solarized_light">Solarized Light</item>
          <item onclick="set_theme_gruvbox_light">Gruvbox Light</item>
          <item onclick="set_theme_catppuccin_latte">Catppuccin Latte</item>
          <hr/>
          <item onclick="set_theme_github_dark">GitHub Dark</item>
          <item onclick="set_theme_monokai">Monokai</item>
          <item onclick="set_theme_solarized">Solarized Dark</item>
          <item onclick="set_theme_dracula">Dracula</item>
          <item onclick="set_theme_catppuccin_mocha">Catppuccin Mocha</item>
        </menu>
      </menu>
    </menubar>
    """
  end
end
