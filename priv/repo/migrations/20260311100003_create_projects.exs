defmodule Synkade.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :enabled, :boolean, default: true
      add :tracker_repo, :string
      add :prompt_template, :string
      add :default_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:name])
  end
end
