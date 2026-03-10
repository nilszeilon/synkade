defmodule Synkade.Orchestrator.Dispatch do
  @moduledoc false

  alias Synkade.Orchestrator.State
  alias Synkade.Workflow.Config

  @doc "Filter candidates that are eligible for dispatch."
  @spec filter_candidates([map()], State.t(), map()) :: [map()]
  def filter_candidates(issues, state, _project) do
    issues
    |> Enum.filter(fn issue ->
      has_required_fields?(issue) and
        not running?(issue, state) and
        not claimed?(issue, state) and
        not blocked?(issue)
    end)
  end

  @doc "Sort candidates by priority (asc), created_at (asc), identifier (asc)."
  @spec sort_candidates([map()]) :: [map()]
  def sort_candidates(issues) do
    Enum.sort_by(issues, fn issue ->
      {issue.priority || 999_999, issue.created_at || ~U[9999-12-31 23:59:59Z], issue.identifier}
    end)
  end

  @doc "Calculate available slots."
  @spec available_slots(State.t(), map()) :: non_neg_integer()
  def available_slots(state, project) do
    global_running = map_size(state.running)
    global_max = state.max_concurrent_agents
    global_available = max(0, global_max - global_running)

    project_running =
      state.running
      |> Enum.count(fn {_key, entry} -> entry.project_name == project.name end)

    project_max = project.max_concurrent_agents
    project_available = max(0, project_max - project_running)

    min(global_available, project_available)
  end

  @doc "Calculate available per-state slots."
  @spec available_state_slots(State.t(), map(), String.t()) :: non_neg_integer()
  def available_state_slots(state, project, issue_state) do
    config = project.config
    by_state = Config.get(config, "agent", "max_concurrent_agents_by_state") || %{}
    normalized = normalize_state(issue_state)

    case Map.get(by_state, normalized) do
      nil ->
        # No per-state limit
        999_999

      limit when is_integer(limit) and limit > 0 ->
        running_in_state =
          state.running
          |> Enum.count(fn {_key, entry} ->
            entry.project_name == project.name and
              normalize_state(entry.issue_state) == normalized
          end)

        max(0, limit - running_in_state)

      _ ->
        999_999
    end
  end

  defp has_required_fields?(issue) do
    issue.id != nil and issue.identifier != nil and
      issue.title != nil and issue.state != nil
  end

  defp running?(issue, state) do
    key = State.composite_key(issue.project_name, issue.id)
    Map.has_key?(state.running, key)
  end

  defp claimed?(issue, state) do
    key = State.composite_key(issue.project_name, issue.id)
    MapSet.member?(state.claimed, key)
  end

  defp blocked?(issue) do
    case issue.blocked_by do
      [] -> false
      blockers -> Enum.any?(blockers, &blocker_active?/1)
    end
  end

  defp blocker_active?(%{state: nil}), do: true
  defp blocker_active?(%{state: state}), do: normalize_state(state) != "closed"

  defp normalize_state(state), do: state |> String.trim() |> String.downcase()
end
