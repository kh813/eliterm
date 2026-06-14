defmodule Eliterm.Container.Engine do
  require Logger

  def executable do
    if path = System.find_executable("docker") do
      case System.cmd(path, ["--version"]) do
        {_, 0} -> path
        _ -> check_podman()
      end
    else
      check_podman()
    end
  rescue
    ErlangError -> check_podman()
  end

  defp check_podman do
    if path = System.find_executable("podman") do
      case System.cmd(path, ["--version"]) do
        {_, 0} -> path
        _ -> nil
      end
    else
      nil
    end
  rescue
    ErlangError -> nil
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
    System.cmd(bin, ["exec", container_name, "mkdir", "-p", "/home/user"])
    
    apps_file = Path.join(home_dir, ".eliterm-apps")
    if File.exists?(apps_file) do
      Logger.info("Installing packages from .eliterm-apps for #{container_name}")
      install_packages(bin, container_name, apps_file)
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
      System.cmd(bin, ["exec", container_name, "apt-get", "update"])
      System.cmd(bin, ["exec", container_name, "apt-get", "install", "-y" | apt_pkgs])
    end
  end
end
