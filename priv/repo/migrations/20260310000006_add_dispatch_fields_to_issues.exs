defmodule Synkade.Repo.Migrations.AddDispatchFieldsToIssues do
  use Ecto.Migration

  def change do
    alter table(:issues) do
      add :dispatch_message, :text
      add :assigned_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
