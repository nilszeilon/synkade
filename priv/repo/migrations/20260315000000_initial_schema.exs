defmodule Synkade.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  def change do
    # --- settings ---
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :github_pat, :binary
      add :github_webhook_secret, :binary

      add :execution_backend, :string, default: "local"
      add :execution_sprites_token, :binary
      add :execution_sprites_org, :string

      add :theme, :string, default: "ops"

      timestamps(type: :utc_datetime)
    end

    # --- agents ---
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :kind, :string, default: "claude"
      add :auth_mode, :string, default: "api_key"
      add :api_key, :binary
      add :oauth_token, :binary
      add :model, :string
      add :max_turns, :integer
      add :allowed_tools, :text, default: "[]"
      add :system_prompt, :text
      add :api_token_hash, :string
      add :api_token, :binary

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agents, [:name])
    create unique_index(:agents, [:api_token_hash])

    # --- projects ---
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :enabled, :boolean, default: true
      add :tracker_repo, :string
      add :prompt_template, :string
      add :default_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:name])

    # --- issues ---
    create table(:issues, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :parent_id, references(:issues, type: :binary_id, on_delete: :nilify_all)
      add :body, :text
      add :state, :string, default: "backlog"
      add :depth, :integer, default: 0
      add :position, :integer, default: 0
      add :agent_output, :text
      add :github_issue_url, :string
      add :github_pr_url, :string
      add :metadata, :text, default: "{}"
      add :dispatch_message, :string
      add :assigned_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :recurring, :boolean, default: false, null: false
      add :recurrence_interval, :integer, default: 24
      add :recurrence_unit, :string, default: "hours"
      add :auto_merge, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:issues, [:project_id])
    create index(:issues, [:parent_id])
    create index(:issues, [:state])
    create index(:issues, [:project_id, :state])
    create index(:issues, [:state, :recurring], where: "recurring = 1")

    # --- token_usage ---
    create table(:token_usage, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :date, :date, null: false
      add :model, :string, null: false
      add :input_tokens, :integer, default: 0, null: false
      add :output_tokens, :integer, default: 0, null: false

      timestamps()
    end

    create unique_index(:token_usage, [:date, :model])
  end
end
