defmodule TestHeart do
  def run do
    try do
      System.cmd("heart", ["-v"])
    rescue
      e -> IO.puts("Failed: #{inspect(e)}")
    end
  end
end
TestHeart.run()
