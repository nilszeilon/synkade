defmodule Synkade.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :enabled, :boolean, default: true, null: false

      # Tracker
      add :tracker_kind, :string
      add :tracker_endpoint, :string
      add :tracker_repo, :string
      add :tracker_api_key, :binary
      add :tracker_labels, {:array, :string}
      add :tracker_app_id, :string
      add :tracker_private_key, :binary
      add :tracker_webhook_secret, :binary
      add :tracker_installation_id, :string

      # Agent
      add :agent_kind, :string
      add :agent_auth_mode, :string
      add :agent_api_key, :binary
      add :agent_oauth_token, :binary
      add :agent_model, :string
      add :agent_max_turns, :integer
      add :agent_allowed_tools, {:array, :string}
      add :agent_max_concurrent, :integer

      # Execution
      add :execution_backend, :string
      add :execution_sprites_token, :binary
      add :execution_sprites_org, :string

      # Prompt
      add :prompt_template, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:name])
  end
end
