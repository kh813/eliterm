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

  test "render/1 returns menu options based on cluster initialization and roles" do
    # 1. Not initialized
    assigns = %{initialized: false, role: "primary"}
    html = rendered_to_string(MenuBar.render(assigns))
    assert html =~ "Initialize Cluster"
    assert html =~ "Join Cluster..."
    refute html =~ "Cluster Info"
    refute html =~ "Rename Node..."
    refute html =~ "Reset Cluster"
    refute html =~ "Leave Cluster"

    # 2. Initialized as primary
    assigns = %{initialized: true, role: "primary"}
    html = rendered_to_string(MenuBar.render(assigns))
    refute html =~ "Initialize Cluster"
    refute html =~ "Join Cluster..."
    assert html =~ "Cluster Info"
    assert html =~ "Rename Node..."
    assert html =~ "Reset Cluster"
    refute html =~ "Leave Cluster"

    # 3. Initialized as secondary
    assigns = %{initialized: true, role: "secondary"}
    html = rendered_to_string(MenuBar.render(assigns))
    refute html =~ "Initialize Cluster"
    refute html =~ "Join Cluster..."
    assert html =~ "Cluster Info"
    refute html =~ "Rename Node..."
    refute html =~ "Reset Cluster"
    assert html =~ "Leave Cluster"

    # 4. Initialized as member
    assigns = %{initialized: true, role: "member"}
    html = rendered_to_string(MenuBar.render(assigns))
    refute html =~ "Initialize Cluster"
    refute html =~ "Join Cluster..."
    assert html =~ "Cluster Info"
    refute html =~ "Rename Node..."
    refute html =~ "Reset Cluster"
    assert html =~ "Leave Cluster"
  end
end
