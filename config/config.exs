import Config

config :eliterm, Eliterm.Scheduler,
  jobs: []

config :eliterm, ElitermWeb.Endpoint,
  http: [port: 4000],
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  server: true,
  secret_key_base: "uR6Q8JbF4Y/5X6x/w9P5aH0lS3kH2gQ5X6x/w9P5aH0lS3kH2gABCDEF0123456789ABCDEF0123456789",
  pubsub_server: Eliterm.PubSub,
  live_view: [signing_salt: "v8LQK7U5"],
  debug_errors: true

config :phoenix, :json_library, Jason

if Mix.env() == :test do
  config :eliterm, ElitermWeb.Endpoint,
    server: false
end
