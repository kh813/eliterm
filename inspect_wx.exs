defmodule InspectWx do
  def run do
    pid = Process.whereis(ElitermWindow)
    if pid do
      IO.inspect(:sys.get_state(pid))
    end
  end
end
InspectWx.run()
