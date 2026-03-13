defmodule Synkade.Repo.Migrations.CreateTokenUsage do
  use Ecto.Migration

  def change do
    create table(:token_usage, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :date, :date, null: false
      add :model, :string, null: false
      add :input_tokens, :bigint, default: 0, null: false
      add :output_tokens, :bigint, default: 0, null: false

      timestamps()
    end

    create unique_index(:token_usage, [:date, :model])
  end
end
