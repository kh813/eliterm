defmodule Eliterm.ShellSession do
  @moduledoc """
  1セッション分の PTY (bash) と CronManager を束ねるスーパーバイザー。
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  def via_tuple(session_id) do
    {:via, Horde.Registry, {Eliterm.Registry, "session_#{session_id}"}}
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    Logger.info("Starting ShellSession for #{session_id}")

    home_dir = Keyword.get_lazy(opts, :home_dir, fn ->
      Path.join([Eliterm.base_dir(), "sessions", session_id, "home"])
    end)

    children = [
      {Eliterm.ContainerWorker, [session_id: session_id, home_dir: home_dir]},
      Supervisor.child_spec({Eliterm.PTY, [session_id: session_id, home_dir: home_dir]}, restart: :transient),
      {Eliterm.CronManager, [session_id: session_id, home_dir: home_dir]}
    ]

    # ContainerWorker is first, and if it crashes, restart everything.
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
