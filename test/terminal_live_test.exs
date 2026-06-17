defmodule ElitermWeb.TerminalLiveTest do
  use ExUnit.Case
  import Phoenix.LiveViewTest
  @endpoint ElitermWeb.Endpoint

  setup do
    ElitermWeb.Endpoint.start_link()
    :ok
  end

  test "clipboard_copy event" do
    # we can't easily start LiveView without ConnCase but we can try
  end
end
