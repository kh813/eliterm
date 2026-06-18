defmodule ElitermWeb.MenuBar do
  use Desktop.Menu
  require Logger

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
    if should_confirm_quit?() do
      if confirm_quit?() do
        Eliterm.WindowWatcher.shutdown_app()
      end
    else
      Eliterm.WindowWatcher.shutdown_app()
    end
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
    Logger.info("MenuBar handle_event(\"copy\") called")
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "menu_actions", :menu_copy)
    {:noreply, menu}
  end

  def handle_event("paste", menu) do
    Phoenix.PubSub.broadcast(Eliterm.PubSub, "menu_actions", :menu_paste)
    {:noreply, menu}
  end

  def handle_event("cluster_info", menu) do
    info = Eliterm.Cluster.info()
    msg = ~c"Node: #{info.node}\nCookie: #{info.cookie}"
    caption = ~c"Cluster Info"
    show_message_dialog(msg, caption, 1024) # wxICON_INFORMATION
    {:noreply, menu}
  end

  def handle_event("cluster_init", menu) do
    cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
    if File.exists?(cookie_path) do
      msg = ~c"Warning: Cluster is already initialized.\nRe-initializing will generate a new cookie, which will disconnect this node from all other nodes.\n\nDo you want to proceed?"
      caption = ~c"Re-initialize Cluster?"
      style = 1162 # wxYES_NO | wxICON_QUESTION | wxNO_DEFAULT
      
      if show_confirm_dialog(msg, caption, style) do
        Eliterm.Cluster.init()
        show_message_dialog(~c"Cluster initialized successfully.", ~c"Success", 1024)
      end
    else
      Eliterm.Cluster.init()
      show_message_dialog(~c"Cluster initialized successfully.", ~c"Success", 1024)
    end
    {:noreply, menu}
  end

  def handle_event("cluster_rename", menu) do
    current_prefix = Eliterm.Config.get(["cluster", "node_prefix"], "eliterm")
    case show_text_entry_dialog(~c"Enter new node prefix:", ~c"Rename Node", to_charlist(current_prefix)) do
      {:ok, new_prefix} ->
        case Eliterm.Cluster.rename(new_prefix) do
          {:ok, new_name} ->
            show_message_dialog(~c"Node renamed successfully.\nNew Node Name: #{new_name}", ~c"Success", 1024)
          :ok ->
            show_message_dialog(~c"Node prefix updated. (Distribution not active)", ~c"Success", 1024)
          {:error, reason} ->
            show_message_dialog(~c"Error renaming node: #{inspect(reason)}", ~c"Error", 256)
        end
      :cancel ->
        :ok
    end
    {:noreply, menu}
  end

  def handle_event("cluster_join", menu) do
    case show_text_entry_dialog(~c"Enter target node to join (e.g. eliterm@hostname):", ~c"Join Cluster", ~c"") do
      {:ok, target_node} ->
        case show_text_entry_dialog(~c"Enter cluster cookie (leave empty to use current cookie):", ~c"Join Cluster - Cookie", ~c"") do
          {:ok, cookie} ->
            cookie_arg = if cookie == "", do: nil, else: cookie
            case Eliterm.Cluster.join(target_node, cookie_arg) do
              :ok ->
                show_message_dialog(~c"Successfully joined cluster.", ~c"Success", 1024)
              {:error, reason} ->
                show_message_dialog(~c"Failed to join cluster: #{inspect(reason)}", ~c"Error", 256)
            end
          :cancel ->
            :ok
        end
      :cancel ->
        :ok
    end
    {:noreply, menu}
  end

  def handle_event("cluster_leave", menu) do
    msg = ~c"Are you sure you want to leave the cluster?\nThis will stop Erlang distribution and delete the cookie."
    caption = ~c"Leave Cluster?"
    style = 1162 # wxYES_NO | wxICON_QUESTION | wxNO_DEFAULT
    
    if show_confirm_dialog(msg, caption, style) do
      Eliterm.Cluster.leave()
      show_message_dialog(~c"Successfully left the cluster.", ~c"Success", 1024)
    end
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

  defp should_confirm_quit? do
    Application.get_env(:eliterm, :start_gui, true) and
      Code.ensure_loaded?(:wx) and
      not :wx.is_null(:wx.null())
  end

  defp confirm_quit? do
    msg = ~c"Elitermを終了してもよろしいですか？\n実行中のバックグラウンドセッションやcronジョブがすべて終了します。"
    caption = ~c"終了の確認"
    # wxYES_NO (10) bor wxICON_QUESTION (1024) bor wxNO_DEFAULT (128) = 1162
    style = 1162

    try do
      dialog = :wxMessageDialog.new(:wx.null(), msg, [{:caption, caption}, {:style, style}])
      result = :wxMessageDialog.showModal(dialog)
      :wxMessageDialog.destroy(dialog)
      result == 5103 # wxID_YES
    rescue
      e ->
        Logger.error("Failed to show confirmation dialog: #{inspect(e)}")
        true
    end
  end

  defp show_message_dialog(msg, caption, style) do
    try do
      dialog = :wxMessageDialog.new(:wx.null(), msg, [{:caption, caption}, {:style, style}])
      :wxMessageDialog.showModal(dialog)
      :wxMessageDialog.destroy(dialog)
    rescue
      e -> Logger.error("Failed to show message dialog: #{inspect(e)}")
    end
  end

  defp show_confirm_dialog(msg, caption, style) do
    try do
      dialog = :wxMessageDialog.new(:wx.null(), msg, [{:caption, caption}, {:style, style}])
      result = :wxMessageDialog.showModal(dialog)
      :wxMessageDialog.destroy(dialog)
      result == 5103 # wxID_YES
    rescue
      _ -> true
    end
  end

  defp show_text_entry_dialog(msg, caption, default_value) do
    try do
      dialog = :wxTextEntryDialog.new(:wx.null(), msg, [{:caption, caption}, {:value, default_value}])
      result = :wxTextEntryDialog.showModal(dialog)
      value = :wxTextEntryDialog.getValue(dialog)
      :wxTextEntryDialog.destroy(dialog)
      
      if result == 5100 do # wxID_OK
        {:ok, to_string(value)}
      else
        :cancel
      end
    rescue
      e ->
        Logger.error("Failed to show text entry dialog: #{inspect(e)}")
        :cancel
    end
  end

  @impl true
  def render(assigns) do
    cmd_key = if match?({:unix, :darwin}, :os.type()), do: "Cmd", else: "Ctrl"
    assigns = Map.put_new(assigns, :cmd_key, cmd_key)

    ~H"""
    <menubar>
      <%= if not match?({:unix, :darwin}, :os.type()) do %>
        <menu label="Eliterm">
          <item onclick="new_terminal"><%= "New Terminal\t#{@cmd_key}+N" %></item>
          <hr/>
          <item onclick="quit"><%= "Quit\t#{@cmd_key}+Q" %></item>
        </menu>
      <% end %>
      <menu label="Edit">
        <item onclick="copy"><%= "Copy (Cmd+C)" %></item>
        <item onclick="paste"><%= "Paste (Cmd+V)" %></item>
      </menu>
      <menu label="Cluster">
        <item onclick="cluster_info">Cluster Info</item>
        <hr/>
        <item onclick="cluster_init">Initialize Cluster</item>
        <item onclick="cluster_join">Join Cluster...</item>
        <item onclick="cluster_leave">Leave Cluster</item>
        <item onclick="cluster_rename">Rename Node...</item>
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
