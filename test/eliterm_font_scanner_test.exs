defmodule ElitermFontScannerTest do
  use ExUnit.Case
  alias Eliterm.FontScanner

  test "scan/0 returns a list of installed developer fonts" do
    fonts = FontScanner.scan()
    assert is_list(fonts)
    
    # Check that any returned font is one of the known fonts
    known_fonts = ["Fira Code", "Cascadia Code", "Source Code Pro", "Hack", "JetBrains Mono", "Ubuntu Mono"]
    Enum.each(fonts, fn font ->
      assert font in known_fonts
    end)
  end
end
