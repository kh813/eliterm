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
      Path.join([System.user_home!(), ".eliterm", "sessions", session_id, "home"])
    end)

    children = [
      {Eliterm.PTY, [session_id: session_id, home_dir: home_dir]},
      {Eliterm.CronManager, [session_id: session_id, home_dir: home_dir]}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
