defmodule Eliterm.Clipboard do
  @moduledoc """
  Handles native OS clipboard interactions via wxWidgets.
  This allows reliable copy and paste in desktop GUI environments where 
  WebViews might restrict the Async Clipboard API.
  """

  def copy(text) when is_binary(text) do
    if :wx.is_null(:wx.null()) do # Check if wx is running, though in Desktop it always is
      clipboard = :wxClipboard.get()
      if :wxClipboard.open(clipboard) do
        # Use binary string directly as :unicode.chardata()
        data_obj = :wxTextDataObject.new(text: text)
        :wxClipboard.setData(clipboard, data_obj)
        :wxClipboard.close(clipboard)
        :ok
      else
        {:error, :clipboard_open_failed}
      end
    else
      {:error, :wx_not_running}
    end
  rescue
    e -> {:error, e}
  end

  def paste do
    if :wx.is_null(:wx.null()) do
      clipboard = :wxClipboard.get()
      if :wxClipboard.open(clipboard) do
        data_obj = :wxTextDataObject.new()
        result =
          if :wxClipboard.getData(clipboard, data_obj) do
            text = :wxTextDataObject.getText(data_obj)
            {:ok, to_string(text)}
          else
            {:ok, ""}
          end
        :wxClipboard.close(clipboard)
        result
      else
        {:error, :clipboard_open_failed}
      end
    else
      {:error, :wx_not_running}
    end
  rescue
    e -> {:error, e}
  end
end
