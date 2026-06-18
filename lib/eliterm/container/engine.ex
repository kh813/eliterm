defmodule Eliterm.Container.Engine do
  require Logger

  def executable do
    path = find_docker() || find_podman()
    path
  end

  defp find_docker do
    home = System.get_env("HOME") || "/var/empty"
    paths = [
      "docker", 
      "/opt/homebrew/bin/docker", 
      "/usr/local/bin/docker", 
      "/Applications/Docker.app/Contents/Resources/bin/docker",
      Path.join(home, ".docker/bin/docker"),
      Path.join(home, ".local/bin/docker")
    ]
    Enum.find_value(paths, fn path ->
      exe = System.find_executable(path) || (if File.regular?(path), do: path, else: nil)
      if exe do
        case System.cmd(exe, ["--version"]) do
          {_, 0} -> exe
          _ -> nil
        end
      end
    end)
  rescue
    _ -> nil
  end

  defp find_podman do
    home = System.get_env("HOME") || "/var/empty"
    paths = [
      "podman", 
      "/opt/homebrew/bin/podman", 
      "/usr/local/bin/podman", 
      "/opt/podman/bin/podman",
      Path.join(home, ".local/bin/podman")
    ]
    Enum.find_value(paths, fn path ->
      exe = System.find_executable(path) || (if File.regular?(path), do: path, else: nil)
      if exe do
        case System.cmd(exe, ["--version"]) do
          {_, 0} -> exe
          _ -> nil
        end
      end
    end)
  rescue
    _ -> nil
  end



  def ensure_installed! do
    exe = executable()
    if is_nil(exe) do
      {:error, "Neither docker nor podman is installed. Please install Docker Desktop or Podman."}
    else
      case Path.basename(exe) do
        "docker" -> 
          Logger.info("Using Docker as container engine.")
          :ok
        "podman" -> 
          Logger.info("Using Podman as container engine.")
          if match?({:unix, :darwin}, :os.type()) do
            ensure_podman_machine_running()
          else
            :ok
          end
        _ ->
          {:error, "Unknown engine."}
      end
    end
  end

  defp ensure_podman_machine_running do
    case System.cmd("podman", ["machine", "info"]) do
      {out, 0} ->
        if String.contains?(out, "Running: true") do
          :ok
        else
          Logger.info("Starting podman machine...")
          System.cmd("podman", ["machine", "start"])
          :ok
        end
      _ ->
        {:error, "podman machine is not initialized. Run 'podman machine init' first."}
    end
  end

  def get_host_uid do
    case System.cmd("id", ["-u"]) do
      {out, 0} -> String.trim(out)
      _ -> "1000"
    end
  end

  def get_host_gid do
    case System.cmd("id", ["-g"]) do
      {out, 0} -> String.trim(out)
      _ -> "1000"
    end
  end

  def start_session_container(session_id, home_dir) do
    bin = executable()
    if is_nil(bin) do
      {:error, "No container engine found"}
    else
      ensure_installed!()
      container_name = "eliterm-#{session_id}"

      # Try to start existing container first
      case System.cmd(bin, ["start", container_name]) do
        {_, 0} ->
          {:ok, container_name}
        _ ->
          # Container does not exist or failed to start, create a new one
          System.cmd(bin, ["rm", "-f", container_name])
          args = [
            "run", "-d",
            "--name", container_name,
            "-h", "eliterm",
            "-v", "#{home_dir}:/home/user",
            "-w", "/home/user",
            "docker.io/library/debian:stable-slim",
            "sleep", "infinity"
          ]
          
          case System.cmd(bin, args) do
            {_, 0} -> 
              setup_environment(bin, container_name, home_dir)
              {:ok, container_name}
            {err, _} -> {:error, err}
          end
      end
    end
  end

  def stop_session_container(session_id) do
    if bin = executable() do
      container_name = "eliterm-#{session_id}"
      System.cmd(bin, ["stop", container_name, "-t", "2"])
    end
    :ok
  end

  defp setup_environment(bin, container_name, home_dir) do
    # Run apt-get update first so we can install sudo and other apps immediately
    System.cmd(bin, ["exec", container_name, "apt-get", "update"])
    create_container_user(bin, container_name)
    System.cmd(bin, ["exec", container_name, "mkdir", "-p", "/home/user"])

    # Install netcat-openbsd in container to allow socket communication
    System.cmd(bin, ["exec", container_name, "apt-get", "install", "-y", "netcat-openbsd"])

    # Write proxy script to host and copy it to container as 'admin' command
    proxy_script = """
    #!/bin/sh
    SOCKET_PATH="/home/user/.eliterm-cli.sock"
    if [ ! -S "$SOCKET_PATH" ]; then
      echo "Error: Eliterm CLI socket not found. Make sure you are inside an active Eliterm session." >&2
      exit 1
    fi
    (printf '%d\\n' "$#"; printf '%s\\0' "$@"; cat) | nc -U "$SOCKET_PATH"
    """

    tmp_path = Path.join(home_dir, ".eliterm-proxy-tmp")
    File.write!(tmp_path, proxy_script)
    System.cmd(bin, ["cp", tmp_path, "#{container_name}:/usr/local/bin/admin"])
    File.rm!(tmp_path)

    System.cmd(bin, ["exec", container_name, "chmod", "+x", "/usr/local/bin/admin"])
    
    # Create symlink for 'eliterm' for compatibility
    System.cmd(bin, ["exec", container_name, "ln", "-sf", "/usr/local/bin/admin", "/usr/local/bin/eliterm"])
    
    apps_file = Path.join(home_dir, ".eliterm-apps")
    if File.exists?(apps_file) do
      Logger.info("Installing packages from .eliterm-apps for #{container_name}")
      install_packages(bin, container_name, apps_file)
    end
  end

  defp create_container_user(bin, container_name) do
    uid = get_host_uid()
    gid = get_host_gid()

    if uid != "0" do
      # Create group and user in container matching host UID and GID
      _ = System.cmd(bin, ["exec", container_name, "groupadd", "-g", gid, "usergroup"])
      _ = System.cmd(bin, ["exec", container_name, "useradd", "-u", uid, "-g", gid, "-d", "/home/user", "-s", "/bin/bash", "user"])
      _ = System.cmd(bin, ["exec", container_name, "chown", "-R", "#{uid}:#{gid}", "/home/user"])

      # Install sudo
      _ = System.cmd(bin, ["exec", container_name, "apt-get", "install", "-y", "sudo"])

      # Add user to sudo group
      _ = System.cmd(bin, ["exec", container_name, "usermod", "-aG", "sudo", "user"])

      # Allow passwordless sudo for user
      _ = System.cmd(bin, ["exec", container_name, "sh", "-c", "echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user"])
      _ = System.cmd(bin, ["exec", container_name, "chmod", "0440", "/etc/sudoers.d/user"])
    end
  end

  defp install_packages(bin, container_name, apps_file) do
    content = File.read!(apps_file)
    apt_pkgs = 
      content 
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "apt="))
      |> Enum.flat_map(fn line -> 
           line 
           |> String.replace("apt=", "") 
           |> String.replace(~r/[\[\]"']/, "") 
           |> String.split(",", trim: true) 
           |> Enum.map(&String.trim/1)
         end)

    if length(apt_pkgs) > 0 do
      Logger.info("Apt install: #{inspect(apt_pkgs)}")
      System.cmd(bin, ["exec", container_name, "apt-get", "install", "-y" | apt_pkgs])
    end
  end
end
