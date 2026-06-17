defmodule TestDesktopState do
  def run do
    # We can get the state of Desktop.Window
    case Process.whereis(ElitermWindow) do
      nil -> IO.puts("Window not found")
      pid -> 
        state = :sys.get_state(pid)
        IO.inspect(state)
        if Map.get(state, :taskbar) != nil do
          IO.puts("TASKBAR IS NOT NIL!")
        else
          IO.puts("TASKBAR IS NIL!")
        end
    end
  end
end
