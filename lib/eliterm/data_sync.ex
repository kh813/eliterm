defmodule Eliterm.DataSync do
  @moduledoc """
  home/ ディレクトリのコピー・同期を担当するモジュール。
  """
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Eliterm.DataSync...")
    {:ok, %{}}
  end
end
