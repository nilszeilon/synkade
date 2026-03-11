defmodule Synkade.Repo.Migrations.CreateIssues do
  use Ecto.Migration

  def change do
    create table(:issues, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :parent_id, references(:issues, type: :binary_id, on_delete: :nilify_all)
      add :title, :string, null: false
      add :description, :text
      add :state, :string, default: "backlog"
      add :priority, :integer, default: 0
      add :depth, :integer, default: 0
      add :position, :integer, default: 0
      add :agent_output, :text
      add :github_issue_url, :string
      add :github_pr_url, :string
      add :metadata, :map, default: %{}
      add :dispatch_message, :string
      add :assigned_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:issues, [:project_id])
    create index(:issues, [:parent_id])
    create index(:issues, [:state])
    create index(:issues, [:project_id, :state])
  end
end
