defmodule ElitermLiveTest do
  use ExUnit.Case

  test "TerminalLive handle_info pty_exit calls shutdown_app or halt" do
    {:ok, ast} = Code.string_to_quoted(File.read!("lib/eliterm_web/live/terminal_live.ex"))

    found_shutdown = Macro.prewalk(ast, false, fn
      {:., _, [{:__aliases__, _, [:Eliterm, :WindowWatcher]}, :shutdown_app]}, _acc -> {nil, true}
      {:., _, [{:__aliases__, _, [:System]}, :halt]}, _acc -> {nil, true}
      node, acc -> {node, acc}
    end) |> elem(1)

    assert found_shutdown, "TerminalLive should call WindowWatcher.shutdown_app or System.halt(0) on pty_exit"
  end
end
