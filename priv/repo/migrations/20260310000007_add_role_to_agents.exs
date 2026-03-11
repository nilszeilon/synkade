defmodule Synkade.Repo.Migrations.AddRoleToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :role, :string, default: "developer", null: false
    end
  end
end
