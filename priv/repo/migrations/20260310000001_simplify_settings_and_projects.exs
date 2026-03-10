defmodule Synkade.Repo.Migrations.SimplifySettingsAndProjects do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      remove :github_auth_mode, :string, default: "pat"
      remove :github_app_id, :string
      remove :github_private_key, :binary
    end

    alter table(:projects) do
      remove :tracker_kind, :string
      remove :tracker_endpoint, :string
      remove :tracker_api_key, :binary
      remove :tracker_labels, {:array, :string}
      remove :tracker_app_id, :string
      remove :tracker_private_key, :binary
      remove :tracker_webhook_secret, :binary
      remove :tracker_installation_id, :string
      remove :agent_kind, :string
      remove :agent_auth_mode, :string
      remove :agent_api_key, :binary
      remove :agent_oauth_token, :binary
      remove :agent_model, :string
      remove :agent_max_turns, :integer
      remove :agent_allowed_tools, {:array, :string}
      remove :agent_max_concurrent, :integer
      remove :execution_backend, :string
      remove :execution_sprites_token, :binary
      remove :execution_sprites_org, :string
    end
  end
end
