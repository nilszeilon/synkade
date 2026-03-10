defmodule Synkade.Repo.Migrations.RemoveKindAndLabelsFromIssues do
  use Ecto.Migration

  def change do
    alter table(:issues) do
      remove :kind, :string, default: "task", null: false
      remove :labels, {:array, :string}, default: [], null: false
    end
  end
end
