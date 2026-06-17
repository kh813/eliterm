defmodule ElitermDependencyCheckerTest do
  use ExUnit.Case, async: false
  alias Eliterm.DependencyChecker

  test "has_container_engine? returns true when docker or podman is in PATH" do
    # Assuming the environment running this test has at least one of them
    assert DependencyChecker.has_container_engine?() == true
  end

  test "has_container_engine? returns false when PATH is empty" do
    original_path = System.get_env("PATH")
    System.put_env("PATH", "")
    
    try do
      assert DependencyChecker.has_container_engine?() == false
    after
      System.put_env("PATH", original_path)
    end
  end
end
