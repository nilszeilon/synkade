defmodule Synkade.Repo.Migrations.CreateSkillsTable do
  use Ecto.Migration

  def change do
    create table(:skills, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :content, :text, null: false
      add :built_in, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:skills, [:user_id, :name])
  end
end
