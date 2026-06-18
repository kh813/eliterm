defmodule ElitermClusterTest do
  use ExUnit.Case, async: false

  setup do
    # Save the original cookie and prefix to restore after tests
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    original_cookie = if File.exists?(cookie_path), do: File.read!(cookie_path), else: nil
    original_prefix = Eliterm.Config.get(["cluster", "node_prefix"])
    original_node_alive = Node.alive?()
    original_node_name = Node.self()
    original_node_cookie = if original_node_alive, do: Node.get_cookie(), else: nil
    
    on_exit(fn ->
      # Restore cookie file
      if original_cookie do
        File.write!(cookie_path, original_cookie)
      else
        File.rm(cookie_path)
      end
      
      # Restore config prefix
      if original_prefix do
        Eliterm.Config.put(["cluster", "node_prefix"], original_prefix)
      else
        Eliterm.Config.put(["cluster"], %{})
      end

      # Restore Erlang distribution state if we modified it
      if original_node_alive do
        unless Node.alive?() do
          Node.start(original_node_name, :shortnames)
        end
        if Node.self() != original_node_name do
          Node.stop()
          Node.start(original_node_name, :shortnames)
        end
        Node.set_cookie(original_node_cookie)
      else
        if Node.alive?() do
          Node.stop()
        end
      end
    end)

    :ok
  end

  test "Eliterm.Cluster.init/0 generates cookie file and sets it if node is alive" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.rm(cookie_path) # Ensure it doesn't exist

    assert :ok == Eliterm.Cluster.init()
    assert File.exists?(cookie_path)
    
    generated_cookie = File.read!(cookie_path)
    assert byte_size(generated_cookie) > 0
    
    if Node.alive?() do
      assert Node.get_cookie() == String.to_atom(generated_cookie)
    end
  end

  test "Eliterm.Cluster.info/0 returns node name and cookie" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.write!(cookie_path, "TEST_COOKIE_123")
    
    info = Eliterm.Cluster.info()
    assert info.node == Node.self()
    assert info.cookie == "TEST_COOKIE_123"
  end

  test "Eliterm.Cluster.rename/1 updates TOML config and restarts distribution if alive" do
    # We test with a test prefix
    test_prefix = "testnode#{System.unique_integer([:positive])}"
    
    # Save current status
    was_alive = Node.alive?()
    
    # Run rename
    res = Eliterm.Cluster.rename(test_prefix)
    
    # Assert config was saved
    assert Eliterm.Config.get(["cluster", "node_prefix"]) == test_prefix
    
    if was_alive do
      assert {:ok, new_node_name} = res
      assert String.starts_with?(to_string(new_node_name), test_prefix <> "@")
      assert Node.alive?()
      assert Node.self() == new_node_name
    else
      assert res == :ok
    end
  end

  test "Eliterm.Cluster.join/2 sets and persists cookie if passed" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    
    # Join with a dummy node and dummy cookie
    dummy_node = "non_existent_node@localhost"
    dummy_cookie = "JOIN_TEST_COOKIE_555"
    
    # Join will fail with connect_failed or ignored, but it should still set and persist the cookie!
    res = Eliterm.Cluster.join(dummy_node, dummy_cookie)
    
    assert match?({:error, _}, res)
    assert File.read!(cookie_path) == dummy_cookie
    
    if Node.alive?() do
      assert Node.get_cookie() == :JOIN_TEST_COOKIE_555
    end
  end
end
