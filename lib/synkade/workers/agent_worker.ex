defmodule Synkade.Workers.AgentWorker do
  @moduledoc "Oban worker for running agent sessions on issues."
  use Oban.Worker, queue: :agents, max_attempts: 5

  require Logger

  alias Synkade.Issues
  alias Synkade.Settings
  alias Synkade.Settings.ConfigAdapter
  alias Synkade.Execution.AgentRunner

  @impl Oban.Worker
  def timeout(_job), do: :timer.hours(2)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    trunc(10_000 * :math.pow(2, attempt - 1))
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"issue_id" => issue_id, "project_id" => project_id}} = job) do
    case Issues.get_issue(issue_id) do
      nil ->
        Logger.info("AgentWorker: issue #{issue_id} not found, skipping")
        :ok

      %{state: state} when state not in ~w(queued in_progress) ->
        Logger.info("AgentWorker: issue #{issue_id} is #{state}, skipping")
        :ok

      issue ->
        run_agent(issue, project_id, job)
    end
  end

  defp run_agent(issue, project_id, job) do
    with {:ok, setting} <- load_setting(),
         {:ok, db_project} <- load_project(project_id),
         {:ok, agent} <- resolve_agent(issue, db_project) do
      # Check per-project concurrency
      max_concurrent = Map.get(db_project, :max_concurrent, 10) || 10
      running_count = Synkade.Jobs.running_for_project(project_id)

      if running_count >= max_concurrent do
        Logger.info(
          "AgentWorker: project #{db_project.name} at concurrency limit (#{running_count}/#{max_concurrent}), snoozing"
        )

        {:snooze, 30}
      else
        # Skip pull-based agents
        if agent && Synkade.Settings.Agent.pull_kind?(agent.kind) do
          Logger.info("AgentWorker: skipping pull-based agent #{agent.name}")
          :ok
        else
          execute_agent(issue, setting, db_project, agent, job)
        end
      end
    end
  end

  defp execute_agent(issue, setting, db_project, agent, job) do
    # Transition to in_progress if still queued
    issue =
      if issue.state == "queued" do
        case Issues.transition_state(issue, "in_progress") do
          {:ok, updated} -> updated
          _ -> issue
        end
      else
        issue
      end

    config = ConfigAdapter.resolve_project_config(setting, db_project, agent)

    # Inject Synkade API URL
    config =
      try do
        api_url = SynkadeWeb.Endpoint.url() <> "/api/v1/agent"
        put_in(config, ["agent", "synkade_api_url"], api_url)
      catch
        _, _ -> config
      end

    project = %{
      name: db_project.name,
      db_id: db_project.id,
      config: config,
      prompt_template: db_project.prompt_template || (agent && agent.system_prompt)
    }

    tracker_issue = db_issue_to_tracker_issue(issue, db_project.name)
    attempt = job.attempt

    case AgentRunner.run(project, tracker_issue, attempt) do
      {:ok, {:pr_created, pr_url}, _session} ->
        handle_pr_created(issue, pr_url)
        :ok

      {:ok, {:completed_with_output, agent_output, children}, _session} ->
        handle_completed(issue, agent_output, children, agent)
        :ok

      {:ok, _reason, _session} ->
        :ok

      {:error, reason, _session} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_pr_created(issue, pr_url) do
    Issues.update_issue(issue, %{github_pr_url: pr_url})
    issue = Issues.get_issue(issue.id)
    if issue, do: Issues.transition_state(issue, "awaiting_review")
  rescue
    e -> Logger.warning("AgentWorker: failed to handle PR: #{inspect(e)}")
  end

  defp handle_completed(issue, agent_output, children, agent) do
    agent_name = agent && agent.name
    agent_kind = agent && agent.kind
    Issues.append_agent_output(issue, agent_output, agent_name, agent_kind)
    issue = Issues.get_issue(issue.id)
    if issue, do: Issues.transition_state(issue, "awaiting_review")
    if issue && children != [], do: Issues.create_children_from_agent(issue, children)
  rescue
    e -> Logger.warning("AgentWorker: failed to handle completion: #{inspect(e)}")
  end

  defp load_setting do
    case Settings.get_settings() do
      nil -> {:error, "no settings configured"}
      setting -> {:ok, setting}
    end
  end

  defp load_project(project_id) do
    case Settings.get_project!(project_id) do
      nil -> {:error, "project not found"}
      project -> {:ok, project}
    end
  rescue
    Ecto.NoResultsError -> {:error, "project not found"}
  end

  defp resolve_agent(issue, db_project) do
    agents = Settings.list_agents()
    agents_by_id = Map.new(agents, fn a -> {a.id, a} end)

    agent =
      case issue.assigned_agent_id do
        nil ->
          agents_by_id[db_project.default_agent_id] || List.first(agents)

        id ->
          agents_by_id[id] || agents_by_id[db_project.default_agent_id] || List.first(agents)
      end

    {:ok, agent}
  end

  defp db_issue_to_tracker_issue(db_issue, project_name) do
    alias Synkade.Issues.Issue

    %Synkade.Tracker.Issue{
      project_name: project_name,
      id: db_issue.id,
      identifier: "#{project_name}##{db_issue.id |> String.slice(0..7)}",
      title: Issue.title(db_issue),
      description: db_issue.body,
      state: db_issue.state,
      priority: nil,
      labels: [],
      blocked_by: [],
      created_at: db_issue.inserted_at,
      updated_at: db_issue.updated_at
    }
  end
end
