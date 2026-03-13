defmodule Synkade.Repo.Migrations.AddThemeToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :theme, :string, default: "ops"
    end
  end
end
