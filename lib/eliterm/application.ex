defmodule Eliterm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Dynamically start distribution if not already running
    unless Node.alive?() do
      prefix = Eliterm.Config.get(["cluster", "node_prefix"], "eliterm")
      short_host = Eliterm.local_host()
      node_name = String.to_atom("#{prefix}@#{short_host}")
      
      case Node.start(node_name, :shortnames) do
        {:ok, _} -> 
          cookie_path = Path.join(Eliterm.base_dir(), "cookie")
          if File.exists?(cookie_path) do
            Node.set_cookie(String.to_atom(File.read!(cookie_path)))
          end
        {:error, reason} -> 
          IO.puts(:stderr, "Failed to start Erlang distribution dynamically: #{inspect(reason)}")
      end
    end

    if Application.get_env(:eliterm, :check_dependencies, true) do
      Eliterm.DependencyChecker.check_and_halt_if_missing!()
    end
    
    port = get_free_port()
    
    endpoint_config = Application.get_env(:eliterm, ElitermWeb.Endpoint)
    http_opts = Keyword.get(endpoint_config, :http, []) |> Keyword.put(:port, port)
    http_opts = if System.get_env("ELITERM_HEADLESS") == "true" do
      Keyword.put(http_opts, :ip, {0, 0, 0, 0})
    else
      Keyword.put_new(http_opts, :ip, {127, 0, 0, 1})
    end
    Application.put_env(:eliterm, ElitermWeb.Endpoint, Keyword.put(endpoint_config, :http, http_opts))


    ports = [45892, 45893, 45894, 45895]
    topologies = Enum.reduce(ports, [], fn port, acc ->
      case :gen_udp.open(port, [:binary, active: 10, reuseaddr: true]) do
        {:ok, socket} ->
          :gen_udp.close(socket)
          name = String.to_atom("eliterm_gossip_#{port}")
          [{name, [strategy: Cluster.Strategy.Gossip, config: [port: port]]} | acc]
        {:error, _reason} ->
          acc
      end
    end)

    children = [
      Eliterm.Scheduler,
      {Cluster.Supervisor, [topologies, [name: Eliterm.ClusterSupervisor]]},
      {Phoenix.PubSub, name: Eliterm.PubSub},
      ElitermWeb.Endpoint
    ]

    children =
      if Application.get_env(:eliterm, :start_gui, true) do
        children ++ [
          {Desktop.Window,
           [
             app: :eliterm,
             id: ElitermWindow,
             title: "Eliterm",
             size: {
               Eliterm.Config.get(["gui", "window", "width"], 1000),
               Eliterm.Config.get(["gui", "window", "height"], 700)
             },
             url: "http://localhost:#{port}",
             icon: "icon.png",
             menubar: ElitermWeb.MenuBar
           ]},
          Eliterm.WindowWatcher
        ]
      else
        children
      end

    children = children ++ [
      {Horde.Registry, [name: Eliterm.Registry, keys: :unique, members: :auto]},
      {Horde.DynamicSupervisor, [name: Eliterm.DistributedSupervisor, strategy: :one_for_one, members: :auto]},
      Eliterm.ClusterManager,
      Eliterm.SessionSupervisor,
      Eliterm.DataSync
    ]

    children =
      if Application.get_env(:eliterm, :start_gui, true) do
        children ++ [Eliterm.Clipboard]
      else
        children
      end

    children =
      if Application.get_env(:eliterm, :start_sleep_watcher, true) do
        children ++ [Eliterm.SleepWatcher]
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eliterm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:inet, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
