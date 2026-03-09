defmodule Synkade.Repo.Migrations.AddExecutionFieldsToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :execution_backend, :string, default: "local"
      add :execution_sprites_token, :binary
      add :execution_sprites_org, :string
    end
  end
end
