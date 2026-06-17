defmodule Eliterm.Clipboard do
  @moduledoc """
  Handles native OS clipboard interactions via wxWidgets.
  Runs as a GenServer to maintain its own wxWidgets environment, allowing
  any other process (like LiveView) to safely access the clipboard.
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    # Initialize wx environment for this GenServer process
    :wx.new()
    {:ok, nil}
  end

  def copy(text) when is_binary(text) do
    if match?({:unix, :darwin}, :os.type()) do
      try do
        temp_file = Path.join(System.tmp_dir!(), "eliterm_cb_#{System.unique_integer([:positive])}")
        File.write!(temp_file, text)
        try do
          case System.cmd("sh", ["-c", "pbcopy < #{temp_file}"]) do
            {_, 0} -> :ok
            {_, status} -> {:error, {:pbcopy_failed, status}}
          end
        after
          File.rm(temp_file)
        end
      rescue
        e ->
          Logger.error("Failed to copy using pbcopy: #{inspect(e)}")
          {:error, e}
      end
    else
      GenServer.call(__MODULE__, {:copy, text})
    end
  end

  def paste do
    if match?({:unix, :darwin}, :os.type()) do
      try do
        case System.cmd("pbpaste", []) do
          {out, 0} -> {:ok, out}
          {_, status} -> {:error, {:pbpaste_failed, status}}
        end
      rescue
        e ->
          Logger.error("Failed to paste using pbpaste: #{inspect(e)}")
          {:error, e}
      end
    else
      GenServer.call(__MODULE__, :paste)
    end
  end

  def handle_call({:copy, text}, _from, state) do
    clipboard = :wxClipboard.get()
    result = do_copy(clipboard, text, 10)
    if result != :ok do
      Logger.error("Failed to copy to clipboard after retries")
    end
    {:reply, result, state}
  rescue
    e -> {:reply, {:error, e}, state}
  end

  def handle_call(:paste, _from, state) do
    clipboard = :wxClipboard.get()
    result = do_paste(clipboard, 10)
    if match?({:error, _}, result) do
      Logger.error("Failed to paste from clipboard after retries")
    end
    {:reply, result, state}
  rescue
    e -> {:reply, {:error, e}, state}
  end

  defp do_copy(_clipboard, _text, 0), do: {:error, :clipboard_open_failed}
  defp do_copy(clipboard, text, retries) do
    if :wxClipboard.open(clipboard) do
      data_obj = :wxTextDataObject.new(text: text)
      if :wxClipboard.setData(clipboard, data_obj) do
        :wxClipboard.flush(clipboard)
      else
        Logger.error("wxClipboard.setData returned false")
      end
      :wxClipboard.close(clipboard)
      :ok
    else
      Process.sleep(50)
      do_copy(clipboard, text, retries - 1)
    end
  end

  defp do_paste(_clipboard, 0), do: {:error, :clipboard_open_failed}
  defp do_paste(clipboard, retries) do
    if :wxClipboard.open(clipboard) do
      data_obj = :wxTextDataObject.new()
      res =
        if :wxClipboard.getData(clipboard, data_obj) do
          text = :wxTextDataObject.getText(data_obj)
          {:ok, to_string(text)}
        else
          {:ok, ""}
        end
      :wxClipboard.close(clipboard)
      res
    else
      Process.sleep(50)
      do_paste(clipboard, retries - 1)
    end
  end
end
