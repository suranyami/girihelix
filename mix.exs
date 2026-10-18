defmodule Girihelix.MixProject do
  use Mix.Project

  def project do
    [
      app: :girihelix,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      usage_rules: usage_rules(),
      # Dialyzer. girihelix is a single app, so the default PLT location under
      # _build/ is fine and is already gitignored; dialyxir keys it by OTP/Elixir
      # version, so no manual cache invalidation is needed. Deliberately NOT in
      # any gate yet — it is slow, and it is not yet clean. Run it with
      # `mix dialyzer`.
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit]
      ],
      test_coverage: [tool: ExCoveralls],
      # `mix test.watch` runs the suite and credo on every save. `--stale` keeps
      # it to the tests affected by what changed.
      mix_test_watch: [
        tasks: [
          "test --stale",
          "credo -a --strict"
        ]
      ],
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Girihelix.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [
        test: :test,
        precommit: :test,
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  # What `mix usage_rules.sync` writes into AGENTS.md. Only the short general
  # block is inlined; the framework rule sets are LINKED, because inlining them
  # all produced a 2,293-line / 90 KB file — 3.5x the size of work/core's
  # hand-written AGENTS.md, and loaded into every agent context. Linking keeps
  # the rules discoverable without that cost. See `mix help usage_rules.sync`.
  #
  # Two traps, both verified the hard way:
  #
  #   * `:phoenix` must stay listed — it carries the Elixir/Ecto/HTML/LiveView
  #     sub-rules `mix phx.new` generated, and syncing without it silently DROPS
  #     them.
  #   * Do NOT also list `:elixir` or `:otp`. They are convenience atoms that
  #     expand to `:usage_rules` sub-rules already pulled in by `:usage_rules`
  #     itself, and listing all three triplicates those blocks.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        :usage_rules,
        {:ash, link: :markdown},
        {:ash_phoenix, link: :markdown},
        {:ash_postgres, link: :markdown},
        {:phoenix, link: :markdown},
        {:sobelow, link: :markdown}
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:tidewave, "~> 0.9", only: [:dev]},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:phoenix, "~> 1.8.14"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui", tag: "v5.5.20", sparse: "packages/bundle", app: false, compile: false, depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},

      # Domain modelling. Ash resources and domains are designed later — the
      # scaffold only needs the framework present and wired.
      {:ash, "~> 3.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},

      # Code quality (dev/test only). Same tool set as work/core, which is the
      # reference standard for this workspace.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.11", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.2", only: [:dev, :test], runtime: false},

      # Dev tooling. `usage_rules` generates the usage-rules block in AGENTS.md
      # from these dependencies, so the agent guidance stays in sync with the
      # versions actually pinned here.
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:usage_rules, "~> 1.2", only: [:dev]}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build", "run priv/repo/seeds.exs"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind girihelix", "esbuild girihelix"],
      "assets.deploy": [
        "tailwind girihelix --minify",
        "esbuild girihelix --minify",
        "phx.digest"
      ],
      # Fast gate — what the `pre-commit` hook runs. Seconds, not minutes, so
      # committing stays cheap: no PLT, no database, no test suite.
      "precommit.fast": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo -a --strict"
      ],
      # Full gate — what the `pre-push` hook runs. Adds dialyzer, sobelow and the
      # suite under coverage. Dialyzer is deliberately here rather than in
      # `precommit.fast`: it builds and consults a PLT, which is too slow to pay
      # on every commit.
      #
      # It earns its place because it checks the half the compiler does not. The
      # compiler checks *call sites*, but against the types it infers from the
      # callee's patterns, guards and body — a `@spec` alone constrains nothing
      # at compile time (measured 2026-10-19). A malformed argument to a function
      # whose head rules it out is a warning, and an error under
      # `--warnings-as-errors`. The compiler does **not** check a body against its
      # own spec, nor enforce `@opaque`. Dialyzer does both, which is what makes
      # types load-bearing rather than decorative. Run it alone with
      # `mix dialyzer`.
      #
      # Measured 2026-10-17 on Elixir 1.20.3 / OTP 29: a cold PLT build is ~57s
      # and a warm analysis ~3s, with zero errors. The PLT lives under `_build/`
      # (gitignored) and is keyed to the Erlang and Elixir versions, so a fresh
      # clone or a version bump pays the 57s once.
      precommit: [
        "precommit.fast",
        "dialyzer",
        "sobelow --skip",
        "coveralls"
      ]
    ]
  end
end
