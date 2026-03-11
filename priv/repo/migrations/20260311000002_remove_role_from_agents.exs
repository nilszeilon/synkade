defmodule Synkade.Repo.Migrations.RemoveRoleFromAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      remove :role, :string, default: "developer"
    end
  end
end
