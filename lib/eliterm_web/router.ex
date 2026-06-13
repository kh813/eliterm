defmodule ElitermWeb.Router do
  use ElitermWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ElitermWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ElitermWeb do
    pipe_through :browser

    live "/", TerminalLive
  end
end
