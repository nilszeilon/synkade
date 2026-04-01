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

      %{state: state} when state != "worked_on" ->
        Logger.info("AgentWorker: issue #{issue_id} is #{state}, skipping")
        :ok

      issue ->
        run_agent(issue, project_id, job)
    end
  end

  defp run_agent(issue, project_id, job) do
    with {:ok, db_project} <- load_project(project_id),
         {:ok, setting} <- load_setting(db_project.user_id),
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
        execute_agent(issue, setting, db_project, agent, job)
      end
    end
  end

  defp execute_agent(issue, setting, db_project, agent, job) do
    # Ensure issue is in worked_on state
    issue =
      if issue.state != "worked_on" do
        case Issues.transition_state(issue, "worked_on") do
          {:ok, updated} -> updated
          _ -> issue
        end
      else
        issue
      end

    config = ConfigAdapter.resolve_project_config(setting, db_project, agent)

    # Model resolution order (highest priority first):
    #   1. Per-issue override (issue.metadata["model"]) — set via model picker at dispatch time
    #   2. Project default (project.default_model) — resolved by ConfigAdapter
    #   3. Global default (setting.default_model) — resolved by ConfigAdapter
    #   4. nil — agent CLI uses its own built-in default
    issue_model = get_in(issue.metadata, ["model"])

    config =
      if issue_model do
        put_in(config, ["agent", "model"], issue_model)
      else
        config
      end

    # Add user's skills to config
    skills = Synkade.Skills.list_skills_for_user(db_project.user_id)
    config = Map.put(config, "skills", Synkade.Skills.skills_to_maps(skills))

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
      config: config
    }

    tracker_issue = db_issue_to_tracker_issue(issue, db_project.name)
    attempt = job.attempt

    case AgentRunner.run(project, tracker_issue, attempt, db_project.user_id) do
      {:ok, {:pr_created, pr_url}, _session} ->
        handle_pr_created(issue, pr_url)
        :ok

      {:ok, {:completed_with_output, agent_output}, _session} ->
        handle_completed(issue, agent_output, agent)
        :ok

      {:ok, _reason, _session} ->
        :ok

      {:error, reason, _session} ->
        handle_error(issue, reason, job)
        {:error, reason}

      {:error, reason} ->
        handle_error(issue, reason, job)
        {:error, reason}
    end
  end

  defp handle_pr_created(issue, pr_url) do
    Issues.update_issue(issue, %{github_pr_url: pr_url})
  rescue
    e -> Logger.warning("AgentWorker: failed to handle PR: #{inspect(e)}")
  end

  defp handle_error(issue, reason, job) do
    error_text = format_error(reason)
    Issues.append_error_message(issue, "Agent failed: #{error_text} (attempt #{job.attempt}/#{job.max_attempts})")

    if job.attempt >= job.max_attempts do
      Issues.append_error_message(issue, "All retries exhausted. Returning issue to backlog.")
      Issues.transition_state(issue, "backlog")
    end
  rescue
    e -> Logger.warning("AgentWorker: failed to handle error: #{inspect(e)}")
  end

  defp format_error({:agent_exit, code}), do: "exited with code #{code}"
  defp format_error(:turn_timeout), do: "timed out"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp handle_completed(issue, agent_output, agent) do
    agent_name = agent && agent.name
    agent_kind = agent && agent.kind
    Issues.append_agent_output(issue, agent_output, agent_name, agent_kind)
  rescue
    e -> Logger.warning("AgentWorker: failed to handle completion: #{inspect(e)}")
  end

  defp load_setting(user_id) do
    case Settings.get_settings_for_user(user_id) do
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
    agents = Settings.list_agents_for_user(db_project.user_id)
    settings = Settings.get_settings_for_user(db_project.user_id)

    agent =
      Settings.resolve_agent(agents,
        assigned_agent_id: issue.assigned_agent_id,
        project_agent_id: db_project.default_agent_id,
        user_default_id: settings && settings.default_agent_id
      )

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
