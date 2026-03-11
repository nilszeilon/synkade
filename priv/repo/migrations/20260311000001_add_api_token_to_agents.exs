defmodule Synkade.Repo.Migrations.AddApiTokenToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :api_token_hash, :string
      add :api_token, :binary
    end

    create index(:agents, [:api_token_hash], unique: true)
  end
end
