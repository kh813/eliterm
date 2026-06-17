defmodule ElitermWeb.MenuBar do
  use Desktop.Menu

  @impl true
  def mount(menu) do
    scanned_fonts = Eliterm.Config.get(["gui", "scanned_fonts"], [])
    {:ok, Desktop.Menu.assign(menu, :scanned_fonts, scanned_fonts)}
  end

  @impl true
  def handle_info(_msg, menu) do
    {:noreply, menu}
  end

  @impl true
  def handle_event("quit", menu) do
    Eliterm.WindowWatcher.shutdown_app()
    {:noreply, menu}
  end

  def handle_event("new_terminal", menu) do
    # On Mac, open a new instance using the open command
    if match?({:unix, :darwin}, :os.type()) do
      System.cmd("open", ["-n", "-a", "Eliterm"])
    end
    {:noreply, menu}
  end

  def handle_event("scan_fonts", menu) do
    fonts = Eliterm.FontScanner.scan()
    Eliterm.Config.put(["gui", "scanned_fonts"], fonts)
    {:noreply, Desktop.Menu.assign(menu, :scanned_fonts, fonts)}
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
      "monokai" -> %{"background" => "#272822", "foreground" => "#f8f8f2", "cursor" => "#f8f8f0", "selectionBackground" => "rgba(255, 255, 255, 0.25)"}
      "solarized" -> %{"background" => "#002b36", "foreground" => "#839496", "cursor" => "#93a1a1", "selectionBackground" => "rgba(255, 255, 255, 0.2)"}
      "dracula" -> %{"background" => "#282a36", "foreground" => "#f8f8f2", "cursor" => "#ff79c6", "selectionBackground" => "rgba(255, 255, 255, 0.25)"}
      "solarized_light" -> %{"background" => "#fdf6e3", "foreground" => "#657b83", "cursor" => "#586e75", "selectionBackground" => "rgba(38, 139, 210, 0.25)"}
      "gruvbox_light" -> %{"background" => "#fbf1c7", "foreground" => "#3c3836", "cursor" => "#af3a03", "selectionBackground" => "rgba(69, 133, 136, 0.25)"}
      "github_light" -> %{"background" => "#ffffff", "foreground" => "#24292f", "cursor" => "#044289", "selectionBackground" => "rgba(4, 66, 137, 0.2)"}
      "github_dark" -> %{"background" => "#0d1117", "foreground" => "#c9d1d9", "cursor" => "#58a6ff", "selectionBackground" => "rgba(88, 166, 255, 0.3)"}
      "catppuccin_mocha" -> %{"background" => "#1e1e2e", "foreground" => "#cdd6f4", "cursor" => "#f5e0dc", "selectionBackground" => "rgba(255, 255, 255, 0.2)"}
      "catppuccin_latte" -> %{"background" => "#eff1f5", "foreground" => "#4c4f69", "cursor" => "#dc8a78", "selectionBackground" => "rgba(30, 102, 245, 0.2)"}
    end

    update_toml_colors(colors)
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "theme", {:theme_updated, colors})
    {:noreply, menu}
  end

  def handle_event("set_font_" <> font_id, menu) do
    # font_id is string. We can decode if we passed base64, but since we know the keys:
    font = case font_id do
      "default" -> ""
      "menlo" -> "Menlo"
      "monaco" -> "Monaco"
      "consolas" -> "Consolas"
      other -> String.replace(other, "_", " ")
    end

    # Fix casing for known fonts that use camel case
    font = Enum.find(["Fira Code", "Cascadia Code", "Source Code Pro", "Hack", "JetBrains Mono", "Ubuntu Mono"], font, fn known -> 
      String.downcase(known) == String.downcase(font)
    end)

    update_toml_font(font)
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "theme", {:font_updated, font})
    {:noreply, menu}
  end

  defp update_toml_colors(colors) do
    if colors == %{} do
      Eliterm.Config.put(["gui", "colors"], %{})
    else
      Eliterm.Config.put(["gui", "colors"], colors)
    end
  end

  defp update_toml_font(font) do
    Eliterm.Config.put(["gui", "font"], font)
  end

  @impl true
  def render(assigns) do
    cmd_key = if match?({:unix, :darwin}, :os.type()), do: "Cmd", else: "Ctrl"
    assigns = Map.put_new(assigns, :cmd_key, cmd_key)

    ~H"""
    <menubar>
      <menu label="Eliterm">
        <item onclick="new_terminal" shortcut={"#{@cmd_key}+N"}>New Terminal</item>
        <hr/>
        <item onclick="quit" shortcut={"#{@cmd_key}+Q"}>Quit</item>
      </menu>
      <menu label="Edit">
        <item onclick="copy" shortcut={"#{@cmd_key}+C"}>Copy</item>
        <item onclick="paste" shortcut={"#{@cmd_key}+V"}>Paste</item>
      </menu>
      <menu label="View">
        <menu label="Font">
          <item onclick="set_font_default">Default</item>
          <hr/>
          <%= if match?({:unix, :darwin}, :os.type()) do %>
            <item onclick="set_font_menlo">Menlo</item>
            <item onclick="set_font_monaco">Monaco</item>
          <% else %>
            <item onclick="set_font_consolas">Consolas</item>
          <% end %>
          
          <%= if @scanned_fonts != [] do %>
            <hr/>
            <%= for font <- @scanned_fonts do %>
              <item onclick={"set_font_#{String.replace(String.downcase(font), " ", "_")}"}><%= font %></item>
            <% end %>
          <% end %>
          <hr/>
          <item onclick="scan_fonts">Scan &amp; update font list</item>
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
