defmodule Synkade.Repo.Migrations.AddAgentUsageLimits do
  use Ecto.Migration

  def change do
    # Add usage limit fields to agents
    alter table(:agents) do
      add :usage_limit, :integer
      add :usage_limit_period, :string, default: "day"
    end

    # Add agent_id to token_usage for per-agent tracking
    alter table(:token_usage) do
      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
    end

    # Drop old unique index and add new ones that include agent_id
    drop_if_exists unique_index(:token_usage, [:user_id, :date, :model])

    # Index for rows WITH an agent_id
    create unique_index(:token_usage, [:user_id, :date, :model, :agent_id],
             where: "agent_id IS NOT NULL",
             name: :token_usage_user_date_model_agent_index
           )

    # Index for rows WITHOUT an agent_id (legacy / untracked)
    create unique_index(:token_usage, [:user_id, :date, :model],
             where: "agent_id IS NULL",
             name: :token_usage_user_date_model_null_agent_index
           )

    create index(:token_usage, [:agent_id])
  end
end
