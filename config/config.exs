import Config

config :eliterm, Eliterm.Scheduler,
  jobs: []

config :eliterm, ElitermWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 0],
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  server: true,
  secret_key_base: "uR6Q8JbF4Y/5X6x/w9P5aH0lS3kH2gQ5X6x/w9P5aH0lS3kH2g",
  pubsub_server: Eliterm.PubSub,
  live_view: [signing_salt: "v8LQK7U5"]

config :phoenix, :json_library, Jason
