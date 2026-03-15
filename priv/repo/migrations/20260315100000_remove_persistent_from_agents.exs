defmodule Synkade.Repo.Migrations.RemovePersistentFromAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      remove :persistent, :boolean, default: false, null: false
      remove :endpoint_url, :string
      remove :workspace_path, :string
      remove :last_session_id, :string
    end
  end
end
