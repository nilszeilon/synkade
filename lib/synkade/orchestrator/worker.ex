defmodule Synkade.Orchestrator.Worker do
  @moduledoc false

  require Logger

  alias Synkade.Workspace.{Manager, Hooks}
  alias Synkade.Prompt.Renderer
  alias Synkade.Agent.Client, as: AgentClient
  alias Synkade.Agent.ClaudeCode
  alias Synkade.Tracker.Client, as: TrackerClient
  alias Synkade.Workflow.Config

  @doc "Run a worker for an issue. Called within a Task."
  def run(orchestrator, project, issue, attempt) do
    config = project.config
    project_name = project.name
    prompt_template = project.prompt_template
    max_turns = Config.max_turns(config)

    Logger.info("Worker starting for #{project_name}:#{issue.identifier} (attempt #{inspect(attempt)})")

    with {:ok, workspace} <- ensure_workspace(config, project_name, issue),
         :ok <- run_before_hook(config, workspace),
         {:ok, prompt} <- render_prompt(prompt_template, project, issue, attempt),
         {:ok, session} <- start_or_continue(config, attempt, prompt, workspace.path, nil) do
      # Event loop: read port output, send events back to orchestrator
      result = event_loop(orchestrator, project, issue, session, config, max_turns, 1)

      run_after_hook(config, workspace)
      result
    else
      {:error, reason} ->
        Logger.error("Worker failed for #{project_name}:#{issue.identifier}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_workspace(config, project_name, issue) do
    Manager.ensure_workspace(config, project_name, issue.identifier)
  end

  defp run_before_hook(config, workspace) do
    hooks = Config.get_section(config, "hooks")
    timeout = hooks["timeout_ms"] || 60_000

    case Hooks.run_hook(hooks["before_run"], workspace.path, timeout_ms: timeout) do
      :ok -> :ok
      {:error, reason} -> {:error, {:hook_failed, :before_run, reason}}
    end
  end

  defp run_after_hook(config, workspace) do
    hooks = Config.get_section(config, "hooks")
    timeout = hooks["timeout_ms"] || 60_000

    case Hooks.run_hook(hooks["after_run"], workspace.path, timeout_ms: timeout) do
      :ok -> :ok
      {:error, reason} ->
        Logger.warning("after_run hook failed: #{reason}")
        :ok
    end
  end

  defp render_prompt(prompt_template, project, issue, attempt) do
    project_map = %{name: project.name, config: project.config}
    issue_map = Map.from_struct(issue)
    Renderer.render(prompt_template, project_map, issue_map, attempt)
  end

  defp start_or_continue(config, nil, prompt, workspace_path, _session_id) do
    AgentClient.start_session(config, prompt, workspace_path)
  end

  defp start_or_continue(config, _attempt, prompt, workspace_path, nil) do
    AgentClient.start_session(config, prompt, workspace_path)
  end

  defp start_or_continue(config, _attempt, prompt, workspace_path, session_id) do
    AgentClient.continue_session(config, session_id, prompt, workspace_path)
  end

  defp event_loop(orchestrator, project, issue, session, config, max_turns, turn) do
    port = session.port
    turn_timeout = Config.get(config, "agent", "turn_timeout_ms") || 3_600_000

    receive do
      {^port, {:data, data}} ->
        {session, events} = process_data(data, session)

        # Send events to orchestrator
        for event <- events do
          GenServer.cast(orchestrator, {:agent_event, project.name, issue.id, event})
        end

        event_loop(orchestrator, project, issue, session, config, max_turns, turn)

      {^port, {:exit_status, 0}} ->
        Logger.info("Agent exited normally for #{project.name}:#{issue.identifier}")
        # Check if issue is still active and we have turns left
        if turn < max_turns do
          check_and_continue(orchestrator, project, issue, session, config, max_turns, turn)
        else
          {:ok, :max_turns_reached, session}
        end

      {^port, {:exit_status, code}} ->
        Logger.warning("Agent exited with code #{code} for #{project.name}:#{issue.identifier}")
        {:error, {:agent_exit, code}, session}
    after
      turn_timeout ->
        Logger.warning("Agent turn timed out for #{project.name}:#{issue.identifier}")
        AgentClient.stop_session(config, session)
        {:error, :turn_timeout, session}
    end
  end

  defp check_and_continue(orchestrator, project, issue, session, config, max_turns, turn) do
    # Re-check issue state
    case TrackerClient.fetch_issue_states_by_ids(project.config, project.name, [issue.id]) do
      {:ok, states} ->
        current_state = Map.get(states, issue.id)
        active = Config.active_states(project.config) |> Enum.map(&normalize_state/1)

        if current_state && normalize_state(current_state) in active do
          # Continue with next turn
          continuation_prompt = "Continue working on this issue. Check the current state and proceed."
          session_id = session.session_id

          case start_or_continue(config, turn, continuation_prompt, nil, session_id) do
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

  defp process_data(data, session) do
    lines = String.split(data, "\n", trim: true)

    Enum.reduce(lines, {session, []}, fn line, {sess, events} ->
      case ClaudeCode.parse_event(line) do
        {:ok, event} ->
          sess =
            if event.session_id do
              %{sess | session_id: event.session_id}
            else
              sess
            end

          {sess, events ++ [event]}

        :skip ->
          {sess, events}
      end
    end)
  end

  defp normalize_state(state), do: state |> String.trim() |> String.downcase()
end
