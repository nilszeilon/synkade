defmodule Synkade.Jobs do
  @moduledoc "Context module for querying Oban job state. Replaces Orchestrator.get_state()."

  import Ecto.Query
  alias Synkade.Repo

  @doc "Returns state compatible with old Orchestrator.get_state() shape."
  def get_state do
    {config_error, projects} = load_projects()

    %{
      projects: projects,
      running: running_agents_map(),
      retry_attempts: retrying_agents_map(),
      awaiting_review: %{},
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, runtime_seconds: 0.0},
      agent_totals_by_project: %{},
      config_error: config_error,
      reconcile_interval_ms: 60_000,
      max_concurrent_agents: 10
    }
  end

  @doc "List currently executing agent jobs."
  def running_agents do
    from(j in Oban.Job,
      where: j.queue == "agents" and j.state == "executing",
      order_by: [asc: j.inserted_at]
    )
    |> Repo.all()
  end

  @doc "List retrying/scheduled agent jobs with attempt > 1."
  def retrying_agents do
    from(j in Oban.Job,
      where: j.queue == "agents" and j.state in ["retryable", "scheduled"] and j.attempt > 1,
      order_by: [asc: j.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Count jobs by state for the agents queue."
  def job_counts do
    from(j in Oban.Job,
      where: j.queue == "agents",
      group_by: j.state,
      select: {j.state, count(j.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count executing jobs for a specific project."
  def running_for_project(project_id) do
    project_id_str = to_string(project_id)

    from(j in Oban.Job,
      where:
        j.queue == "agents" and j.state == "executing" and
          fragment("?->>'project_id' = ?", j.args, ^project_id_str)
    )
    |> Repo.aggregate(:count)
  end

  @doc "No-op refresh -- Oban handles scheduling. Broadcasts to trigger LiveView re-query."
  def refresh do
    Phoenix.PubSub.broadcast(Synkade.PubSub, "jobs:updates", {:jobs_changed})
  end

  @doc "Load projects configuration from Settings."
  def load_projects do
    settings = try_load(fn -> Synkade.Settings.get_settings() end)
    projects = try_load(fn -> Synkade.Settings.list_enabled_projects() end) || []
    agents = try_load(fn -> Synkade.Settings.list_agents() end) || []

    cond do
      is_nil(settings) ->
        {"No settings configured", %{}}

      projects == [] ->
        {"No projects configured", %{}}

      true ->
        agents_by_id = Map.new(agents, fn a -> {a.id, a} end)
        first_agent = List.first(agents)

        entries =
          Enum.map(projects, fn project ->
            agent = agents_by_id[project.default_agent_id] || first_agent

            config =
              if agent do
                Synkade.Settings.ConfigAdapter.resolve_project_config(settings, project, agent)
              else
                Synkade.Settings.ConfigAdapter.to_config(settings)
              end

            # Inject API URL
            config =
              try do
                api_url = SynkadeWeb.Endpoint.url() <> "/api/v1/agent"
                put_in(config, ["agent", "synkade_api_url"], api_url)
              catch
                _, _ -> config
              end

            %{
              name: project.name,
              db_id: project.id,
              config: config,
              prompt_template: project.prompt_template || (agent && agent.system_prompt),
              max_concurrent_agents: Synkade.Workflow.Config.max_concurrent_agents(config),
              enabled: project.enabled
            }
          end)

        {nil, Map.new(entries, fn p -> {p.name, p} end)}
    end
  end

  # --- Private ---

  defp running_agents_map do
    jobs = running_agents()
    project_cache = load_project_names()

    Map.new(jobs, fn job ->
      issue_id = job.args["issue_id"]
      project_id = job.args["project_id"]
      project_name = Map.get(project_cache, project_id, "unknown")
      key = "#{project_name}:#{issue_id}"

      entry = %{
        project_name: project_name,
        issue_id: issue_id,
        identifier: "#{project_name}##{String.slice(issue_id || "", 0..7)}",
        issue_state: "in_progress",
        session_id: nil,
        last_agent_event: nil,
        last_agent_timestamp: nil,
        last_agent_message: nil,
        agent_input_tokens: 0,
        agent_output_tokens: 0,
        agent_total_tokens: 0,
        turn_count: 0,
        stalled: false,
        agent_name: nil,
        agent_kind: nil,
        model: nil
      }

      {key, entry}
    end)
  end

  defp retrying_agents_map do
    jobs = retrying_agents()
    project_cache = load_project_names()

    Map.new(jobs, fn job ->
      issue_id = job.args["issue_id"]
      project_id = job.args["project_id"]
      project_name = Map.get(project_cache, project_id, "unknown")
      key = "#{project_name}:#{issue_id}"

      entry = %{
        project_name: project_name,
        issue_id: issue_id,
        identifier: "#{project_name}##{String.slice(issue_id || "", 0..7)}",
        attempt: job.attempt,
        error: List.last(job.errors),
        agent_name: nil
      }

      {key, entry}
    end)
  end

  defp load_project_names do
    try do
      Synkade.Settings.list_projects()
      |> Map.new(fn p -> {p.id, p.name} end)
    catch
      _, _ -> %{}
    end
  end

  defp try_load(fun) do
    try do
      fun.()
    catch
      _, _ -> nil
    end
  end
end
