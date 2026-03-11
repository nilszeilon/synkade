defmodule Synkade.Orchestrator do
  @moduledoc false
  use GenServer

  require Logger

  alias Synkade.Orchestrator.{State, Dispatch, Retry, Reconciler, Worker}
  alias Synkade.Workflow.Config
  alias Synkade.Execution.BackendClient
  alias Synkade.Settings
  alias Synkade.Settings.ConfigAdapter
  alias Synkade.Issues

  @pubsub_topic "orchestrator:updates"
  @max_events_per_issue 500

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def pubsub_topic, do: @pubsub_topic

  def agent_events_topic(issue_id), do: "agent_events:#{issue_id}"

  @doc "Get the current orchestrator state."
  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  @doc "Get accumulated events for a specific issue."
  def get_issue_events(server \\ __MODULE__, issue_id) do
    GenServer.call(server, {:get_issue_events, issue_id})
  end

  @doc "Force a refresh."
  def refresh(server \\ __MODULE__) do
    GenServer.cast(server, :refresh)
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    pubsub = opts[:pubsub] || Synkade.PubSub

    # Subscribe to settings/project updates and issues
    Phoenix.PubSub.subscribe(pubsub, Settings.pubsub_topic())
    Phoenix.PubSub.subscribe(pubsub, Issues.pubsub_topic())

    state = %State{} |> Map.put(:__pubsub__, pubsub)

    # Load initial config
    state = load_config(state)

    # Schedule immediate first tick
    send(self(), :poll_tick)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    snapshot = %{
      projects: state.projects,
      poll_interval_ms: state.poll_interval_ms,
      max_concurrent_agents: state.max_concurrent_agents,
      running: state.running,
      claimed: MapSet.to_list(state.claimed),
      retry_attempts: state.retry_attempts,
      awaiting_review: state.awaiting_review,
      agent_totals: state.agent_totals,
      agent_totals_by_project: state.agent_totals_by_project,
      activity_log: state.activity_log,
      config_error: state.config_error
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_call({:get_issue_events, issue_id}, _from, state) do
    events =
      state.running
      |> Enum.find_value(fn {_key, entry} ->
        if entry.issue_id == issue_id, do: Map.get(entry, :events, [])
      end) || []

    {:reply, events, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    send(self(), :poll_tick)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:agent_event, project_name, issue_id, event}, state) do
    key = State.composite_key(project_name, issue_id)

    state =
      case Map.get(state.running, key) do
        nil ->
          state

        entry ->
          entry = %{
            entry
            | last_agent_event: event.type,
              last_agent_timestamp: System.monotonic_time(:millisecond),
              last_agent_message: event.message,
              session_id: event.session_id || entry.session_id
          }

          entry = %{
            entry
            | agent_input_tokens: entry.agent_input_tokens + event.input_tokens,
              agent_output_tokens: entry.agent_output_tokens + event.output_tokens,
              agent_total_tokens: entry.agent_total_tokens + event.total_tokens
          }

          # Accumulate events (capped)
          existing_events = Map.get(entry, :events, [])
          events = Enum.take(existing_events ++ [event], -@max_events_per_issue)
          entry = Map.put(entry, :events, events)

          put_in(state.running[key], entry)
      end

    # Broadcast per-issue event for live session view
    pubsub = state.__pubsub__
    Phoenix.PubSub.broadcast(pubsub, agent_events_topic(issue_id), {:agent_event, event})

    broadcast_state(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:env_ready, project_name, issue_id, env_ref}, state) do
    key = State.composite_key(project_name, issue_id)

    state =
      case Map.get(state.running, key) do
        nil -> state
        entry -> put_in(state.running[key], %{entry | env_ref: env_ref})
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:worker_exit, project_name, issue_id, result}, state) do
    key = State.composite_key(project_name, issue_id)
    entry = Map.get(state.running, key)

    state = %{state | running: Map.delete(state.running, key)}

    state =
      if entry do
        update_totals(state, entry)
      else
        state
      end

    state =
      case result do
        {:ok, {:pr_created, pr_url}, _session} ->
          pr_number = extract_pr_number(pr_url)

          # Transition DB issue to awaiting_review and store PR URL
          update_db_issue_on_pr(entry, pr_url)

          review_entry = %{
            project_name: project_name,
            issue_id: issue_id,
            identifier: (entry && entry.identifier) || issue_id,
            pr_url: pr_url,
            pr_number: pr_number,
            env_ref: entry && entry.env_ref,
            session_id: entry && entry.session_id,
            created_at: System.monotonic_time(:millisecond),
            agent_total_tokens: (entry && entry.agent_total_tokens) || 0
          }

          Logger.info("PR created for #{key}: #{pr_url}")

          %{state | awaiting_review: Map.put(state.awaiting_review, key, review_entry)}

        {:ok, {:completed_with_output, agent_output, children}, _session} ->
          # Research/task completed — store output, create children, mark done
          complete_db_issue_with_output(entry, agent_output, children)
          state

        {:ok, _reason, _session} ->
          # Normal exit - schedule continuation retry
          retry =
            Retry.schedule_continuation(
              self(),
              project_name,
              issue_id,
              (entry && entry.identifier) || issue_id
            )

          %{state | retry_attempts: Map.put(state.retry_attempts, key, retry)}

        {:error, _reason, _session} ->
          # Abnormal exit - schedule backoff retry
          attempt = if entry, do: (entry.attempt || 0) + 1, else: 1
          max_backoff = state |> get_project_config(project_name) |> Config.max_retry_backoff_ms()

          retry =
            Retry.schedule_retry(
              self(),
              project_name,
              issue_id,
              (entry && entry.identifier) || issue_id,
              attempt,
              max_backoff,
              inspect(result)
            )

          %{state | retry_attempts: Map.put(state.retry_attempts, key, retry)}

        {:error, reason} ->
          attempt = if entry, do: (entry.attempt || 0) + 1, else: 1
          max_backoff = state |> get_project_config(project_name) |> Config.max_retry_backoff_ms()

          retry =
            Retry.schedule_retry(
              self(),
              project_name,
              issue_id,
              (entry && entry.identifier) || issue_id,
              attempt,
              max_backoff,
              inspect(reason)
            )

          %{state | retry_attempts: Map.put(state.retry_attempts, key, retry)}
      end

    broadcast_state(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_tick, state) do
    state = do_poll_tick(state)
    schedule_tick(state.poll_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info({:settings_updated, _settings}, state) do
    Logger.info("Orchestrator: applying updated DB settings")
    state = load_config(state)
    broadcast_state(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:projects_updated}, state) do
    Logger.info("Orchestrator: applying updated project config")
    state = load_config(state)
    broadcast_state(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:agents_updated}, state) do
    Logger.info("Orchestrator: applying updated agent config")
    state = load_config(state)
    broadcast_state(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:issues_updated}, state) do
    # Issues changed in DB — trigger a dispatch cycle
    send(self(), :poll_tick)
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry_timer, project_name, issue_id}, state) do
    key = State.composite_key(project_name, issue_id)

    state = %{state | retry_attempts: Map.delete(state.retry_attempts, key)}

    broadcast_state(state)

    # Attempt re-dispatch on next tick
    send(self(), :poll_tick)

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completion - find which issue this was for
    Process.demonitor(ref, [:flush])

    case find_task_entry(state, ref) do
      {_key, entry} ->
        GenServer.cast(self(), {:worker_exit, entry.project_name, entry.issue_id, result})
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private ---

  defp do_poll_tick(state) do
    # 1. Reconcile
    state = Reconciler.reconcile(state)

    # 2. Handle stopped sessions
    state = handle_stopped_sessions(state)

    # 3. Validate config
    state =
      if map_size(state.projects) == 0 do
        load_config(state)
      else
        # 4. Fetch candidates and dispatch
        dispatch_all_projects(state)
      end

    broadcast_state(state)
    state
  end

  defp handle_stopped_sessions(state) do
    # Handle stopped running sessions
    to_stop =
      state.running
      |> Enum.filter(fn {_key, entry} ->
        Map.get(entry, :should_stop) != nil or Map.get(entry, :stalled) == true
      end)

    state =
      Enum.reduce(to_stop, state, fn {key, entry}, acc ->
        # Stop the task if possible
        if entry.task_ref do
          Task.Supervisor.terminate_child(Synkade.TaskSupervisor, entry.task_pid)
        end

        reason = Map.get(entry, :should_stop) || :stalled

        # Cleanup env for terminal issues
        if reason == :terminal do
          project = Map.get(acc.projects, entry.project_name)

          if project && entry.env_ref do
            BackendClient.destroy_env(project.config, entry.env_ref)
          end
        end

        running = Map.delete(acc.running, key)
        claimed = MapSet.delete(acc.claimed, key)
        %{acc | running: running, claimed: claimed}
      end)

    # Handle resolved awaiting_review entries
    resolved_reviews =
      state.awaiting_review
      |> Enum.filter(fn {_key, entry} -> Map.get(entry, :should_stop) != nil end)

    Enum.reduce(resolved_reviews, state, fn {key, entry}, acc ->
      project = Map.get(acc.projects, entry.project_name)

      if project && entry.env_ref do
        BackendClient.destroy_env(project.config, entry.env_ref)
      end

      Logger.info("PR #{entry.should_stop} for #{key}, cleaning up")

      %{
        acc
        | awaiting_review: Map.delete(acc.awaiting_review, key),
          claimed: MapSet.delete(acc.claimed, key)
      }
    end)
  end

  defp dispatch_all_projects(state) do
    enabled_projects =
      state.projects
      |> Map.values()
      |> Enum.filter(& &1.enabled)

    Enum.reduce(enabled_projects, state, fn project, acc ->
      dispatch_project(acc, project)
    end)
  end

  defp dispatch_project(state, project) do
    db_project_id = project[:db_id]

    if db_project_id do
      db_issues =
        try do
          Issues.list_queued_issues(db_project_id)
        catch
          _, _ -> []
        end

      tracker_issues =
        Enum.map(db_issues, fn db_issue ->
          db_issue_to_tracker_issue(db_issue, project)
        end)

      candidates =
        tracker_issues
        |> Dispatch.filter_candidates(state, project)
        |> Dispatch.sort_candidates()

      dispatch_candidates(state, project, candidates, db_issues)
    else
      state
    end
  end

  defp dispatch_candidates(state, _project, [], _db_issues), do: state

  defp dispatch_candidates(state, project, [issue | rest], db_issues) do
    slots = Dispatch.available_slots(state, project)
    state_slots = Dispatch.available_state_slots(state, project, issue.state)

    if slots > 0 and state_slots > 0 do
      state = dispatch_issue(state, project, issue, db_issues)
      dispatch_candidates(state, project, rest, db_issues)
    else
      state
    end
  end

  defp dispatch_issue(state, project, issue, db_issues) do
    key = State.composite_key(project.name, issue.id)

    # Check retry to get attempt number
    attempt =
      case Map.get(state.retry_attempts, key) do
        %{attempt: a} -> a
        _ -> nil
      end

    # Claim the issue
    state = %{state | claimed: MapSet.put(state.claimed, key)}

    # Remove from retry if present
    state =
      case Map.get(state.retry_attempts, key) do
        nil ->
          state

        retry ->
          Retry.cancel_retry(retry)
          %{state | retry_attempts: Map.delete(state.retry_attempts, key)}
      end

    # Transition DB issue to in_progress
    db_issue = Enum.find(db_issues, fn di -> di.id == issue.id end)

    if db_issue do
      try do
        Issues.transition_state(db_issue, "in_progress")
      catch
        _, _ -> :ok
      end
    end

    # Resolve per-issue agent override
    effective_project = resolve_issue_agent_override(project, db_issue)

    # Launch worker task
    orchestrator = self()

    task =
      Task.Supervisor.async_nolink(Synkade.TaskSupervisor, fn ->
        Worker.run(orchestrator, effective_project, issue, attempt)
      end)

    entry = %{
      project_name: project.name,
      issue_id: issue.id,
      identifier: issue.identifier,
      issue_state: issue.state,
      db_issue_id: issue.id,
      attempt: attempt,
      env_ref: nil,
      session_id: nil,
      task_ref: task.ref,
      task_pid: task.pid,
      started_at: System.monotonic_time(:millisecond),
      last_agent_event: nil,
      last_agent_timestamp: nil,
      last_agent_message: nil,
      agent_input_tokens: 0,
      agent_output_tokens: 0,
      agent_total_tokens: 0,
      turn_count: 0,
      stalled: false,
      should_stop: nil,
      events: []
    }

    state = %{state | running: Map.put(state.running, key, entry)}

    # Append to activity log (capped at 365 entries)
    log_entry = %{project_name: project.name, timestamp: DateTime.utc_now()}
    activity_log = Enum.take([log_entry | state.activity_log], 365)
    state = %{state | activity_log: activity_log}

    Logger.info("Dispatched #{project.name}:#{issue.identifier}")
    broadcast_state(state)
    state
  end

  defp load_config(state) do
    db_settings =
      try do
        Settings.get_settings()
      catch
        _, _ -> nil
      end

    db_projects =
      try do
        Settings.list_enabled_projects()
      catch
        _, _ -> []
      end

    db_agents =
      try do
        Settings.list_agents()
      catch
        _, _ -> []
      end

    case {db_settings, db_projects} do
      {nil, _} ->
        %{state | config_error: "No settings configured"}

      {%Settings.Setting{}, []} ->
        %{state | config_error: "No projects configured", projects: %{}}

      {%Settings.Setting{} = setting, projects} ->
        agents_by_id = Map.new(db_agents, fn a -> {a.id, a} end)
        first_agent = List.first(db_agents)

        project_entries =
          Enum.map(projects, fn project ->
            agent = agents_by_id[project.default_agent_id] || first_agent

            case agent do
              nil ->
                config = ConfigAdapter.to_config(setting)

                %{
                  name: project.name,
                  db_id: project.id,
                  config: config,
                  prompt_template: project.prompt_template,
                  max_concurrent_agents: Config.max_concurrent_agents(config),
                  enabled: project.enabled
                }

              %Settings.Agent{} = a ->
                config = ConfigAdapter.resolve_project_config(setting, project, a)

                # Inject Synkade API URL for agent runtime access
                api_url =
                  try do
                    SynkadeWeb.Endpoint.url() <> "/api/v1/agent"
                  catch
                    _, _ -> nil
                  end

                config =
                  if api_url do
                    put_in(config, ["agent", "synkade_api_url"], api_url)
                  else
                    config
                  end

                %{
                  name: project.name,
                  db_id: project.id,
                  config: config,
                  prompt_template: project.prompt_template || a.system_prompt,
                  max_concurrent_agents: Config.max_concurrent_agents(config),
                  enabled: project.enabled
                }
            end
          end)

        projects_map = Map.new(project_entries, fn p -> {p.name, p} end)

        first_config =
          case project_entries do
            [first | _] -> first.config
            [] -> ConfigAdapter.to_config(setting)
          end

        %{
          state
          | config_error: nil,
            projects: projects_map,
            poll_interval_ms: Config.poll_interval_ms(first_config),
            max_concurrent_agents: Config.max_concurrent_agents(first_config)
        }
    end
  end

  defp update_totals(state, entry) do
    totals = state.agent_totals

    runtime_seconds =
      if entry.started_at do
        (System.monotonic_time(:millisecond) - entry.started_at) / 1000
      else
        0.0
      end

    totals = %{
      totals
      | input_tokens: totals.input_tokens + entry.agent_input_tokens,
        output_tokens: totals.output_tokens + entry.agent_output_tokens,
        total_tokens: totals.total_tokens + entry.agent_total_tokens,
        runtime_seconds: totals.runtime_seconds + runtime_seconds
    }

    project_totals =
      Map.get(state.agent_totals_by_project, entry.project_name, %{
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0,
        runtime_seconds: 0.0
      })

    project_totals = %{
      project_totals
      | input_tokens: project_totals.input_tokens + entry.agent_input_tokens,
        output_tokens: project_totals.output_tokens + entry.agent_output_tokens,
        total_tokens: project_totals.total_tokens + entry.agent_total_tokens,
        runtime_seconds: project_totals.runtime_seconds + runtime_seconds
    }

    %{
      state
      | agent_totals: totals,
        agent_totals_by_project:
          Map.put(state.agent_totals_by_project, entry.project_name, project_totals)
    }
  end

  defp schedule_tick(interval_ms) do
    Process.send_after(self(), :poll_tick, interval_ms)
  end

  defp broadcast_state(state) do
    pubsub = state.__pubsub__

    # Strip events from running entries to avoid large broadcast payloads
    running_slim =
      Map.new(state.running, fn {key, entry} ->
        {key, Map.delete(entry, :events)}
      end)

    snapshot = %{
      running: running_slim,
      retry_attempts: state.retry_attempts,
      awaiting_review: state.awaiting_review,
      agent_totals: state.agent_totals,
      agent_totals_by_project: state.agent_totals_by_project,
      activity_log: state.activity_log,
      projects: state.projects,
      config_error: state.config_error
    }

    Phoenix.PubSub.broadcast(pubsub, @pubsub_topic, {:state_changed, snapshot})
  end

  defp get_project_config(state, project_name) do
    case Map.get(state.projects, project_name) do
      nil -> %{}
      project -> project.config
    end
  end

  defp find_task_entry(state, ref) do
    Enum.find(state.running, fn {_key, entry} -> entry.task_ref == ref end)
  end

  defp extract_pr_number(pr_url) do
    case Regex.run(~r{/pull/(\d+)$}, pr_url) do
      [_, number] -> number
      _ -> nil
    end
  end

  defp db_issue_to_tracker_issue(db_issue, project) do
    %Synkade.Tracker.Issue{
      project_name: project.name,
      id: db_issue.id,
      identifier: "#{project.name}##{db_issue.id |> String.slice(0..7)}",
      title: db_issue.title,
      description: db_issue.description,
      state: db_issue.state,
      priority: db_issue.priority,
      labels: [],
      blocked_by: [],
      created_at: db_issue.inserted_at,
      updated_at: db_issue.updated_at
    }
  end

  defp update_db_issue_on_pr(nil, _pr_url), do: :ok

  defp update_db_issue_on_pr(entry, pr_url) do
    try do
      db_issue = Issues.get_issue(entry.db_issue_id)

      if db_issue do
        Issues.update_issue(db_issue, %{github_pr_url: pr_url})
        Issues.transition_state(db_issue, "awaiting_review")
      end
    catch
      _, _ -> :ok
    end
  end

  defp resolve_issue_agent_override(project, nil), do: project

  defp resolve_issue_agent_override(project, db_issue) do
    case db_issue.assigned_agent_id do
      nil ->
        project

      agent_id ->
        try do
          agent = Settings.get_agent!(agent_id)
          setting = Settings.get_settings()
          db_project = Settings.get_project!(project.db_id)
          config = ConfigAdapter.resolve_project_config(setting, db_project, agent)

          %{project | config: config, prompt_template: db_project.prompt_template || agent.system_prompt}
        catch
          _, _ -> project
        end
    end
  end

  defp complete_db_issue_with_output(nil, _output, _children), do: :ok

  defp complete_db_issue_with_output(entry, agent_output, children) do
    try do
      db_issue = Issues.get_issue(entry.db_issue_id)

      if db_issue do
        Issues.update_issue(db_issue, %{agent_output: agent_output})
        Issues.transition_state(db_issue, "done")

        if children != [] do
          Issues.create_children_from_agent(db_issue, children)
        end
      end
    catch
      _, _ -> :ok
    end
  end
end
