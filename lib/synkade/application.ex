defmodule Synkade.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SynkadeWeb.Telemetry,
      Synkade.Vault,
      Synkade.Repo,
      {DNSCluster, query: Application.get_env(:synkade, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Synkade.PubSub},
      {Registry, keys: :unique, name: Synkade.TokenServerRegistry},
      {DynamicSupervisor, name: Synkade.GitHubAppSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: Synkade.TaskSupervisor},
      Synkade.Orchestrator,
      # Start to serve requests, typically the last entry
      SynkadeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Synkade.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SynkadeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
