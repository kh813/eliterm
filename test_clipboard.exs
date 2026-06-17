:wx.new()

clipboard = :wxClipboard.get()
:wxClipboard.open(clipboard)

data_obj = :wxTextDataObject.new([text: "こんにちは"])
:wxClipboard.setData(clipboard, data_obj)
:wxClipboard.close(clipboard)

:wxClipboard.open(clipboard)
data_obj2 = :wxTextDataObject.new()
if :wxClipboard.getData(clipboard, data_obj2) do
  text = :wxTextDataObject.getText(data_obj2)
  IO.puts("Clipboard text: #{text}")
else
  IO.puts("Failed to get clipboard data")
end
:wxClipboard.close(clipboard)

:wx.destroy()
