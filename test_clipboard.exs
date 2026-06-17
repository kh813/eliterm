# Run with: mix run test_clipboard.exs
defmodule TestClipboard do
  def run do
    # Eliterm.Clipboard is started by the application tree
    Task.async(fn ->
      IO.inspect(Eliterm.Clipboard.copy("test_async"))
    end) |> Task.await()
  end
end
TestClipboard.run()
