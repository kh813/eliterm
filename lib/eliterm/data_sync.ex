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

  @doc """
  指定されたセッションの home/ ディレクトリを初期化する。
  """
  def init_home(session_id) do
    home_dir = Path.join([System.user_home!(), ".eliterm", "sessions", session_id, "home"])
    File.mkdir_p!(home_dir)
    
    scripts_dir = Path.join(home_dir, "scripts")
    File.mkdir_p!(scripts_dir)

    crontab_path = Path.join(home_dir, "crontab")
    unless File.exists?(crontab_path) do
      template = """
      # eliterm crontab template
      # 
      # Example:
      # # name: backup
      # */5 * * * * ~/scripts/backup.sh
      """
      File.write!(crontab_path, template)
    end

    :ok
  end

  @doc """
  指定されたディレクトリのサイズと内訳（サブディレクトリごとのサイズ）を計算して返す。
  """
  def calc_size(dir) do
    case System.cmd("du", ["-sh", dir]) do
      {output, 0} -> 
        total_size = output |> String.split("\t") |> List.first()
        
        children = File.ls!(dir)
        breakdown = 
          Enum.map(children, fn child ->
            child_path = Path.join(dir, child)
            case System.cmd("du", ["-sh", child_path]) do
              {child_out, 0} -> 
                sz = child_out |> String.split("\t") |> List.first()
                %{size: sz, path: child}
              _ -> %{size: "error", path: child}
            end
          end)

        {:ok, %{total: total_size, breakdown: breakdown}}
      _ ->
        {:error, :du_failed}
    end
  end

  @doc """
  ディレクトリの書き込み権限を変更する。
  """
  def set_readonly(dir, readonly?) do
    mode = if readonly?, do: "a-w", else: "u+w"
    case System.cmd("chmod", ["-R", mode, dir]) do
      {_, 0} -> :ok
      {err, _} -> {:error, err}
    end
  end

  @doc """
  rsync を使用してディレクトリを別ノードへコピーする。
  プログレスバーは rsync の --info=progress2 で出力し、IO.streamに流す。
  """
  def rsync_copy(src_dir, target_node, dest_dir) do
    args = ["-avz", "--info=progress2", "--delete", src_dir <> "/", "#{target_node}:#{dest_dir}/"]
    
    # 標準出力にそのまま流すことでプログレスバーを表示する
    case System.cmd("rsync", args, into: IO.stream(:stdio, :line), stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, _} -> {:error, :rsync_failed}
    end
  end

  @doc """
  ディレクトリ全体の SHA256 チェックサムを計算し、整合性を検証する。
  """
  def verify_checksum(dir) do
    cmd = "tar -cf - -C #{Path.dirname(dir)} #{Path.basename(dir)} | (sha256sum || shasum -a 256) 2>/dev/null"
    case System.cmd("bash", ["-c", cmd]) do
      {output, 0} -> 
        hash = output |> String.split(" ") |> List.first()
        {:ok, hash}
      _ ->
        {:error, :checksum_failed}
    end
  end
end
