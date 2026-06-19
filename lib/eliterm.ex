defmodule Eliterm do
  @moduledoc """
  eliterm コアモジュール。セッション操作のエントリポイントを提供。
  """

  def base_dir do
    if env_dir = System.get_env("ELITERM_DATA_DIR") do
      env_dir
    else
      if File.exists?(Path.join(File.cwd!(), "mix.exs")) do
        Path.join(File.cwd!(), ".eliterm")
      else
        xdg = System.get_env("XDG_CONFIG_HOME")
        config_home = if xdg && xdg != "", do: xdg, else: Path.join(System.user_home!(), ".config")
        Path.join(config_home, "eliterm")
      end
    end
  end

  def local_host do
    case :inet.gethostname() do
      {:ok, hostname} ->
        host_str = to_string(hostname)
        short_host = host_str |> String.split(".") |> List.first()
        case :inet.getaddr(to_charlist(short_host), :inet) do
          {:ok, _} -> short_host
          _ -> "localhost"
        end
      _ ->
        "localhost"
    end
  end

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

  def list_sessions do
    Horde.Registry.select(Eliterm.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    |> Enum.filter(fn {name, _pid, _value} ->
      is_binary(name) and String.starts_with?(name, "session_")
    end)
    |> Enum.map(fn {"session_" <> id, pid, _} -> %{id: id, pid: pid} end)
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
