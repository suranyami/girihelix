defmodule Girihelix.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GirihelixWeb.Telemetry,
      Girihelix.Repo,
      {DNSCluster, query: Application.get_env(:girihelix, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Girihelix.PubSub},
      # The shared construction cache. `:disk?` comes from config rather than
      # `Mix.env/0`, which releases do not have. See
      # `docs/superpowers/specs/2026-10-24-girihelix-construction-cache-design.md`.
      {GirihelixWeb.Workbench.ConstructCache, disk?: Application.get_env(:girihelix, :construct_cache_disk, false)},
      # Start to serve requests, typically the last entry
      GirihelixWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Girihelix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GirihelixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
