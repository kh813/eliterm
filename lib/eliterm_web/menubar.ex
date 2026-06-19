defmodule ElitermWeb.MenuBar do
  use Desktop.Menu
  require Logger

  @impl true
  def mount(menu) do
    scanned_fonts = Eliterm.Config.get(["gui", "scanned_fonts"], [])
    cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
    initialized = File.exists?(cookie_path)
    role = Eliterm.Config.get(["cluster", "role"], "primary")

    if Code.ensure_loaded?(Phoenix.PubSub) do
      Phoenix.PubSub.subscribe(Eliterm.PubSub, "cluster")
    end

    {:ok,
     menu
     |> Desktop.Menu.assign(:scanned_fonts, scanned_fonts)
     |> Desktop.Menu.assign(:initialized, initialized)
     |> Desktop.Menu.assign(:role, role)}
  end

  @impl true
  def handle_info(:cluster_state_changed, menu) do
    cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
    initialized = File.exists?(cookie_path)
    role = Eliterm.Config.get(["cluster", "role"], "primary")

    {:noreply,
     menu
     |> Desktop.Menu.assign(:initialized, initialized)
     |> Desktop.Menu.assign(:role, role)}
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
    msg = ~c"Cluster Name: #{info.cluster_name}\nNode: #{info.node}\nJoin Target: #{info.full_node}\nCookie: #{info.cookie}"
    caption = ~c"Cluster Info"
    show_message_dialog(msg, caption, 1024) # wxICON_INFORMATION
    {:noreply, menu}
  end

  def handle_event("cluster_invite", menu) do
    port = case Application.get_env(:eliterm, ElitermWeb.Endpoint, []) do
      config when is_list(config) ->
        Keyword.get(config, :http, []) |> Keyword.get(:port, 4000)
      _ ->
        4000
    end

    case Eliterm.Cluster.invite() do
      {:ok, token, _expires_at} ->
        msg = ~c"Cluster invite mode started.\n\nInvite Token: #{token}\nPrimary Port: #{port}\nExpires in: 5 minutes\n\nDo you want to keep waiting? (If you click 'No', the invite session will be terminated immediately)"
        caption = ~c"Invite Node"
        style = 1162 # wxYES_NO | wxICON_QUESTION | wxNO_DEFAULT
        
        unless show_confirm_dialog(msg, caption, style) do
          Eliterm.Cluster.cancel_invite()
          show_message_dialog(~c"Invite session terminated. Token is now invalid.", ~c"Success", 1024)
        end
      {:error, reason} ->
        show_message_dialog(~c"Error starting invite: #{inspect(reason)}", ~c"Error", 256)
    end
    {:noreply, menu}
  end

  def handle_event("cluster_init", menu) do
    cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
    if File.exists?(cookie_path) do
      show_message_dialog(~c"Error: Cluster is already initialized.\nPlease reset the cluster first.", ~c"Error", 256)
      {:noreply, menu}
    else
      current_prefix = Eliterm.Config.get(["cluster", "node_prefix"], "eliterm")
      case show_text_entry_dialog(~c"Enter cluster node prefix:", ~c"Initialize Cluster", to_charlist(current_prefix)) do
        {:ok, prefix} ->
          Eliterm.Cluster.init(prefix)
          show_message_dialog(~c"Cluster initialized successfully with prefix '#{prefix}'.", ~c"Success", 1024)
          menu = menu |> Desktop.Menu.assign(:initialized, true) |> Desktop.Menu.assign(:role, "primary")
          {:noreply, menu}
        :cancel ->
          {:noreply, menu}
      end
    end
  end

  def handle_event("cluster_rename", menu) do
    if not Eliterm.Cluster.primary?() do
      show_message_dialog(~c"Error: Rename is only allowed on the primary (management) node.", ~c"Error", 256)
    else
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
    end
    {:noreply, menu}
  end

  def handle_event("cluster_join", menu) do
    cookie_path = Path.join([Eliterm.base_dir(), "cookie"])
    if File.exists?(cookie_path) do
      show_message_dialog(~c"Error: Cluster is already initialized.\nPlease reset the cluster first.", ~c"Error", 256)
      {:noreply, menu}
    else
      case show_text_entry_dialog(~c"Enter target node to join (e.g. eliterm@hostname):", ~c"Join Cluster", ~c"") do
        {:ok, target_node} ->
          case show_text_entry_dialog(~c"Enter cluster cookie (leave empty to use current cookie):", ~c"Join Cluster - Cookie", ~c"") do
            {:ok, cookie} ->
              cookie_arg = if cookie == "", do: nil, else: cookie

              # ロール（セカンダリ権限）を付与するか確認
              msg = ~c"Do you want to join this node as a Secondary Node?\n\nIf Yes, this node will join as a Secondary Node.\nIf No, this node will join as a standard Member Node."
              caption = ~c"Join as Secondary?"
              role = if show_confirm_dialog(msg, caption, 1162) do
                "secondary"
              else
                "member"
              end

              case Eliterm.Cluster.join(target_node, cookie_arg, role) do
                :ok ->
                  show_message_dialog(~c"Successfully joined cluster as #{role}.", ~c"Success", 1024)
                  menu = menu |> Desktop.Menu.assign(:initialized, true) |> Desktop.Menu.assign(:role, role)
                  {:noreply, menu}
                {:error, reason} ->
                  show_message_dialog(~c"Failed to join cluster: #{inspect(reason)}", ~c"Error", 256)
                  {:noreply, menu}
              end
            :cancel ->
              {:noreply, menu}
          end
        :cancel ->
          {:noreply, menu}
      end
    end
  end

  def handle_event("cluster_leave", menu) do
    msg = ~c"Are you sure you want to leave the cluster?\nThis will stop Erlang distribution and delete the cookie."
    caption = ~c"Leave Cluster?"
    style = 1162 # wxYES_NO | wxICON_QUESTION | wxNO_DEFAULT
    
    menu = if show_confirm_dialog(msg, caption, style) do
      Eliterm.Cluster.leave()
      show_message_dialog(~c"Successfully left the cluster.", ~c"Success", 1024)
      menu |> Desktop.Menu.assign(:initialized, false) |> Desktop.Menu.assign(:role, "primary")
    else
      menu
    end
    {:noreply, menu}
  end

  def handle_event("cluster_reset", menu) do
    if not Eliterm.Cluster.primary?() do
      show_message_dialog(~c"Error: Reset is only allowed on the primary (management) node.", ~c"Error", 256)
      {:noreply, menu}
    else
      other_nodes = Node.list()
      msg = if other_nodes != [] do
        node_strs = Enum.map(other_nodes, &to_string/1) |> Enum.join(", ")
        ~c"Are you sure you want to reset the cluster?\n\nThe following connected nodes will be forced to leave and reset:\n#{node_strs}\n\nThis will stop Erlang distribution and delete the cookie file on all nodes."
      else
        ~c"Are you sure you want to reset the cluster?\nThis will stop Erlang distribution and delete the cookie file."
      end
      caption = ~c"Reset Cluster?"
      style = 1162 # wxYES_NO | wxICON_QUESTION | wxNO_DEFAULT
      
      menu = if show_confirm_dialog(msg, caption, style) do
        Eliterm.Cluster.reset()
        show_message_dialog(~c"Cluster reset successfully.", ~c"Success", 1024)
        menu |> Desktop.Menu.assign(:initialized, false) |> Desktop.Menu.assign(:role, "primary")
      else
        menu
      end
      {:noreply, menu}
    end
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
    
    assigns = assigns
              |> Map.put_new(:cmd_key, cmd_key)
              |> Map.put_new(:initialized, false)
              |> Map.put_new(:role, "primary")
              |> Map.put_new(:scanned_fonts, [])

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
        <%= if @initialized do %>
          <item onclick="cluster_info">Cluster Info</item>
          <hr/>
          <%= if @role == "primary" do %>
            <item onclick="cluster_invite">Invite Node...</item>
            <item onclick="cluster_rename">Rename Node...</item>
            <item onclick="cluster_reset">Reset Cluster</item>
          <% end %>
          <%= if @role == "secondary" do %>
            <item onclick="cluster_leave">Leave Cluster</item>
          <% end %>
          <%= if @role == "member" do %>
            <item onclick="cluster_leave">Leave Cluster</item>
          <% end %>
        <% else %>
          <item onclick="cluster_init">Initialize Cluster</item>
          <item onclick="cluster_join">Join Cluster...</item>
        <% end %>
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
