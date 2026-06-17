exclude = if System.get_env("CI") == "true", do: [skip_on_ci: true], else: []
ExUnit.start(exclude: exclude)
