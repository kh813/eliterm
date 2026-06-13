defmodule Eliterm do
  @moduledoc """
  eliterm コアモジュール。セッション操作のエントリポイントを提供。
  """

  def start_session(session_id, opts \\ []) do
    Horde.DynamicSupervisor.start_child(
      Eliterm.DistributedSupervisor,
      {Eliterm.ShellSession, Keyword.put(opts, :session_id, session_id)}
    )
  end

  def stop_session(session_id) do
    case Horde.Registry.lookup(Eliterm.Registry, "session_#{session_id}") do
      [{pid, _}] ->
        Horde.DynamicSupervisor.terminate_child(Eliterm.DistributedSupervisor, pid)
      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Hello world.

  ## Examples

      iex> Eliterm.hello()
      :world

  """
  def hello do
    :world
  end
end
