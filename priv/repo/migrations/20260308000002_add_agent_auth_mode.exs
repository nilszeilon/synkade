defmodule Synkade.Repo.Migrations.AddAgentAuthMode do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :agent_auth_mode, :string, default: "api_key"
      add :agent_oauth_token, :binary
    end
  end
end
