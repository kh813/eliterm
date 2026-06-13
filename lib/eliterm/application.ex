defmodule Eliterm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
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
         endpoint: ElitermWeb.Endpoint,
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
end
