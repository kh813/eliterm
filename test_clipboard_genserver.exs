defmodule TestGenserver do
  def run do
    defmodule ClipboardServer do
      use GenServer
      def start_link, do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      def init(_) do
        :wx.new()
        {:ok, nil}
      end
      def handle_call({:copy, text}, _, state) do
        cb = :wxClipboard.get()
        res = if :wxClipboard.open(cb) do
          obj = :wxTextDataObject.new(text: text)
          :wxClipboard.setData(cb, obj)
          :wxClipboard.close(cb)
          :ok
        else
          :error
        end
        {:reply, res, state}
      end
    end
    
    ClipboardServer.start_link()
    
    Task.async(fn ->
      IO.inspect(GenServer.call(ClipboardServer, {:copy, "testing_genserver"}))
    end) |> Task.await()
  end
end
TestGenserver.run()
