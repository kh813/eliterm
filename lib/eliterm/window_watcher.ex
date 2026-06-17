defmodule Eliterm.WindowWatcher do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :init)
  end

  def init(:init) do
    # Start polling after 2 seconds
    Process.send_after(self(), :check, 2000)
    {:ok, %{shown: false, last_bounds: nil}}
  end

  def handle_info(:check, state) do
    case Process.whereis(ElitermWindow) do
      nil ->
        if state.shown do
          shutdown_app()
        end
        Process.send_after(self(), :check, 1000)
        {:noreply, state}

      pid ->
        try do
          ui_state = :sys.get_state(pid)
          frame = ui_state.frame

          if frame != nil and :wxFrame.isShown(frame) do
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
            {:noreply, %{state | shown: true, last_bounds: bounds}}
          else
            if state.shown do
              # The window was shown and is now hidden or destroyed!
              shutdown_app()
            end
            Process.send_after(self(), :check, 1000)
            {:noreply, state}
          end
        catch
          _, _ ->
            if state.shown do
              shutdown_app()
            end
            Process.send_after(self(), :check, 1000)
            {:noreply, state}
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
end
