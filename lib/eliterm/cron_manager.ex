defmodule Eliterm.CronManager do
  @moduledoc """
  home/crontab をパースし、Quantum へジョブを登録・管理する GenServer。
  """
  use GenServer
  require Logger

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  defp via_tuple(session_id) do
    {:via, Horde.Registry, {Eliterm.Registry, "cron_#{session_id}"}}
  end

  # --- API ---

  def list_jobs(session_id) do
    Eliterm.Scheduler.jobs()
    |> Enum.filter(fn {name, _job} -> 
         String.starts_with?(to_string(name), "#{session_id}:") 
       end)
    |> Enum.map(fn {name, job} -> 
         %{name: name, schedule: job.schedule, state: job.state} 
       end)
  end

  def run_job(session_id, job_name) do
    # Quantum 3.x does not have a public run_job by name easily.
    # Actually, we can just find the job and run its task.
    job_id = String.to_atom("#{session_id}:#{job_name}")
    case Enum.find(Eliterm.Scheduler.jobs(), fn {name, _job} -> name == job_id end) do
      {^job_id, job} -> 
        spawn(job.task)
        :ok
      nil -> {:error, :not_found}
    end
  end

  def disable_job(session_id, job_name) do
    job_id = String.to_atom("#{session_id}:#{job_name}")
    Eliterm.Scheduler.deactivate_job(job_id)
  end

  def enable_job(session_id, job_name) do
    job_id = String.to_atom("#{session_id}:#{job_name}")
    Eliterm.Scheduler.activate_job(job_id)
  end

  def job_log(session_id, job_name, lines \\ 100) do
    home_dir = Path.join([System.user_home!(), ".eliterm", "sessions", session_id, "home"])
    sync_log = Path.join([home_dir, "..", ".session", "sync.log"]) |> Path.expand()
    
    if File.exists?(sync_log) do
      case System.cmd("grep", ["\\[#{job_name}\\]", sync_log]) do
        {output, 0} -> 
          tail_out = output |> String.split("\n", trim: true) |> Enum.take(-lines) |> Enum.join("\n")
          {:ok, tail_out}
        _ -> {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    home_dir = Keyword.fetch!(opts, :home_dir)
    
    state = %{
      session_id: session_id,
      home_dir: home_dir,
      jobs: []
    }

    send(self(), :load_crontab)

    {:ok, state}
  end

  @impl true
  def handle_info(:load_crontab, state) do
    crontab_path = Path.join(state.home_dir, "crontab")
    if File.exists?(crontab_path) do
      content = File.read!(crontab_path)
      jobs = parse_crontab(content, state.home_dir)
      
      Enum.each(jobs, fn {name, schedule, command} ->
        job_id = String.to_atom("#{state.session_id}:#{name}")
        
        task = fn ->
          execute_job(state.session_id, name, command, state.home_dir)
        end

        if schedule == "@reboot" do
          spawn(task)
        else
          job =
            Eliterm.Scheduler.new_job()
            |> Quantum.Job.set_name(job_id)
            |> Quantum.Job.set_schedule(Crontab.CronExpression.Parser.parse!(schedule))
            |> Quantum.Job.set_task(task)

          Eliterm.Scheduler.add_job(job)
        end
      end)
      
      {:noreply, %{state | jobs: jobs}}
    else
      {:noreply, state}
    end
  end

  defp parse_crontab(content, home_dir) do
    lines = String.split(content, "\n")
    
    {jobs, _, _} = Enum.reduce(lines, {[], nil, 1}, fn line, {acc_jobs, pending_name, counter} ->
      line = String.trim(line)
      cond do
        line == "" -> 
          {acc_jobs, pending_name, counter}
        String.starts_with?(line, "#") ->
          if String.match?(line, ~r/^#\s*name:/) do
            name = String.replace(line, ~r/^#\s*name:\s*/, "") |> String.trim()
            {acc_jobs, name, counter}
          else
            {acc_jobs, pending_name, counter}
          end
        true ->
          {schedule, command} = parse_crontab_line(line)
          name = pending_name || "job_#{counter}"
          
          # Replace ~ with home_dir
          command = String.replace(command, "~", home_dir)

          acc_jobs = [{name, schedule, command} | acc_jobs]
          {acc_jobs, nil, counter + 1}
      end
    end)
    
    Enum.reverse(jobs)
  end

  defp parse_crontab_line(line) do
    if String.starts_with?(line, "@reboot") do
      command = String.replace_prefix(line, "@reboot", "") |> String.trim()
      {"@reboot", command}
    else
      # split max 6 parts: 5 for schedule, 1 for command
      parts = String.split(line, ~r/\s+/, parts: 6)
      if length(parts) == 6 do
        [m, h, dom, mon, dow, cmd] = parts
        {"#{m} #{h} #{dom} #{mon} #{dow}", String.trim(cmd)}
      else
        {"* * * * *", line}
      end
    end
  end

  def execute_job(session_id, job_name, command, home_dir) do
    sync_log = Path.join([home_dir, "..", ".session", "sync.log"]) |> Path.expand()
    File.mkdir_p!(Path.dirname(sync_log))
    
    log_msg = "[#{DateTime.utc_now()}] [#{job_name}] START: #{command}\n"
    File.write!(sync_log, log_msg, [:append])

    args = [
      "exec", 
      "-w", "/home/user",
      "-e", "HOME=/home/user",
      "eliterm-#{session_id}", 
      "bash", "--posix", "-c", command
    ]

    bin = Eliterm.Container.Engine.executable() || "docker"

    {output, exit_code} = System.cmd(bin, args, stderr_to_stdout: true)

    log_msg_end = "[#{DateTime.utc_now()}] [#{job_name}] END: exit_code=#{exit_code}\nOutput:\n#{output}\n"
    File.write!(sync_log, log_msg_end, [:append])
  end
end
