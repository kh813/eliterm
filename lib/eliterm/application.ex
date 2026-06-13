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
      {Horde.Registry, [name: Eliterm.Registry, keys: :unique, members: :auto]},
      {Horde.DynamicSupervisor, [name: Eliterm.DistributedSupervisor, strategy: :one_for_one, members: :auto]},
      Eliterm.ClusterManager,
      Eliterm.SessionSupervisor,
      Eliterm.DataSync
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eliterm.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
