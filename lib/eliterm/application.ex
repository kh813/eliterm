defmodule Eliterm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = get_free_port()
    
    endpoint_config = Application.get_env(:eliterm, ElitermWeb.Endpoint)
    http_opts = Keyword.get(endpoint_config, :http, []) |> Keyword.put(:port, port)
    Application.put_env(:eliterm, ElitermWeb.Endpoint, Keyword.put(endpoint_config, :http, http_opts))

    topologies = [
      eliterm_cluster: [
        strategy: Cluster.Strategy.Gossip
      ]
    ]

    children = [
      Eliterm.Scheduler,
      {Cluster.Supervisor, [topologies, [name: Eliterm.ClusterSupervisor]]},
      {Phoenix.PubSub, name: Eliterm.PubSub},
      ElitermWeb.Endpoint,
      {Desktop.Window,
       [
         app: :eliterm,
         id: ElitermWindow,
         title: "Eliterm",
         size: {1000, 700},
         url: "http://localhost:#{port}",
         icon: "icon.png",
         menubar: ElitermWeb.MenuBar
       ]},
      {Horde.Registry, [name: Eliterm.Registry, keys: :unique, members: :auto]},
      {Horde.DynamicSupervisor, [name: Eliterm.DistributedSupervisor, strategy: :one_for_one, members: :auto]},
      Eliterm.ClusterManager,
      Eliterm.SessionSupervisor,
      Eliterm.DataSync,
      Eliterm.SleepWatcher
    ]

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
