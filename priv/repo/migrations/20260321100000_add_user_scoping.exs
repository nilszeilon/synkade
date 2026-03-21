defmodule Synkade.Repo.Migrations.AddUserScoping do
  use Ecto.Migration

  def up do
    # Add nullable user_id FK to settings, projects, agents, token_usage
    alter table(:settings) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    alter table(:projects) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    alter table(:agents) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    alter table(:token_usage) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    flush()

    # Backfill all rows to first user
    execute "UPDATE settings SET user_id = (SELECT id FROM users ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    execute "UPDATE projects SET user_id = (SELECT id FROM users ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    execute "UPDATE agents SET user_id = (SELECT id FROM users ORDER BY id LIMIT 1) WHERE user_id IS NULL"
    execute "UPDATE token_usage SET user_id = (SELECT id FROM users ORDER BY id LIMIT 1) WHERE user_id IS NULL"

    flush()

    # Make NOT NULL
    alter table(:settings) do
      modify :user_id, :bigint, null: false
    end

    alter table(:projects) do
      modify :user_id, :bigint, null: false
    end

    alter table(:agents) do
      modify :user_id, :bigint, null: false
    end

    alter table(:token_usage) do
      modify :user_id, :bigint, null: false
    end

    # Drop old unique indexes
    drop_if_exists unique_index(:agents, [:name])
    drop_if_exists unique_index(:projects, [:name])
    drop_if_exists unique_index(:token_usage, [:date, :model])

    # Create scoped unique indexes
    create unique_index(:settings, [:user_id])
    create unique_index(:agents, [:user_id, :name])
    create unique_index(:projects, [:user_id, :name])
    create unique_index(:token_usage, [:user_id, :date, :model])
  end

  def down do
    drop_if_exists unique_index(:token_usage, [:user_id, :date, :model])
    drop_if_exists unique_index(:projects, [:user_id, :name])
    drop_if_exists unique_index(:agents, [:user_id, :name])
    drop_if_exists unique_index(:settings, [:user_id])

    create unique_index(:token_usage, [:date, :model])
    create unique_index(:projects, [:name])
    create unique_index(:agents, [:name])

    alter table(:token_usage) do
      remove :user_id
    end

    alter table(:agents) do
      remove :user_id
    end

    alter table(:projects) do
      remove :user_id
    end

    alter table(:settings) do
      remove :user_id
    end
  end
end
