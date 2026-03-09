defmodule Synkade.Orchestrator.Reconciler do
  @moduledoc false

  require Logger

  alias Synkade.Orchestrator.State
  alias Synkade.Workflow.Config
  alias Synkade.Tracker.Client, as: TrackerClient

  @doc "Reconcile running sessions: check for stalls and state changes."
  @spec reconcile(State.t()) :: State.t()
  def reconcile(state) do
    state
    |> detect_stalls()
    |> refresh_issue_states()
    |> check_pr_statuses()
  end

  @doc "Detect stalled sessions based on last agent event timestamp."
  @spec detect_stalls(State.t()) :: State.t()
  def detect_stalls(state) do
    now = System.monotonic_time(:millisecond)

    stalled_keys =
      state.running
      |> Enum.filter(fn {_key, entry} ->
        stall_timeout = get_stall_timeout(state, entry.project_name)

        stall_timeout > 0 and
          entry.last_agent_timestamp != nil and
          now - entry.last_agent_timestamp > stall_timeout
      end)
      |> Enum.map(fn {key, _} -> key end)

    Enum.reduce(stalled_keys, state, fn key, acc ->
      Logger.warning("Stalled session detected: #{key}")
      entry = acc.running[key]

      # Mark for stop - the orchestrator will handle cleanup
      put_in(acc.running[key], Map.put(entry, :stalled, true))
    end)
  end

  @doc "Refresh issue states from tracker for running sessions."
  @spec refresh_issue_states(State.t()) :: State.t()
  def refresh_issue_states(state) do
    # Group running issues by project
    by_project =
      state.running
      |> Enum.group_by(
        fn {_key, entry} -> entry.project_name end,
        fn {key, entry} -> {key, entry} end
      )

    Enum.reduce(by_project, state, fn {project_name, entries}, acc ->
      project = Map.get(acc.projects, project_name)

      if project do
        ids = Enum.map(entries, fn {_key, entry} -> entry.issue_id end)

        case TrackerClient.fetch_issue_states_by_ids(project.config, project_name, ids) do
          {:ok, current_states} ->
            check_state_changes(acc, project, entries, current_states)

          {:error, reason} ->
            Logger.warning("Reconciler: failed to fetch states for #{project_name}: #{inspect(reason)}")
            acc
        end
      else
        acc
      end
    end)
  end

  defp check_state_changes(state, project, entries, current_states) do
    terminal_states =
      Config.terminal_states(project.config)
      |> MapSet.new(&normalize_state/1)

    active_states =
      Config.active_states(project.config)
      |> MapSet.new(&normalize_state/1)

    Enum.reduce(entries, state, fn {key, entry}, acc ->
      current_state = Map.get(current_states, entry.issue_id)

      cond do
        current_state == nil ->
          # Issue not found, mark for stop
          Logger.info("Issue #{key} not found in tracker, marking for stop")
          put_in(acc.running[key], Map.put(entry, :should_stop, :missing))

        MapSet.member?(terminal_states, normalize_state(current_state)) ->
          Logger.info("Issue #{key} is now in terminal state: #{current_state}")
          put_in(acc.running[key], Map.put(entry, :should_stop, :terminal))

        not MapSet.member?(active_states, normalize_state(current_state)) ->
          Logger.info("Issue #{key} is no longer active: #{current_state}")
          put_in(acc.running[key], Map.put(entry, :should_stop, :inactive))

        true ->
          # Update the current state
          put_in(acc.running[key], Map.put(entry, :issue_state, current_state))
      end
    end)
  end

  @doc "Check PR statuses for awaiting_review entries."
  @spec check_pr_statuses(State.t()) :: State.t()
  def check_pr_statuses(state) do
    by_project =
      state.awaiting_review
      |> Enum.group_by(
        fn {_key, entry} -> entry.project_name end,
        fn {key, entry} -> {key, entry} end
      )

    Enum.reduce(by_project, state, fn {project_name, entries}, acc ->
      project = Map.get(acc.projects, project_name)

      if project do
        Enum.reduce(entries, acc, fn {key, entry}, inner_acc ->
          case TrackerClient.fetch_pr_status(project.config, project_name, entry.pr_number) do
            {:ok, %{merged: true}} ->
              Logger.info("PR merged for #{key}")
              put_in(inner_acc.awaiting_review[key], Map.put(entry, :should_stop, :pr_merged))

            {:ok, %{state: "closed"}} ->
              Logger.info("PR closed for #{key}")
              put_in(inner_acc.awaiting_review[key], Map.put(entry, :should_stop, :pr_closed))

            {:ok, %{state: "open"}} ->
              inner_acc

            {:error, :not_found} ->
              Logger.warning("PR not found for #{key}, marking for cleanup")
              put_in(inner_acc.awaiting_review[key], Map.put(entry, :should_stop, :pr_not_found))

            {:error, reason} ->
              Logger.warning("Failed to check PR status for #{key}: #{inspect(reason)}")
              inner_acc
          end
        end)
      else
        acc
      end
    end)
  end

  defp get_stall_timeout(state, project_name) do
    case Map.get(state.projects, project_name) do
      nil -> 300_000
      project -> Config.get(project.config, "agent", "stall_timeout_ms") || 300_000
    end
  end

  defp normalize_state(state), do: state |> String.trim() |> String.downcase()
end
