defmodule Synkade.Repo.Migrations.CreateTokenUsage do
  use Ecto.Migration

  def change do
    create table(:token_usage, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_name, :string, null: false
      add :issue_id, :string, null: false
      add :issue_identifier, :string
      add :model, :string
      add :auth_mode, :string, null: false
      add :input_tokens, :bigint, null: false, default: 0
      add :output_tokens, :bigint, null: false, default: 0
      add :runtime_seconds, :float, default: 0.0

      timestamps(type: :utc_datetime)
    end

    create index(:token_usage, [:project_name])
    create index(:token_usage, [:model])
    create index(:token_usage, [:auth_mode])
    create index(:token_usage, [:inserted_at])
  end
end
