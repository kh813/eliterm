defmodule ElitermApplicationTest do
  use ExUnit.Case

  test "in test environment, GUI, SleepWatcher, and WindowWatcher processes are bypassed" do
    # Verify the configurations are disabled in test environment
    refute Application.get_env(:eliterm, :start_gui)
    refute Application.get_env(:eliterm, :start_sleep_watcher)
    refute Application.get_env(:eliterm, :check_dependencies)

    # Verify that these GUI-related processes are not running
    # (wxWidgets/X11 initialization will crash if started in headless CI environment)
    assert Process.whereis(ElitermWindow) == nil
    assert Process.whereis(Eliterm.WindowWatcher) == nil
    assert Process.whereis(Eliterm.SleepWatcher) == nil
    assert Process.whereis(Eliterm.Clipboard) == nil
  end

  test "core processes are running in test environment" do
    assert Process.whereis(Eliterm.Scheduler) != nil
    assert Process.whereis(Eliterm.ClusterSupervisor) != nil
    assert Process.whereis(Eliterm.PubSub) != nil
    assert Process.whereis(ElitermWeb.Endpoint) != nil
  end
end
