defmodule TestTaskbar do
  def run do
    options = [
         app: :eliterm,
         id: ElitermWindow,
         title: "Eliterm",
         size: {1000, 700},
         url: "http://localhost:1234",
         icon: "icon.png",
         menubar: ElitermWeb.MenuBar
    ]
    icon_menu = options[:icon_menu]
    IO.puts("icon_menu: #{inspect(icon_menu)}")
  end
end
TestTaskbar.run()
