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
      # Start a worker by calling: Girihelix.Worker.start_link(arg)
      # {Girihelix.Worker, arg},
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
