defmodule Eliterm.MixProject do
  use Mix.Project

  def project do
    [
      app: :eliterm,
      version: "0.1.15",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        eliterm: [
          include_erts: true,
          include_executables_for: [:unix, :windows],
          steps: [:assemble]
        ]
      ],
      escript: [
        main_module: Eliterm.CLI,
        path: "bin/eliterm",
        app: nil
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Eliterm.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:horde, "~> 0.9.0"},
      {:libcluster, "~> 3.4"},
      {:quantum, "~> 3.5"},
      {:expty, "~> 0.1"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.7.0"},
      {:phoenix_live_view, "~> 0.19.0"},
      {:phoenix_html, "~> 3.3"},
      {:bandit, "~> 1.0"},
      {:desktop, "~> 1.5"},
      {:toml, "~> 0.7"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
