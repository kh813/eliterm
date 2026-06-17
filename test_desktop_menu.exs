defmodule TestMenu do
  use Desktop.Menu
  def render(assigns) do
    ~H"""
    <menubar>
      <menu label="Edit">
        <item id="wxID_COPY" onclick="copy" shortcut="Cmd+C">Copy</item>
      </menu>
    </menubar>
    """
  end
end
IO.puts "Compiled successfully"
