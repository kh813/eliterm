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

  def is_fallback?(session_id) do
    case Horde.Registry.lookup(Eliterm.Registry, "container_#{session_id}") do
      [{pid, _}] -> GenServer.call(pid, :is_fallback)
      [] -> true
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    session_id = Keyword.fetch!(opts, :session_id)
    home_dir = Keyword.fetch!(opts, :home_dir)
    
    if is_nil(Eliterm.Container.Engine.executable()) do
      Logger.warning("No container engine found. Falling back to local bash for session #{session_id}.")
      {:ok, %{session_id: session_id, fallback: true}}
    else
      Logger.info("Starting container for session #{session_id}...")
      case Eliterm.Container.Engine.start_session_container(session_id, home_dir) do
        {:ok, _} -> 
          Logger.info("Container started.")
          {:ok, %{session_id: session_id, fallback: false}}
        {:error, reason} -> 
          Logger.error("Failed to start container: #{inspect(reason)}. Falling back to local bash.")
          {:ok, %{session_id: session_id, fallback: true}}
      end
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.fallback do
      Logger.info("Container was in fallback mode, no need to stop.")
    else
      Logger.info("Stopping container for session #{state.session_id}...")
      Eliterm.Container.Engine.stop_session_container(state.session_id)
    end
  end

  @impl true
  def handle_call(:is_fallback, _from, state) do
    {:reply, state.fallback, state}
  end
end
