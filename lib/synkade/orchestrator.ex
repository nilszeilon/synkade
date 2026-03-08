defmodule Synkade.Orchestrator do
  @moduledoc false
  use GenServer

  require Logger

  alias Synkade.Orchestrator.{State, Dispatch, Retry, Reconciler, Worker}
  alias Synkade.Workflow.{Config, Watcher, ProjectRegistry}
  alias Synkade.Tracker.Client, as: TrackerClient
  alias Synkade.Workspace.Manager, as: WorkspaceManager
  alias Synkade.Settings
  alias Synkade.Settings.ConfigAdapter

  @pubsub_topic "orchestrator:updates"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def pubsub_topic, do: @pubsub_topic

  @doc "Get the current orchestrator state."
  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  @doc "Force a refresh."
  def refresh(server \\ __MODULE__) do
    GenServer.cast(server, :refresh)
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    watcher = opts[:watcher] || Watcher
    pubsub = opts[:pubsub] || Synkade.PubSub

    # Subscribe to workflow and settings updates
    Phoenix.PubSub.subscribe(pubsub, Watcher.pubsub_topic())
    Phoenix.PubSub.subscribe(pubsub, Settings.pubsub_topic())

    state = %State{} |> Map.put(:__watcher__, watcher) |> Map.put(:__pubsub__, pubsub)

    # Load initial workflow
    state = load_workflow(state)

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
      completed: MapSet.to_list(state.completed),
      agent_totals: state.agent_totals,
      agent_totals_by_project: state.agent_totals_by_project,
      activity_log: state.activity_log,
      workflow_error: state.workflow_error
    }

    {:reply, snapshot, state}
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

          put_in(state.running[key], entry)
      end

    broadcast_state(state)
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
        {:ok, _reason, _session} ->
          # Normal exit - schedule continuation retry
          retry =
            Retry.schedule_continuation(
              self(),
              project_name,
              issue_id,
              entry && entry.identifier || issue_id
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
              entry && entry.identifier || issue_id,
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
              entry && entry.identifier || issue_id,
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
  def handle_info({:workflow_reloaded, workflow}, state) do
    Logger.info("Orchestrator: applying reloaded workflow")
    state = apply_workflow(state, workflow)
    broadcast_state(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:settings_updated, _settings}, state) do
    Logger.info("Orchestrator: applying updated DB settings")
    state = load_workflow(state)
    broadcast_state(state)
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

    # 3. Validate workflow
    state =
      case state.workflow do
        nil ->
          load_workflow(state)

        _workflow ->
          # 4. Fetch candidates and dispatch
          dispatch_all_projects(state)
      end

    broadcast_state(state)
    state
  end

  defp handle_stopped_sessions(state) do
    to_stop =
      state.running
      |> Enum.filter(fn {_key, entry} ->
        Map.get(entry, :should_stop) != nil or Map.get(entry, :stalled) == true
      end)

    Enum.reduce(to_stop, state, fn {key, entry}, acc ->
      # Stop the task if possible
      if entry.task_ref do
        Task.Supervisor.terminate_child(Synkade.TaskSupervisor, entry.task_pid)
      end

      reason = Map.get(entry, :should_stop) || :stalled

      # Cleanup workspace for terminal issues
      if reason == :terminal do
        project = Map.get(acc.projects, entry.project_name)

        if project do
          workspace = %Synkade.Workspace{
            project_name: entry.project_name,
            path: entry.workspace_path || "",
            workspace_key: key
          }

          WorkspaceManager.cleanup_workspace(project.config, workspace)
        end
      end

      running = Map.delete(acc.running, key)
      claimed = MapSet.delete(acc.claimed, key)
      %{acc | running: running, claimed: claimed}
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
    case TrackerClient.fetch_candidate_issues(project.config, project.name) do
      {:ok, issues} ->
        candidates =
          issues
          |> Dispatch.filter_candidates(state, project)
          |> Dispatch.sort_candidates()

        dispatch_candidates(state, project, candidates)

      {:error, reason} ->
        Logger.warning("Failed to fetch issues for #{project.name}: #{inspect(reason)}")
        state
    end
  end

  defp dispatch_candidates(state, _project, []), do: state

  defp dispatch_candidates(state, project, [issue | rest]) do
    slots = Dispatch.available_slots(state, project)
    state_slots = Dispatch.available_state_slots(state, project, issue.state)

    if slots > 0 and state_slots > 0 do
      state = dispatch_issue(state, project, issue)
      dispatch_candidates(state, project, rest)
    else
      state
    end
  end

  defp dispatch_issue(state, project, issue) do
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
        nil -> state
        retry ->
          Retry.cancel_retry(retry)
          %{state | retry_attempts: Map.delete(state.retry_attempts, key)}
      end

    # Launch worker task
    orchestrator = self()

    task =
      Task.Supervisor.async_nolink(Synkade.TaskSupervisor, fn ->
        Worker.run(orchestrator, project, issue, attempt)
      end)

    entry = %{
      project_name: project.name,
      issue_id: issue.id,
      identifier: issue.identifier,
      issue_state: issue.state,
      attempt: attempt,
      workspace_path: nil,
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
      should_stop: nil
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

  defp load_workflow(state) do
    watcher = state.__watcher__

    db_settings =
      try do
        Settings.get_settings()
      rescue
        _ -> nil
      end

    case {Watcher.get_workflow(watcher), db_settings} do
      {{:ok, workflow}, %Settings.Setting{} = setting} when not is_nil(workflow) ->
        # Both exist — merge DB over file (DB wins)
        merged_config = ConfigAdapter.merge_into(workflow.config, setting)
        merged_workflow = %{workflow | config: merged_config}
        apply_workflow(state, merged_workflow)

      {{:ok, nil}, %Settings.Setting{} = setting} ->
        # Only DB settings — build config from DB
        config = ConfigAdapter.to_config(setting)

        workflow = %{
          config: config,
          prompt_template: setting.prompt_template,
          raw: nil,
          path: nil
        }

        apply_workflow(state, workflow)

      {{:ok, workflow}, nil} when not is_nil(workflow) ->
        # Only WORKFLOW.md — use as-is
        apply_workflow(state, workflow)

      _ ->
        %{state | workflow: nil, workflow_error: "No workflow loaded"}
    end
  end

  defp apply_workflow(state, workflow) do
    config = workflow.config

    # Start GitHub App services if needed
    maybe_start_app_services(config)

    projects = ProjectRegistry.resolve_projects(config, workflow.prompt_template)

    projects_map =
      Map.new(projects, fn p -> {p.name, p} end)

    %{
      state
      | workflow: workflow,
        workflow_error: nil,
        projects: projects_map,
        poll_interval_ms: Config.poll_interval_ms(config),
        max_concurrent_agents: Config.max_concurrent_agents(config)
    }
  end

  defp maybe_start_app_services(config) do
    if Config.auth_mode(config) == "app" do
      app_id = Config.get(config, "tracker", "app_id")
      pem = Config.private_key_pem(config)

      if app_id && pem do
        # Start InstallationRegistry if not already running
        case DynamicSupervisor.start_child(
               Synkade.GitHubAppSupervisor,
               {Synkade.Tracker.GitHub.InstallationRegistry,
                app_id: app_id, private_key_pem: pem}
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> Logger.warning("Failed to start InstallationRegistry: #{inspect(reason)}")
        end

        # Start TokenServers for any explicit installation_id
        case Config.get(config, "tracker", "installation_id") do
          nil ->
            :ok

          installation_id ->
            case DynamicSupervisor.start_child(
                   Synkade.GitHubAppSupervisor,
                   {Synkade.Tracker.GitHub.TokenServer,
                    installation_id: installation_id, app_id: app_id, private_key_pem: pem}
                 ) do
              {:ok, _pid} -> :ok
              {:error, {:already_started, _pid}} -> :ok
              {:error, reason} -> Logger.warning("Failed to start TokenServer: #{inspect(reason)}")
            end
        end
      end
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

    project_totals = Map.get(state.agent_totals_by_project, entry.project_name, %{
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

    snapshot = %{
      running: state.running,
      retry_attempts: state.retry_attempts,
      agent_totals: state.agent_totals,
      agent_totals_by_project: state.agent_totals_by_project,
      activity_log: state.activity_log,
      projects: state.projects,
      workflow_error: state.workflow_error
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
end
