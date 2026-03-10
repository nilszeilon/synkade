defmodule Synkade.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :kind, :string, null: false, default: "claude"
      add :auth_mode, :string, null: false, default: "api_key"
      add :api_key, :binary
      add :oauth_token, :binary
      add :model, :string
      add :max_turns, :integer
      add :allowed_tools, {:array, :string}, default: []
      add :system_prompt, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agents, [:name])

    alter table(:projects) do
      add :default_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:settings) do
      remove :agent_kind, :string, default: "claude"
      remove :agent_auth_mode, :string, default: "api_key"
      remove :agent_api_key, :binary
      remove :agent_oauth_token, :binary
      remove :agent_model, :string
      remove :agent_max_turns, :integer
      remove :agent_allowed_tools, {:array, :string}, default: []
      remove :agent_max_concurrent, :integer
      remove :prompt_template, :string
    end
  end
end
