defmodule Eliterm.WindowWatcher do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :init)
  end

  def init(:init) do
    # Start polling after 2 seconds
    Process.send_after(self(), :check, 2000)
    {:ok, :hidden}
  end

  def handle_info(:check, state) do
    case Process.whereis(ElitermWindow) do
      nil ->
        if state == :shown do
          System.halt(0)
        end
        Process.send_after(self(), :check, 1000)
        {:noreply, state}

      pid ->
        try do
          ui_state = :sys.get_state(pid)
          frame = ui_state.frame

          if frame != nil and :wxFrame.isShown(frame) do
            Process.send_after(self(), :check, 1000)
            {:noreply, :shown}
          else
            if state == :shown do
              # The window was shown and is now hidden or destroyed!
              System.halt(0)
            end
            Process.send_after(self(), :check, 1000)
            {:noreply, state}
          end
        catch
          _, _ ->
            if state == :shown do
              System.halt(0)
            end
            Process.send_after(self(), :check, 1000)
            {:noreply, state}
        end
    end
  end
end
