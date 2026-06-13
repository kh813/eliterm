defmodule Eliterm.SessionSnapshot do
  @moduledoc """
  bash セッションの現在の状態をキャプチャし、JSON に保存・復元するモジュール。
  """
  @derive Jason.Encoder
  defstruct [:session_id, :cwd, :env, :shell_vars, :aliases, :history, :captured_at]

  def capture(session_id, home_dir, pty_pid) do
    session_dir = Path.join([home_dir, "..", ".session"]) |> Path.expand()
    File.mkdir_p!(session_dir)

    snapshot_tmp_host = Path.join(home_dir, ".snapshot_tmp")
    File.mkdir_p!(snapshot_tmp_host)
    
    # We write via PTY. Note: this assumes bash is at a prompt.
    ExPTY.write(pty_pid, "\ndeclare -p > ~/.snapshot_tmp/vars.txt\n")
    ExPTY.write(pty_pid, "alias > ~/.snapshot_tmp/aliases.txt\n")
    ExPTY.write(pty_pid, "pwd > ~/.snapshot_tmp/cwd.txt\n")
    ExPTY.write(pty_pid, "env > ~/.snapshot_tmp/env.txt\n")

    wait_for_files_list([
      Path.join(snapshot_tmp_host, "vars.txt"),
      Path.join(snapshot_tmp_host, "aliases.txt"),
      Path.join(snapshot_tmp_host, "cwd.txt"),
      Path.join(snapshot_tmp_host, "env.txt")
    ], 20, 100)

    vars = read_file_or_empty(Path.join(snapshot_tmp_host, "vars.txt"))
    aliases = read_file_or_empty(Path.join(snapshot_tmp_host, "aliases.txt"))
    cwd_output = String.trim(read_file_or_empty(Path.join(snapshot_tmp_host, "cwd.txt")))
    env_str = read_file_or_empty(Path.join(snapshot_tmp_host, "env.txt"))

    rel_cwd = String.replace_prefix(cwd_output, "/home/user", "") |> String.trim_leading("/")

    env_map = parse_env(env_str)

    history = load_history(home_dir)

    File.rm_rf!(snapshot_tmp_host)

    snapshot = %__MODULE__{
      session_id: session_id,
      cwd: rel_cwd,
      env: env_map,
      shell_vars: vars,
      aliases: aliases,
      history: history,
      captured_at: DateTime.utc_now()
    }

    snapshot_path = Path.join(session_dir, "snapshot.json")
    File.write!(snapshot_path, Jason.encode!(Map.from_struct(snapshot)))
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

  defp wait_for_files_list(_files, 0, _sleep), do: :timeout
  defp wait_for_files_list(files, retries, sleep) do
    all_exist = Enum.all?(files, fn f -> File.exists?(f) end)
    if all_exist do
      :ok
    else
      Process.sleep(sleep)
      wait_for_files_list(files, retries - 1, sleep)
    end
  end

  defp parse_env(env_str) do
    env_str
    |> String.split("\n", trim: true)
    |> Enum.map(&String.split(&1, "=", parts: 2))
    |> Enum.filter(fn
      [_, _] -> true
      _ -> false
    end)
    |> Map.new(fn [k, v] -> {k, v} end)
  end

  defp load_history(home_dir) do
    hist_file = Path.join(home_dir, ".bash_history")
    if File.exists?(hist_file) do
      File.read!(hist_file) |> String.split("\n", trim: true)
    else
      []
    end
  end
end
