defmodule Synkade.Repo.Migrations.AddLabelsToIssues do
  use Ecto.Migration

  def change do
    alter table(:issues) do
      add :labels, {:array, :string}, default: [], null: false
    end
  end
end
