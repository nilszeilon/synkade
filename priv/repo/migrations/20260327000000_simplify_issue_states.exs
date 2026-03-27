defmodule Synkade.Repo.Migrations.SimplifyIssueStates do
  use Ecto.Migration

  def up do
    # Merge old states into simplified 3-state model
    execute "UPDATE issues SET state = 'worked_on' WHERE state IN ('queued', 'in_progress', 'awaiting_review')"
    execute "UPDATE issues SET state = 'done' WHERE state = 'cancelled'"
  end

  def down do
    # Best-effort reverse: worked_on -> backlog, done stays done
    execute "UPDATE issues SET state = 'backlog' WHERE state = 'worked_on'"
  end
end
