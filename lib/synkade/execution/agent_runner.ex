defmodule Synkade.Execution.AgentRunner do
  @moduledoc "Runs an agent session for an issue. Extracted from Orchestrator.Worker."

  require Logger

  alias Synkade.Prompt.Renderer
  alias Synkade.Execution.BackendClient
  alias Synkade.Tracker.Client, as: TrackerClient
  alias Synkade.Workflow.Config
  alias Synkade.Issues.ChildParser

  @doc "Run a worker for an issue. Called from Oban AgentWorker."
  def run(project, issue, attempt) do
    config = project.config
    project_name = project.name

    Logger.info(
      "AgentRunner starting for #{project_name}:#{issue.identifier} (attempt #{inspect(attempt)})"
    )

    with {:ok, env_ref} <- BackendClient.setup_env(config, project_name, issue.identifier),
         :ok <- BackendClient.run_before_hook(config, env_ref),
         {:ok, prompt} <- render_prompt(project, issue, attempt),
         {:ok, session} <- start_agent(config, prompt, env_ref) do
      result = event_loop(project, issue, session, config, 1)
      BackendClient.run_after_hook(config, env_ref)
      result
    else
      {:error, reason} ->
        Logger.error(
          "AgentRunner failed for #{project_name}:#{issue.identifier}: #{inspect(reason)}"
        )

        broadcast_error(issue.id, "Agent failed to start: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp render_prompt(project, issue, attempt) do
    project_map = %{name: project.name, config: project.config, db_id: project.db_id}
    issue_map = Map.from_struct(issue)

    {ancestors, dispatch_message, issue_map} =
      try do
        case Synkade.Issues.get_issue(issue.id) do
          nil ->
            {[], nil, issue_map}

          db_issue ->
            ancestor_maps =
              Synkade.Issues.ancestor_chain(db_issue)
              |> Enum.map(fn a ->
                %{
                  title: Synkade.Issues.Issue.title(a),
                  body: a.body,
                  agent_output: a.agent_output
                }
              end)

            {ancestor_maps, db_issue.dispatch_message, issue_map}
        end
      catch
        _, _ -> {[], nil, issue_map}
      end

    Renderer.render(project_map, issue_map, attempt, ancestors, dispatch_message)
  end

  defp start_agent(config, prompt, env_ref) do
    BackendClient.start_agent(config, prompt, env_ref)
  end

  defp event_loop(project, issue, session, config, turn) do
    turn_timeout = Config.get(config, "agent", "turn_timeout_ms") || 3_600_000

    case BackendClient.await_event(config, session, turn_timeout) do
      {:partial, chunk} ->
        pending = Map.get(session, :pending_line, "")
        session = Map.put(session, :pending_line, pending <> chunk)
        event_loop(project, issue, session, config, turn)

      {:data, data} ->
        pending = Map.get(session, :pending_line, "")
        data = if pending != "", do: pending <> data, else: data
        session = Map.put(session, :pending_line, "")
        {session, events} = process_data(config, data, session)

        # Broadcast events via PubSub directly
        for event <- events do
          Phoenix.PubSub.broadcast(
            Synkade.PubSub,
            "agent_events:#{issue.id}",
            {:agent_event, event}
          )
        end

        # Update heartbeat on DB
        if events != [] do
          last = List.last(events)
          Synkade.Issues.update_issue_heartbeat(issue.id, last.message)
        end

        event_loop(project, issue, session, config, turn)

      {:exit, 0} ->
        Logger.info("Agent exited normally for #{project.name}:#{issue.identifier}")

        case extract_pr_url(session) do
          {:ok, pr_url} ->
            {:ok, {:pr_created, pr_url}, session}

          :none ->
            agent_output = collect_agent_output(session)
            children = ChildParser.parse(agent_output)

            if agent_output != "" or children != [] do
              {:ok, {:completed_with_output, agent_output, children}, session}
            else
              check_and_continue(project, issue, session, config, turn)
            end
        end

      {:exit, code} ->
        Logger.warning("Agent exited with code #{code} for #{project.name}:#{issue.identifier}")

        broadcast_error(issue.id, "Agent exited with code #{code}")
        {:error, {:agent_exit, code}, session}

      :timeout ->
        Logger.warning("Agent turn timed out for #{project.name}:#{issue.identifier}")
        BackendClient.stop_agent(config, session)

        broadcast_error(issue.id, "Agent timed out")
        {:error, :turn_timeout, session}
    end
  end

  defp check_and_continue(project, issue, session, config, turn) do
    case TrackerClient.fetch_issue_states_by_ids(project.config, project.name, [issue.id]) do
      {:ok, states} ->
        current_state = Map.get(states, issue.id)
        active = Config.active_states(project.config) |> Enum.map(&normalize_state/1)

        if current_state && normalize_state(current_state) in active do
          continuation_prompt =
            "Continue working on this issue. Check the current state and proceed."

          session_id = session.session_id

          case BackendClient.continue_agent(config, session_id, continuation_prompt, session.env_ref) do
            {:ok, new_session} ->
              event_loop(project, issue, new_session, config, turn + 1)

            {:error, reason} ->
              {:error, reason, session}
          end
        else
          {:ok, :issue_no_longer_active, session}
        end

      {:error, _} ->
        {:ok, :state_check_failed, session}
    end
  end

  defp process_data(config, data, session) do
    lines = String.split(data, "\n", trim: true)

    Enum.reduce(lines, {session, []}, fn line, {sess, events} ->
      case BackendClient.parse_event(config, line) do
        {:ok, event} ->
          sess = if event.session_id, do: %{sess | session_id: event.session_id}, else: sess
          sess = %{sess | events: sess.events ++ [event]}
          {sess, events ++ [event]}

        :skip ->
          trimmed = String.trim(line)

          if trimmed != "" do
            stderr_event = %Synkade.Agent.Event{
              type: "stderr",
              message: trimmed,
              timestamp: DateTime.utc_now()
            }

            {sess, events ++ [stderr_event]}
          else
            {sess, events}
          end
      end
    end)
  end

  @doc "Extract a GitHub PR URL from session events."
  def extract_pr_url(session) do
    pr_regex = ~r{https://github\.com/[^/]+/[^/]+/pull/\d+}

    session.events
    |> Enum.reverse()
    |> Enum.find_value(fn event ->
      if event.message do
        case Regex.run(pr_regex, event.message) do
          [url | _] -> url
          _ -> nil
        end
      end
    end)
    |> case do
      nil -> :none
      url -> {:ok, url}
    end
  end

  defp collect_agent_output(session) do
    session.events
    |> Enum.filter(& &1.message)
    |> Enum.map(& &1.message)
    |> Enum.join("\n")
  end

  defp normalize_state(state), do: state |> String.trim() |> String.downcase()

  defp broadcast_error(issue_id, message) do
    event = %Synkade.Agent.Event{
      type: "error",
      message: message,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      "agent_events:#{issue_id}",
      {:agent_event, event}
    )
  end
end
