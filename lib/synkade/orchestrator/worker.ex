defmodule Synkade.Orchestrator.Worker do
  @moduledoc false

  require Logger

  alias Synkade.Prompt.Renderer
  alias Synkade.Execution.BackendClient
  alias Synkade.Tracker.Client, as: TrackerClient
  alias Synkade.Workflow.Config
  alias Synkade.Issues.ChildParser

  @doc "Run a worker for an issue. Called within a Task."
  def run(orchestrator, project, issue, attempt) do
    config = project.config
    project_name = project.name
    prompt_template = project.prompt_template
    max_turns = Config.max_turns(config)

    Logger.info("Worker starting for #{project_name}:#{issue.identifier} (attempt #{inspect(attempt)})")

    with {:ok, env_ref} <- BackendClient.setup_env(config, project_name, issue.identifier),
         :ok <- report_env(orchestrator, project_name, issue.id, env_ref),
         :ok <- BackendClient.run_before_hook(config, env_ref),
         {:ok, prompt} <- render_prompt(prompt_template, project, issue, attempt),
         {:ok, session} <- start_or_continue(config, attempt, prompt, env_ref, nil) do
      result = event_loop(orchestrator, project, issue, session, config, max_turns, 1)

      BackendClient.run_after_hook(config, env_ref)
      result
    else
      {:error, reason} ->
        Logger.error("Worker failed for #{project_name}:#{issue.identifier}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp report_env(orchestrator, project_name, issue_id, env_ref) do
    GenServer.cast(orchestrator, {:env_ready, project_name, issue_id, env_ref})
    :ok
  end

  defp render_prompt(prompt_template, project, issue, attempt) do
    project_map = %{name: project.name, config: project.config, db_id: project.db_id}
    issue_map = Map.from_struct(issue)

    # Load DB issue for ancestor chain and dispatch_message
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
                  title: a.title,
                  description: a.description,
                  agent_output: a.agent_output
                }
              end)

            {ancestor_maps, db_issue.dispatch_message, issue_map}
        end
      catch
        _, _ -> {[], nil, issue_map}
      end

    role = get_in(project.config, ["agent", "role"]) || "developer"
    Renderer.render(prompt_template, project_map, issue_map, attempt, ancestors, dispatch_message, role)
  end

  defp start_or_continue(config, nil, prompt, env_ref, _session_id) do
    BackendClient.start_agent(config, prompt, env_ref)
  end

  defp start_or_continue(config, _attempt, prompt, env_ref, nil) do
    BackendClient.start_agent(config, prompt, env_ref)
  end

  defp start_or_continue(config, _attempt, prompt, env_ref, session_id) do
    BackendClient.continue_agent(config, session_id, prompt, env_ref)
  end

  defp event_loop(orchestrator, project, issue, session, config, max_turns, turn) do
    turn_timeout = Config.get(config, "agent", "turn_timeout_ms") || 3_600_000

    case BackendClient.await_event(config, session, turn_timeout) do
      {:data, data} ->
        {session, events} = process_data(config, data, session)

        for event <- events do
          GenServer.cast(orchestrator, {:agent_event, project.name, issue.id, event})
        end

        event_loop(orchestrator, project, issue, session, config, max_turns, turn)

      {:exit, 0} ->
        Logger.info("Agent exited normally for #{project.name}:#{issue.identifier}")

        case extract_pr_url(session) do
          {:ok, pr_url} ->
            {:ok, {:pr_created, pr_url}, session}

          :none ->
            # Capture agent output and check for child declarations
            agent_output = collect_agent_output(session)
            children = ChildParser.parse(agent_output)

            if agent_output != "" or children != [] do
              {:ok, {:completed_with_output, agent_output, children}, session}
            else
              if turn < max_turns do
                check_and_continue(orchestrator, project, issue, session, config, max_turns, turn)
              else
                {:ok, :max_turns_reached, session}
              end
            end
        end

      {:exit, code} ->
        Logger.warning("Agent exited with code #{code} for #{project.name}:#{issue.identifier}")
        {:error, {:agent_exit, code}, session}

      :timeout ->
        Logger.warning("Agent turn timed out for #{project.name}:#{issue.identifier}")
        BackendClient.stop_agent(config, session)
        {:error, :turn_timeout, session}
    end
  end

  defp check_and_continue(orchestrator, project, issue, session, config, max_turns, turn) do
    case TrackerClient.fetch_issue_states_by_ids(project.config, project.name, [issue.id]) do
      {:ok, states} ->
        current_state = Map.get(states, issue.id)
        active = Config.active_states(project.config) |> Enum.map(&normalize_state/1)

        if current_state && normalize_state(current_state) in active do
          continuation_prompt = "Continue working on this issue. Check the current state and proceed."
          session_id = session.session_id

          case start_or_continue(config, turn, continuation_prompt, session.env_ref, session_id) do
            {:ok, new_session} ->
              event_loop(orchestrator, project, issue, new_session, config, max_turns, turn + 1)

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
          sess =
            if event.session_id do
              %{sess | session_id: event.session_id}
            else
              sess
            end

          sess = %{sess | events: sess.events ++ [event]}

          {sess, events ++ [event]}

        :skip ->
          {sess, events}
      end
    end)
  end

  @doc "Extract a GitHub PR URL from the session's accumulated events."
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
end
