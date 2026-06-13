defmodule Eliterm.Container.Podman do
  require Logger

  def ensure_installed! do
    case System.cmd("podman", ["--version"]) do
      {_, 0} -> 
        if match?({:unix, :darwin}, :os.type()) do
          ensure_machine_running()
        else
          :ok
        end
      _ -> 
        {:error, "podman is not installed. Please install podman."}
    end
  rescue
    ErlangError -> {:error, "podman command not found"}
  end

  defp ensure_machine_running do
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
    ensure_installed!()

    container_name = "eliterm-#{session_id}"
    System.cmd("podman", ["rm", "-f", container_name])

    args = [
      "run", "-d",
      "--name", container_name,
      "-v", "#{home_dir}:/home/user",
      "-w", "/home/user",
      "docker.io/library/debian:slim",
      "sleep", "infinity"
    ]
    
    case System.cmd("podman", args) do
      {_, 0} -> 
        setup_environment(container_name, home_dir)
        {:ok, container_name}
      {err, _} -> {:error, err}
    end
  end

  def stop_session_container(session_id) do
    container_name = "eliterm-#{session_id}"
    System.cmd("podman", ["rm", "-f", container_name])
    :ok
  end

  defp setup_environment(container_name, home_dir) do
    # Ensure /home/user is fully accessible by the container user (root by default in debian slim)
    System.cmd("podman", ["exec", container_name, "mkdir", "-p", "/home/user"])
    
    apps_file = Path.join(home_dir, ".eliterm-apps")
    if File.exists?(apps_file) do
      Logger.info("Installing packages from .eliterm-apps for #{container_name}")
      install_packages(container_name, apps_file)
    end
  end

  defp install_packages(container_name, apps_file) do
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
      System.cmd("podman", ["exec", container_name, "apt-get", "update"])
      System.cmd("podman", ["exec", container_name, "apt-get", "install", "-y" | apt_pkgs])
    end
  end
end
