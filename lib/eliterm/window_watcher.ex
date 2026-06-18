defmodule Eliterm.WindowWatcher do
  use GenServer
  require Logger

  # Require wx records for command event matching
  require Record
  for tag <- [:wx, :wxCommand] do
    Record.defrecordp(tag, Record.extract(tag, from_lib: "wx/include/wx.hrl"))
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :init)
  end

  def init(:init) do
    # Start polling after 2 seconds
    Process.send_after(self(), :check, 2000)
    {:ok, %{shown: false, last_bounds: nil, menu_adjusted: false}}
  end

  def handle_info(
        wx(event: wxCommand(type: :command_menu_selected), userData: "new_terminal"),
        state
      ) do
    if match?({:unix, :darwin}, :os.type()) do
      System.cmd("open", ["-n", "-a", "Eliterm"])
    end
    {:noreply, state}
  end

  def handle_info(
        wx(event: wxCommand(type: :command_menu_selected), userData: "quit"),
        state
      ) do
    if confirm_quit?() do
      shutdown_app()
    end
    {:noreply, state}
  end

  def handle_info(:check, state) do
    case Process.whereis(ElitermWindow) do
      nil ->
        # Just update state to hidden, don't kill the app!
        Process.send_after(self(), :check, 1000)
        {:noreply, %{state | shown: false}}

      pid ->
        try do
          ui_state = :sys.get_state(pid)
          frame = ui_state.frame

          if frame != nil and :wxFrame.isShown(frame) do
            state = if not state.menu_adjusted do
              adjust_mac_menu(frame)
              %{state | menu_adjusted: true}
            else
              state
            end

            if not state.shown do
              # First time the window is shown, restore position
              x = Eliterm.Config.get(["gui", "window", "x"])
              y = Eliterm.Config.get(["gui", "window", "y"])
              if x != nil and y != nil do
                :wxWindow.move(frame, {x, y})
              end
            end

            {w, h} = :wxWindow.getSize(frame)
            {x, y} = :wxWindow.getPosition(frame)
            bounds = %{"width" => w, "height" => h, "x" => x, "y" => y}

            if state.shown and state.last_bounds != nil and state.last_bounds != bounds do
              Eliterm.Config.put(["gui", "window"], bounds)
            end

            Process.send_after(self(), :check, 1000)
            {:noreply, %{state | shown: true, last_bounds: bounds, menu_adjusted: state.menu_adjusted}}
          else
            Process.send_after(self(), :check, 1000)
            {:noreply, %{state | shown: false}}
          end
        catch
          _, _ ->
            Process.send_after(self(), :check, 1000)
            {:noreply, %{state | shown: false}}
        end
    end
  end

  def shutdown_app do
    if match?({:win32, :nt}, :os.type()) do
      # epmd.exe locks the release folder. We must kill it before halting.
      System.cmd("epmd", ["-kill"])
    end
    System.halt(0)
  end

  defp adjust_mac_menu(frame) do
    if match?({:unix, :darwin}, :os.type()) do
      try do
        menubar = :wxFrame.getMenuBar(frame)
        if menubar != nil and not :wx.is_null(menubar) do
          apple_menu = :wxMenuBar.oSXGetAppleMenu(menubar)
          if apple_menu != nil and not :wx.is_null(apple_menu) do
            items = :wxMenu.getMenuItems(apple_menu)
            wx_id_exit = Desktop.Wx.wxID_EXIT()

            # Find standard quit item
            quit_item = Enum.find(items, fn item ->
              :wxMenuItem.getId(item) == wx_id_exit
            end)

            # Check if New Terminal is already added
            has_new_terminal = Enum.any?(items, fn item ->
              label = :wxMenuItem.getItemLabel(item) |> to_string()
              String.contains?(label, "New Terminal")
            end)

            if not has_new_terminal do
              new_term_id = 10001
              new_term_item = :wxMenuItem.new(id: new_term_id, text: ~c"New Terminal\tCmd+N")
              :wxMenu.insert(apple_menu, 0, new_term_item)
              :wxMenu.connect(self(), :command_menu_selected, id: new_term_id, userData: "new_terminal")
            end

            if quit_item != nil do
              # Recreate standard quit item with a custom ID so we can intercept it
              :wxMenu.delete(apple_menu, quit_item)

              custom_quit_id = 10002
              new_quit_item = :wxMenuItem.new(id: custom_quit_id, text: ~c"Quit Eliterm\tCmd+Q")
              :wxMenu.append(apple_menu, new_quit_item)
              :wxMenu.connect(self(), :command_menu_selected, id: custom_quit_id, userData: "quit")
            end
          end
        end
      rescue
        e ->
          Logger.error("Failed to adjust macOS application menu: #{inspect(e)}")
      end
    end
  end

  defp confirm_quit? do
    if should_confirm_quit?() do
      msg = ~c"Elitermを終了してもよろしいですか？\n実行中のバックグラウンドセッションやcronジョブがすべて終了します。"
      caption = ~c"終了の確認"
      style = 1162 # wxYES_NO | wxICON_QUESTION | wxNO_DEFAULT

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
    else
      true
    end
  end

  defp should_confirm_quit? do
    Code.ensure_loaded?(:wx) and not :wx.is_null(:wx.null())
  end
end
