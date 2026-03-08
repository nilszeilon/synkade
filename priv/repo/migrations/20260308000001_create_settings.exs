defmodule Synkade.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # GitHub integration
      add :github_auth_mode, :string, default: "pat"
      add :github_pat, :binary
      add :github_app_id, :string
      add :github_private_key, :binary
      add :github_webhook_secret, :binary
      add :github_installation_id, :string
      add :github_endpoint, :string
      add :github_repo, :string
      add :tracker_labels, {:array, :string}, default: []

      # Agent config
      add :agent_kind, :string, default: "claude"
      add :agent_api_key, :binary
      add :agent_model, :string
      add :agent_max_turns, :integer
      add :agent_allowed_tools, {:array, :string}, default: []
      add :agent_max_concurrent, :integer

      # Prompt template
      add :prompt_template, :text

      timestamps(type: :utc_datetime)
    end
  end
end
