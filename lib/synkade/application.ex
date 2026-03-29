defmodule Synkade.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    migrate()
    Synkade.ObanTelemetry.attach()

    children = [
      SynkadeWeb.Telemetry,
      Synkade.Vault,
      Synkade.Repo,
      {Phoenix.PubSub, name: Synkade.PubSub},
      Synkade.Agent.ModelCache,
      {Oban, Application.fetch_env!(:synkade, Oban)},
      # Start to serve requests, typically the last entry
      SynkadeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Synkade.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Run migrations automatically on boot in prod releases.
  defp migrate do
    if Application.get_env(:synkade, :auto_migrate, false) do
      Synkade.Release.migrate()
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SynkadeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
