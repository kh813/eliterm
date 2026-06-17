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
    GenServer.call(__MODULE__, {:copy, text})
  end

  def paste do
    GenServer.call(__MODULE__, :paste)
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

  defp do_copy(_clipboard, _text, 0), do: {:error, :clipboard_open_failed}
  defp do_copy(clipboard, text, retries) do
    if :wxClipboard.open(clipboard) do
      data_obj = :wxTextDataObject.new(text: text)
      :wxClipboard.setData(clipboard, data_obj)
      :wxClipboard.close(clipboard)
      :ok
    else
      Process.sleep(50)
      do_copy(clipboard, text, retries - 1)
    end
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
