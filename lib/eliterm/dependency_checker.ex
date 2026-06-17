defmodule Eliterm.DependencyChecker do
  require Logger

  @doc """
  Checks if Docker or Podman is installed and available in the system PATH.
  If neither is available, it shows a native dialog on GUI mode and halts the application.
  """
  def check_and_halt_if_missing! do
    unless has_container_engine?() do
      show_error_and_halt()
    end
  end

  @doc false
  def has_container_engine? do
    (System.find_executable("docker") != nil) or (System.find_executable("podman") != nil)
  end

  defp show_error_and_halt do
    msg = ~c"Docker or Podman is required to run Eliterm.\nPlease install a container engine and restart the application."
    caption = ~c"Dependency Missing"
    
    # Check if we are running in a GUI context
    if Code.ensure_loaded?(:wx) and match?({:win32, :nt}, :os.type()) or match?({:unix, :darwin}, :os.type()) do
      try do
        :wx.new()
        # 260 = :wxICON_ERROR (256) ||| :wxOK (4)
        dialog = :wxMessageDialog.new(:wx.null(), msg, [{:caption, caption}, {:style, 260}])
        :wxMessageDialog.showModal(dialog)
        :wxMessageDialog.destroy(dialog)
        :wx.destroy()
      rescue
        e -> 
          Logger.error("Failed to show GUI dialog: #{inspect(e)}")
          IO.puts(msg)
      end
    else
      IO.puts(msg)
    end
    
    System.halt(1)
  end
end
