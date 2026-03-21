defmodule Synkade.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    # --- users ---
    create table(:users) do
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    # --- settings ---
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :github_pat, :binary
      add :github_webhook_secret, :binary
      add :execution_backend, :string, default: "local"
      add :execution_sprites_token, :binary
      add :execution_sprites_org, :string
      add :theme, :string, default: "ops"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:user_id])

    # --- agents ---
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
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

    create unique_index(:agents, [:user_id, :name])
    create unique_index(:agents, [:api_token_hash])

    # --- projects ---
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :enabled, :boolean, default: true
      add :tracker_repo, :string
      add :prompt_template, :string
      add :default_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:user_id, :name])

    # --- issues ---
    create table(:issues, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :parent_id, references(:issues, type: :binary_id, on_delete: :nilify_all)
      add :body, :text
      add :state, :string, default: "backlog"
      add :depth, :integer, default: 0
      add :position, :integer, default: 0
      add :agent_output, :text
      add :github_issue_url, :string
      add :github_pr_url, :string
      add :metadata, :map, default: %{}
      add :dispatch_message, :string
      add :assigned_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :recurring, :boolean, default: false, null: false
      add :recurrence_interval, :integer, default: 24
      add :recurrence_unit, :string, default: "hours"
      add :auto_merge, :boolean, default: false, null: false
      add :last_heartbeat_at, :utc_datetime
      add :last_heartbeat_message, :text
      timestamps(type: :utc_datetime)
    end

    create index(:issues, [:project_id])
    create index(:issues, [:parent_id])
    create index(:issues, [:state])
    create index(:issues, [:project_id, :state])
    create index(:issues, [:state, :recurring], where: "recurring = true")

    # --- token_usage ---
    create table(:token_usage, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :model, :string, null: false
      add :input_tokens, :integer, default: 0, null: false
      add :output_tokens, :integer, default: 0, null: false
      timestamps()
    end

    create unique_index(:token_usage, [:user_id, :date, :model])

    # --- Oban ---
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 1)

    drop table(:issues)
    drop table(:projects)
    drop table(:agents)
    drop table(:settings)
    drop table(:token_usage)
    drop table(:users_tokens)
    drop table(:users)

    execute "DROP EXTENSION IF EXISTS citext"
  end
end
