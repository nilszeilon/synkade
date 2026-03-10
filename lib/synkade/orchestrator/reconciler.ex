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
end
