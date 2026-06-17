defmodule TestHeartWhereis do
  def run do
    IO.inspect(Process.whereis(:heart))
  end
end
TestHeartWhereis.run()
