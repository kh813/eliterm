defmodule Eliterm.CLITest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  test "CLI main entrypoint handles connection failure and outputs error" do
    # Validate that Eliterm.CLI.main captures node failure correctly and outputs the appropriate daemon message to stdout.
    # We trap the exit call since execute_rpc will System.halt(1) on failure.
    output = capture_io(fn ->
      try do
        Eliterm.CLI.main(["list", "nodes", "--node", "non_existent@localhost"])
      catch
        :exit, _ -> :ok
      end
    end)

    assert output =~ "Eliterm daemon is not running on non_existent@localhost"
  end
end
