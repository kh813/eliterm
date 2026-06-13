defmodule Eliterm.ContainerWorker do
  use GenServer
  require Logger

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  defp via_tuple(session_id) do
    {:via, Horde.Registry, {Eliterm.Registry, "container_#{session_id}"}}
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    session_id = Keyword.fetch!(opts, :session_id)
    home_dir = Keyword.fetch!(opts, :home_dir)
    
    Logger.info("Starting container for session #{session_id}...")
    case Eliterm.Container.Engine.start_session_container(session_id, home_dir) do
      {:ok, _} -> 
        Logger.info("Container started.")
        {:ok, %{session_id: session_id}}
      {:error, reason} -> 
        Logger.error("Failed to start container: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Stopping container for session #{state.session_id}...")
    Eliterm.Container.Engine.stop_session_container(state.session_id)
  end
end
