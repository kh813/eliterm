defmodule Eliterm.ClusterManager do
  @moduledoc """
  ノード参加・離脱・マイグレーションのフローを制御するGenServer。
  """
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Eliterm.ClusterManager...")
    {:ok, %{}}
  end
end
