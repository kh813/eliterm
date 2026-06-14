defmodule Eliterm.AppManager do
  @moduledoc """
  Manages persistent application installation via .eliterm-apps.
  """
  require Logger

  def install_app(session_id, pkg) do
    home_dir = Path.join([Eliterm.base_dir(), "sessions", session_id, "home"])
    apps_file = Path.join(home_dir, ".eliterm-apps")
    
    # 1. Update the .eliterm-apps schema file
    File.mkdir_p!(home_dir)
    content = if File.exists?(apps_file), do: File.read!(apps_file), else: ""
    
    unless String.contains?(content, "apt=#{pkg}") do
      new_content = content <> "\napt=#{pkg}\n"
      File.write!(apps_file, new_content)
    end

    # 2. Try to dynamically install it in the running container if available
    bin = Eliterm.Container.Engine.executable()
    container_name = "eliterm-#{session_id}"
    
    if bin do
      # We just fire and forget or wait for the result
      Logger.info("Installing #{pkg} in container #{container_name}...")
      case System.cmd(bin, ["exec", container_name, "apt-get", "update"]) do
        {_, 0} ->
          case System.cmd(bin, ["exec", container_name, "apt-get", "install", "-y", pkg]) do
            {_, 0} -> {:ok, "Successfully installed #{pkg} and persisted to .eliterm-apps."}
            {err, _} -> {:error, "Failed to install in container: #{err}"}
          end
        {err, _} -> {:error, "Failed to update apt: #{err}"}
      end
    else
      {:ok, "Added #{pkg} to .eliterm-apps. (Container engine not running locally)."}
    end
  end
  
  def list_apps(session_id) do
    home_dir = Path.join([Eliterm.base_dir(), "sessions", session_id, "home"])
    apps_file = Path.join(home_dir, ".eliterm-apps")
    
    if File.exists?(apps_file) do
      content = File.read!(apps_file)
      pkgs = 
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
      {:ok, "Installed packages: " <> Enum.join(pkgs, ", ")}
    else
      {:ok, "No packages installed via eliterm-apps."}
    end
  end
end
