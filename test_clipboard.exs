defmodule TestClipboard do
  def run do
    :wx.new()
    Task.async(fn ->
      IO.inspect(Eliterm.Clipboard.copy("test_async"))
    end) |> Task.await()
  end
end
TestClipboard.run()
