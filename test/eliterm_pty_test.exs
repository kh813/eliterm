defmodule ElitermPTYTest do
  use ExUnit.Case
  alias Eliterm.PTY

  test "get_fallback_shell uses wsl.exe with ~ on Windows if no args provided" do
    {path, args} = PTY.get_fallback_shell({:win32, :nt}, [])
    assert path != nil
    assert args == ["~"]
  end

  test "get_fallback_shell respects existing args on Windows" do
    {path, args} = PTY.get_fallback_shell({:win32, :nt}, ["-c", "ls"])
    assert path != nil
    assert args == ["-c", "ls"]
  end

  test "get_fallback_shell uses bash on unix" do
    {path, args} = PTY.get_fallback_shell({:unix, :darwin}, [])
    assert path != nil
    assert args == []
  end
end
