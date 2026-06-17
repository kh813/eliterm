defmodule ElitermMenuBarTest do
  use ExUnit.Case
  import Phoenix.LiveViewTest
  alias ElitermWeb.MenuBar

  test "render/1 returns valid menubar markup with fonts" do
    scanned_fonts = ["Fira Code", "Hack"]
    assigns = %{scanned_fonts: scanned_fonts}
    
    html = rendered_to_string(MenuBar.render(assigns))
    
    assert html =~ "Default"
    assert html =~ "Scan &amp; update font list"
    assert html =~ "Fira Code"
    assert html =~ "Hack"
    
    if match?({:unix, :darwin}, :os.type()) do
      assert html =~ "Menlo"
      assert html =~ "Monaco"
    else
      assert html =~ "Consolas"
    end
  end
end
