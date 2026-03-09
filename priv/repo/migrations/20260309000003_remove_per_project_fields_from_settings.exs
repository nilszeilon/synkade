defmodule Synkade.Repo.Migrations.RemovePerProjectFieldsFromSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      remove :github_repo, :string
      remove :tracker_labels, {:array, :string}, default: []
      remove :github_installation_id, :string
      remove :github_endpoint, :string
    end
  end
end
