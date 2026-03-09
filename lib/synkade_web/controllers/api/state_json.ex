defmodule SynkadeWeb.Api.StateJSON do
  @moduledoc false

  def state(state) do
    %{
      running: format_running(state.running),
      retry_queue: format_retries(state.retry_attempts),
      claimed: state.claimed,
      agent_totals: state.agent_totals,
      agent_totals_by_project: state.agent_totals_by_project,
      poll_interval_ms: state.poll_interval_ms,
      max_concurrent_agents: state.max_concurrent_agents,
      config_error: state.config_error
    }
  end

  def projects(state) do
    %{
      projects:
        state.projects
        |> Map.values()
        |> Enum.map(&format_project_summary/1)
    }
  end

  def project(project, state) do
    running_for_project =
      state.running
      |> Enum.filter(fn {_k, v} -> v.project_name == project.name end)
      |> Map.new()

    retries_for_project =
      state.retry_attempts
      |> Enum.filter(fn {_k, v} -> v.project_name == project.name end)
      |> Map.new()

    %{
      name: project.name,
      enabled: project.enabled,
      max_concurrent_agents: project.max_concurrent_agents,
      running: format_running(running_for_project),
      retry_queue: format_retries(retries_for_project),
      totals: Map.get(state.agent_totals_by_project, project.name, %{
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0,
        runtime_seconds: 0.0
      })
    }
  end

  defp format_running(running) do
    Map.new(running, fn {key, entry} ->
      {key, %{
        project_name: entry.project_name,
        issue_id: entry.issue_id,
        identifier: entry.identifier,
        issue_state: entry.issue_state,
        session_id: entry.session_id,
        turn_count: entry.turn_count,
        agent_total_tokens: entry.agent_total_tokens,
        last_agent_event: entry.last_agent_event,
        last_agent_message: entry.last_agent_message
      }}
    end)
  end

  defp format_retries(retries) do
    Map.new(retries, fn {key, entry} ->
      {key, %{
        project_name: entry.project_name,
        issue_id: entry.issue_id,
        identifier: entry.identifier,
        attempt: entry.attempt,
        error: entry.error
      }}
    end)
  end

  defp format_project_summary(project) do
    %{
      name: project.name,
      enabled: project.enabled,
      max_concurrent_agents: project.max_concurrent_agents
    }
  end
end
