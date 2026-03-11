defmodule Synkade.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # GitHub integration
      add :github_pat, :binary
      add :github_webhook_secret, :binary

      # Execution
      add :execution_backend, :string, default: "local"
      add :execution_sprites_token, :binary
      add :execution_sprites_org, :string

      timestamps(type: :utc_datetime)
    end
  end
end
