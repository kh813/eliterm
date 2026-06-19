defmodule ElitermClusterTest do
  use ExUnit.Case, async: false

  setup do
    # Save the original cookie and prefix to restore after tests
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    original_cookie = if File.exists?(cookie_path), do: File.read!(cookie_path), else: nil
    original_prefix = Eliterm.Config.get(["cluster", "node_prefix"])
    original_role = Eliterm.Config.get(["cluster", "role"])
    original_node_alive = Node.alive?()
    original_node_name = Node.self()
    original_node_cookie = if original_node_alive, do: Node.get_cookie(), else: nil
    
    # Ensure every test starts with primary role by default
    Eliterm.Config.put(["cluster", "role"], "primary")

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

      # Restore config role
      if original_role do
        Eliterm.Config.put(["cluster", "role"], original_role)
      else
        Eliterm.Config.put(["cluster", "role"], "primary")
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

  test "Eliterm.Cluster.init/1 with a prefix sets prefix and renames node if alive" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.rm(cookie_path)

    test_prefix = "initnode#{System.unique_integer([:positive])}"
    
    assert :ok == Eliterm.Cluster.init(test_prefix)
    assert File.exists?(cookie_path)
    assert Eliterm.Config.get(["cluster", "node_prefix"]) == test_prefix

    if Node.alive?() do
      assert String.starts_with?(to_string(Node.self()), test_prefix <> "@")
    end
  end

  test "Eliterm.Cluster.info/0 returns node name and cookie" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.write!(cookie_path, "TEST_COOKIE_123")
    Eliterm.Config.put(["cluster", "node_prefix"], "testprefix")
    
    info = Eliterm.Cluster.info()
    assert info.cookie == "TEST_COOKIE_123"

    if Node.alive?() and Node.self() != :nonode@nohost and not String.starts_with?(to_string(Node.self()), "cli_") do
      assert info.full_node == Node.self()
      [expected_prefix, _] = String.split(to_string(Node.self()), "@")
      assert info.cluster_name == expected_prefix
    else
      short_host = Eliterm.local_host()
      assert info.full_node == String.to_atom("testprefix@#{short_host}")
      assert info.node == short_host
      assert info.cluster_name == "testprefix"
    end
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
    File.rm(cookie_path) # Ensure cookie file does not exist
    
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

  test "Eliterm.Cluster.init/1 returns already_initialized if cookie exists" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.write!(cookie_path, "EXISTING_COOKIE")
    
    assert {:error, :already_initialized} == Eliterm.Cluster.init()
  end

  test "Eliterm.Cluster.join/2 returns already_initialized if cookie exists" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.write!(cookie_path, "EXISTING_COOKIE")
    
    assert {:error, :already_initialized} == Eliterm.Cluster.join("some_node@localhost")
  end

  test "Eliterm.Cluster.reset/0 stops node and deletes cookie file" do
    Eliterm.Config.put(["cluster", "role"], "primary")
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.write!(cookie_path, "EXISTING_COOKIE")
    
    assert :ok == Eliterm.Cluster.reset()
    refute File.exists?(cookie_path)
  end

  test "Eliterm.Cluster.rename/1 returns error on secondary and member node" do
    Eliterm.Config.put(["cluster", "role"], "secondary")
    assert {:error, :not_allowed_on_secondary} == Eliterm.Cluster.rename("new_prefix")

    Eliterm.Config.put(["cluster", "role"], "member")
    assert {:error, :not_allowed_on_secondary} == Eliterm.Cluster.rename("new_prefix")
  end

  test "Eliterm.Cluster.reset/0 returns error on secondary and member node" do
    Eliterm.Config.put(["cluster", "role"], "secondary")
    assert {:error, :not_allowed_on_secondary} == Eliterm.Cluster.reset()

    Eliterm.Config.put(["cluster", "role"], "member")
    assert {:error, :not_allowed_on_secondary} == Eliterm.Cluster.reset()
  end

  test "Eliterm.Cluster.invite/0 returns error when cluster is not initialized" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.rm(cookie_path)
    assert {:error, :not_initialized} == Eliterm.Cluster.invite()
  end

  test "Eliterm.Cluster.invite/0 and cancel_invite/0 works correctly when initialized" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.write!(cookie_path, "TEST_INVITE_COOKIE")

    assert {:ok, token, expires_at} = Eliterm.Cluster.invite()
    assert String.match?(token, ~r/^\d{3}-\d{3}$/)
    assert expires_at > DateTime.utc_now() |> DateTime.to_unix()

    status = Eliterm.Cluster.get_invite_status()
    assert status.token == token
    assert status.expires_at == expires_at

    assert :ok == Eliterm.Cluster.cancel_invite()
    assert nil == Eliterm.Cluster.get_invite_status()
  end

  test "Eliterm.Cluster.verify_and_use_token/2 verifies, encrypts cookie and consumes token" do
    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.write!(cookie_path, "TEST_SUPER_SECRET_COOKIE")
    
    assert {:ok, token, _} = Eliterm.Cluster.invite()
    
    {private_key, public_key_der} = Eliterm.Crypto.generate_keypair()
    
    assert {:error, :invalid_token} == Eliterm.Cluster.verify_and_use_token("000-000", public_key_der)
    
    assert {:ok, encrypted_base64} = Eliterm.Cluster.verify_and_use_token(token, public_key_der)
    
    decrypted = Eliterm.Crypto.decrypt_cookie(encrypted_base64, private_key)
    assert decrypted == "TEST_SUPER_SECRET_COOKIE"
    
    assert nil == Eliterm.Cluster.get_invite_status()
    assert {:error, :no_active_invite} == Eliterm.Cluster.verify_and_use_token(token, public_key_der)
  end

  test "Eliterm.Cluster.join/4 handles token join handshake end-to-end" do
    # Enable Phoenix server temporarily for HTTP verification
    orig_config = Application.get_env(:eliterm, ElitermWeb.Endpoint, [])
    Application.put_env(:eliterm, ElitermWeb.Endpoint, Keyword.put(orig_config, :server, true))
    
    Supervisor.terminate_child(Eliterm.Supervisor, ElitermWeb.Endpoint)
    {:ok, _pid} = Supervisor.restart_child(Eliterm.Supervisor, ElitermWeb.Endpoint)

    cookie_path = Path.join(Eliterm.base_dir(), "cookie")
    File.write!(cookie_path, "E2E_TEST_COOKIE_999")
    
    assert {:ok, token, _} = Eliterm.Cluster.invite()
    
    endpoint_config = Application.get_env(:eliterm, ElitermWeb.Endpoint, [])
    http_opts = Keyword.get(endpoint_config, :http, [])
    port = Keyword.get(http_opts, :port)
    
    File.rm(cookie_path)
    
    target_node = "primary@localhost:#{port}"
    res = Eliterm.Cluster.join(target_node, token, "member", port)
    
    # Restore Endpoint server to false to avoid port leaks in other tests
    Application.put_env(:eliterm, ElitermWeb.Endpoint, orig_config)
    Supervisor.terminate_child(Eliterm.Supervisor, ElitermWeb.Endpoint)
    Supervisor.restart_child(Eliterm.Supervisor, ElitermWeb.Endpoint)
    
    assert File.read!(cookie_path) == "E2E_TEST_COOKIE_999"
    assert match?({:error, :connect_failed}, res)
  end
end
