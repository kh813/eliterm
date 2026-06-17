defmodule ElitermClipboardTest do
  use ExUnit.Case

  test "can copy and paste text via native OS clipboard (Windows/Mac support)" do
    # Ensure wx is running since Eliterm.Clipboard depends on it
    if :wx.is_null(:wx.null()) do
      :wx.new()
    end
    
    test_string = "Eliterm Clipboard Test #{System.unique_integer()}"
    
    # 1. Verify we can copy
    assert :ok == Eliterm.Clipboard.copy(test_string)
    
    # 2. Verify we can paste and it matches exactly what was copied
    assert {:ok, ^test_string} = Eliterm.Clipboard.paste()
  end
end
