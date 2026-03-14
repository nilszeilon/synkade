defmodule Synkade.Repo.Migrations.AddAutoMergeToIssues do
  use Ecto.Migration

  def change do
    alter table(:issues) do
      add :auto_merge, :boolean, default: false, null: false
    end
  end
end
