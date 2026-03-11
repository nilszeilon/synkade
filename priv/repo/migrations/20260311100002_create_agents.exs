defmodule Synkade.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :kind, :string, default: "claude"
      add :auth_mode, :string, default: "api_key"
      add :api_key, :binary
      add :oauth_token, :binary
      add :model, :string
      add :max_turns, :integer
      add :allowed_tools, {:array, :string}, default: []
      add :system_prompt, :text
      add :api_token_hash, :string
      add :api_token, :binary

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agents, [:name])
    create unique_index(:agents, [:api_token_hash])
  end
end
