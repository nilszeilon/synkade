defmodule Synkade.Repo.Migrations.AddRecurringToIssues do
  use Ecto.Migration

  def change do
    alter table(:issues) do
      add :recurring, :boolean, default: false, null: false
      add :recurrence_interval, :integer, default: 24
      add :recurrence_unit, :string, default: "hours"
    end

    create index(:issues, [:state, :recurring], where: "recurring = true")
  end
end
