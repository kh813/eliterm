exclude = if System.get_env("CI") == "true", do: [skip_on_ci: true], else: []

# Start Erlang distribution with localhost to ensure node name resolution works in CI/headless
unless Node.alive?() do
  System.cmd("epmd", ["-daemon"])
  Node.start(:"eliterm_test@localhost", :shortnames)
end

ExUnit.start(exclude: exclude)
