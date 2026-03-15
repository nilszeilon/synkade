defmodule Synkade.Repo.Migrations.AddPersistentToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :persistent, :boolean, default: false, null: false
      add :endpoint_url, :string
      add :workspace_path, :string
      add :last_session_id, :string
    end
  end
end
