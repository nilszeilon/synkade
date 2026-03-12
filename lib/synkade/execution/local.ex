defmodule Synkade.Execution.Local do
  @moduledoc false
  @behaviour Synkade.Execution.Backend

  require Logger

  alias Synkade.Workspace.{Manager, Hooks}
  alias Synkade.Agent.Client, as: AgentClient
  alias Synkade.Workflow.Config

  @impl true
  def setup_env(config, project_name, issue_identifier) do
    Manager.ensure_workspace(config, project_name, issue_identifier)
  end

  @impl true
  def run_before_hook(config, workspace) do
    hooks = Config.get_section(config, "hooks")
    timeout = hooks["timeout_ms"] || 60_000

    case Hooks.run_hook(hooks["before_run"], workspace.path, timeout_ms: timeout) do
      :ok -> :ok
      {:error, reason} -> {:error, {:hook_failed, :before_run, reason}}
    end
  end

  @impl true
  def start_agent(config, prompt, workspace) do
    case AgentClient.start_session(config, prompt, workspace.path) do
      {:ok, agent_session} ->
        session = %{
          session_id: agent_session.session_id,
          env_ref: workspace,
          events: [],
          backend_data: %{port: agent_session.port, os_pid: agent_session[:os_pid]},
          # Keep the original agent session for stop_agent and port matching
          agent_session: agent_session
        }

        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def continue_agent(config, session_id, prompt, workspace) do
    workspace_path = if is_map(workspace), do: workspace.path, else: nil

    case AgentClient.continue_session(config, session_id, prompt, workspace_path) do
      {:ok, agent_session} ->
        session = %{
          session_id: agent_session.session_id,
          env_ref: workspace,
          events: [],
          backend_data: %{port: agent_session.port, os_pid: agent_session[:os_pid]},
          agent_session: agent_session
        }

        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def await_event(session, timeout_ms) do
    port = session.backend_data.port
    require Logger
    Logger.warning("await_event: waiting on port=#{inspect(port)}, timeout=#{timeout_ms}")

    receive do
      {^port, {:data, {:eol, chunk}}} ->
        Logger.info(
          "Received eol data from agent port: #{String.slice(to_string(chunk), 0..200)}"
        )

        {:data, to_string(chunk)}

      {^port, {:data, {:noeol, chunk}}} ->
        Logger.info(
          "Received noeol data from agent port: #{String.slice(to_string(chunk), 0..200)}"
        )

        {:partial, to_string(chunk)}

      {^port, {:exit_status, code}} ->
        Logger.warning("Agent port exit status: #{code}")
        {:exit, code}
    after
      timeout_ms ->
        Logger.warning("await_event: timeout after #{timeout_ms}ms")
        :timeout
    end
  end

  @impl true
  def stop_agent(session) do
    AgentClient.stop_session(%{}, session.agent_session)
    :ok
  end

  @impl true
  def run_after_hook(config, workspace) do
    hooks = Config.get_section(config, "hooks")
    timeout = hooks["timeout_ms"] || 60_000

    case Hooks.run_hook(hooks["after_run"], workspace.path, timeout_ms: timeout) do
      :ok ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("after_run hook failed: #{reason}")
        :ok
    end
  end

  @impl true
  def destroy_env(config, workspace) do
    Manager.cleanup_workspace(config, workspace)
  end

  @impl true
  def parse_event(config, line) do
    AgentClient.parse_event(config, line)
  end
end
