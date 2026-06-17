defmodule ElitermContainerEngineTest do
  use ExUnit.Case
  alias Eliterm.Container.Engine

  test "get_host_uid/0 returns a valid UID string" do
    uid = Engine.get_host_uid()
    assert is_binary(uid)
    assert Regex.match?(~r/^\d+$/, uid)
  end

  test "get_host_gid/0 returns a valid GID string" do
    gid = Engine.get_host_gid()
    assert is_binary(gid)
    assert Regex.match?(~r/^\d+$/, gid)
  end

  test "executable/0 returns a binary path or nil" do
    exe = Engine.executable()
    if exe do
      assert is_binary(exe)
      assert File.exists?(exe) || System.find_executable(exe)
    else
      assert is_nil(exe)
    end
  end
end
