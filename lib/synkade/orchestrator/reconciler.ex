defmodule Synkade.Orchestrator.Reconciler do
  @moduledoc false

  require Logger

  alias Synkade.Orchestrator.State
  alias Synkade.Workflow.Config
  alias Synkade.Tracker.Client, as: TrackerClient
  alias Synkade.Issues

  @doc "Reconcile running sessions: check for stalls and state changes."
  @spec reconcile(State.t()) :: State.t()
  def reconcile(state) do
    state
    |> detect_stalls()
    |> refresh_issue_states()
    |> check_pr_statuses()
    |> cleanup_stale_claimed()
    |> cycle_recurring_issues()
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

  @doc "Refresh issue states from DB for running sessions."
  @spec refresh_issue_states(State.t()) :: State.t()
  def refresh_issue_states(state) do
    Enum.reduce(state.running, state, fn {key, entry}, acc ->
      db_issue_id = Map.get(entry, :db_issue_id)

      if db_issue_id do
        try do
          case Issues.get_issue(db_issue_id) do
            nil ->
              Logger.info("Issue #{key} not found in DB, marking for stop")
              put_in(acc.running[key], Map.put(entry, :should_stop, :missing))

            db_issue ->
              if db_issue.state in ["done", "cancelled"] do
                Logger.info("Issue #{key} is now in terminal state: #{db_issue.state}")
                put_in(acc.running[key], Map.put(entry, :should_stop, :terminal))
              else
                put_in(acc.running[key], Map.put(entry, :issue_state, db_issue.state))
              end
          end
        catch
          _, _ -> acc
        end
      else
        acc
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

              # Transition DB issue to done
              try do
                db_issue_id = Map.get(entry, :db_issue_id) || entry.issue_id
                db_issue = Issues.get_issue(db_issue_id)
                if db_issue, do: Issues.transition_state(db_issue, "done")
              catch
                _, _ -> :ok
              end

              put_in(inner_acc.awaiting_review[key], Map.put(entry, :should_stop, :pr_merged))

            {:ok, %{state: "closed"}} ->
              Logger.info("PR closed for #{key}")

              try do
                db_issue_id = Map.get(entry, :db_issue_id) || entry.issue_id
                db_issue = Issues.get_issue(db_issue_id)
                if db_issue, do: Issues.transition_state(db_issue, "done")
              catch
                _, _ -> :ok
              end

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

  @doc "Clean up claimed issues that are no longer in progress in the DB."
  @spec cleanup_stale_claimed(State.t()) :: State.t()
  def cleanup_stale_claimed(state) do
    stale_keys =
      state.claimed
      |> Enum.filter(fn key ->
        case parse_claimed_key(key) do
          {_project_name, issue_id} ->
            case Issues.get_issue(issue_id) do
              nil -> true
              db_issue -> db_issue.state != "in_progress"
            end

          nil ->
            true
        end
      end)

    if stale_keys != [] do
      Logger.info("Cleaning up stale claimed entries: #{inspect(stale_keys)}")
    end

    state = %{state | claimed: MapSet.difference(state.claimed, MapSet.new(stale_keys))}

    # Clean up stale running entries - if task is no longer alive, remove from running
    stale_running =
      state.running
      |> Enum.filter(fn {_key, entry} ->
        task_pid = Map.get(entry, :task_pid)

        if task_pid do
          not Process.alive?(task_pid)
        else
          # No task_pid means we can't verify, check if we have any events
          entry.agent_total_tokens == 0 and entry.last_agent_event == nil
        end
      end)
      |> Enum.map(fn {key, _entry} -> key end)

    if stale_running != [] do
      Logger.warning("Cleaning up stale running entries: #{inspect(stale_running)}")
    end

    %{state | running: Map.drop(state.running, stale_running)}
  end

  @doc "Cycle recurring issues that are due back to queued."
  @spec cycle_recurring_issues(State.t()) :: State.t()
  def cycle_recurring_issues(state) do
    due = Issues.list_due_recurring_issues()

    Enum.each(due, fn issue ->
      case Issues.cycle_recurring_issue(issue) do
        {:ok, _} ->
          Logger.info("Cycled recurring issue #{issue.id}")

        {:error, reason} ->
          Logger.warning("Failed to cycle recurring issue #{issue.id}: #{inspect(reason)}")
      end
    end)

    state
  end

  defp parse_claimed_key(key) do
    case String.split(key, ":", parts: 2) do
      [project_name, issue_id] -> {project_name, issue_id}
      _ -> nil
    end
  end

  defp get_stall_timeout(state, project_name) do
    case Map.get(state.projects, project_name) do
      nil -> 300_000
      project -> Config.get(project.config, "agent", "stall_timeout_ms") || 300_000
    end
  end
end
