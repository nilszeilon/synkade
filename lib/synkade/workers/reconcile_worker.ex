defmodule Synkade.Workers.ReconcileWorker do
  @moduledoc "Oban Cron worker for periodic reconciliation tasks."
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias Synkade.Issues
  alias Synkade.Settings
  alias Synkade.Tracker.Client, as: TrackerClient

  @impl Oban.Worker
  def perform(_job) do
    check_pr_statuses()
    cycle_recurring_issues()
    :ok
  end

  defp check_pr_statuses do
    issues = Issues.list_awaiting_review_issues()

    for issue <- issues, issue.github_pr_url do
      check_single_pr(issue)
    end
  end

  defp check_single_pr(issue) do
    pr_number = extract_pr_number(issue.github_pr_url)

    project =
      try do
        Settings.get_project!(issue.project_id)
      rescue
        _ -> nil
      end

    if pr_number && project do
      setting = Settings.get_settings()
      agent = resolve_agent(issue, project)
      config = Settings.ConfigAdapter.resolve_project_config(setting, project, agent)

      case TrackerClient.fetch_pr_status(config, project.name, pr_number) do
        {:ok, %{merged: true}} ->
          Logger.info("ReconcileWorker: PR merged for issue #{issue.id}")
          Issues.transition_state(issue, "done")

        {:ok, %{state: "closed"}} ->
          Logger.info("ReconcileWorker: PR closed for issue #{issue.id}")
          Issues.transition_state(issue, "done")

        _ ->
          :ok
      end
    end
  rescue
    e -> Logger.warning("ReconcileWorker: PR check failed for issue #{issue.id}: #{inspect(e)}")
  end

  defp cycle_recurring_issues do
    due = Issues.list_due_recurring_issues()

    for issue <- due do
      case Issues.cycle_recurring_issue(issue) do
        {:ok, queued} ->
          Logger.info("ReconcileWorker: cycled recurring issue #{issue.id}")

          %{issue_id: queued.id, project_id: queued.project_id}
          |> Synkade.Workers.AgentWorker.new()
          |> Oban.insert()

        {:error, reason} ->
          Logger.warning("ReconcileWorker: failed to cycle #{issue.id}: #{inspect(reason)}")
      end
    end
  end

  defp extract_pr_number(pr_url) do
    case Regex.run(~r{/pull/(\d+)$}, pr_url) do
      [_, number] -> number
      _ -> nil
    end
  end

  defp resolve_agent(issue, project) do
    agents = Settings.list_agents()
    agents_by_id = Map.new(agents, fn a -> {a.id, a} end)

    case issue.assigned_agent_id do
      nil -> agents_by_id[project.default_agent_id] || List.first(agents)
      id -> agents_by_id[id] || agents_by_id[project.default_agent_id] || List.first(agents)
    end
  end
end
