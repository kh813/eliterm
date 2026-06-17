defmodule ElitermWindowWatcherTest do
  use ExUnit.Case

  test "shutdown_app logic contains epmd kill and halt" do
    # Verify that shutdown_app is exported
    assert function_exported?(Eliterm.WindowWatcher, :shutdown_app, 0)

    # Read the AST of window_watcher.ex
    {:ok, ast} = Code.string_to_quoted(File.read!("lib/eliterm/window_watcher.ex"))

    # Ensure System.halt(0) is used instead of System.stop(0)
    found_halt = Macro.prewalk(ast, false, fn
      {:., _, [{:__aliases__, _, [:System]}, :halt]}, _acc -> {nil, true}
      node, acc -> {node, acc}
    end) |> elem(1)

    assert found_halt, "shutdown_app should call System.halt(0)"

    # Ensure epmd -kill is executed
    found_epmd = Macro.prewalk(ast, false, fn
      {_, _, ["epmd", ["-kill"]]}, _acc -> {nil, true}
      node, acc -> {node, acc}
    end) |> elem(1)

    assert found_epmd, "shutdown_app should execute System.cmd(\"epmd\", [\"-kill\"])"
  end
end
