defmodule Eliterm.SessionSnapshot do
  @moduledoc """
  bash セッションの現在の状態をキャプチャし、JSON に保存・復元するモジュール。
  """
  @derive Jason.Encoder
  defstruct [:session_id, :cwd, :env, :shell_vars, :aliases, :history, :captured_at]

  def capture(session_id, home_dir, pty_pid) do
    session_dir = Path.join([home_dir, "..", ".session"]) |> Path.expand()
    File.mkdir_p!(session_dir)

    # Clean old temp files
    Enum.each(["cwd", "env", "vars", "aliases"], fn f ->
      File.rm(Path.join(session_dir, f))
    end)

    # Send SIGUSR1 to bash process to trigger the trap
    state = :sys.get_state(pty_pid)
    os_pid = state.pid
    System.cmd("kill", ["-SIGUSR1", to_string(os_pid)])

    # Wait for the files to be written
    wait_for_files(session_dir, ["cwd", "env", "vars", "aliases"], 20, 50)

    cwd_abs = read_file_or_empty(Path.join(session_dir, "cwd")) |> String.trim()
    cwd_rel =
      if String.starts_with?(cwd_abs, home_dir) do
        String.replace_prefix(cwd_abs, home_dir, "") |> String.trim_leading("/")
      else
        "."
      end

    env_map =
      read_file_or_empty(Path.join(session_dir, "env"))
      |> String.split("\n", trim: true)
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.filter(fn
        [_, _] -> true
        _ -> false
      end)
      |> Map.new(fn [k, v] -> {k, v} end)

    shell_vars = read_file_or_empty(Path.join(session_dir, "vars"))
    aliases = read_file_or_empty(Path.join(session_dir, "aliases"))

    hist_file = Path.join(home_dir, ".bash_history")
    history =
      if File.exists?(hist_file) do
        File.read!(hist_file) |> String.split("\n", trim: true)
      else
        []
      end

    snapshot = %__MODULE__{
      session_id: session_id,
      cwd: cwd_rel,
      env: env_map,
      shell_vars: shell_vars,
      aliases: aliases,
      history: history,
      captured_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    save(snapshot, session_dir)
    snapshot
  end

  def save(%__MODULE__{} = snapshot, session_dir) do
    json = Jason.encode!(snapshot, pretty: true)
    File.write!(Path.join(session_dir, "snapshot.json"), json)
  end

  def load(session_dir) do
    path = Path.join(session_dir, "snapshot.json")
    if File.exists?(path) do
      json = File.read!(path)
      attrs = Jason.decode!(json, keys: :atoms)
      struct(__MODULE__, attrs)
    else
      nil
    end
  end

  defp read_file_or_empty(path) do
    case File.read(path) do
      {:ok, content} -> content
      _ -> ""
    end
  end

  defp wait_for_files(_dir, _files, 0, _sleep), do: :timeout
  defp wait_for_files(dir, files, retries, sleep) do
    all_exist = Enum.all?(files, fn f -> File.exists?(Path.join(dir, f)) end)
    if all_exist do
      :ok
    else
      Process.sleep(sleep)
      wait_for_files(dir, files, retries - 1, sleep)
    end
  end
end
