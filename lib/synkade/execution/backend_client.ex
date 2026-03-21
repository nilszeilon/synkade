defmodule Synkade.Execution.BackendClient do
  @moduledoc false

  alias Synkade.Workflow.Config

  @backends %{
    "local" => Synkade.Execution.Local,
    "sprites" => Synkade.Execution.Sprites
  }

  def backend_for(config) do
    backend_name = Config.get(config, "execution", "backend") || "local"
    Map.get(@backends, backend_name) || raise "Unsupported execution backend: #{backend_name}"
  end

  def setup_env(config, project_name, issue_identifier) do
    backend_for(config).setup_env(config, project_name, issue_identifier)
  end

  def run_before_hook(config, env_ref) do
    backend_for(config).run_before_hook(config, env_ref)
  end

  def start_agent(config, prompt, env_ref) do
    backend_for(config).start_agent(config, prompt, env_ref)
  end

  def continue_agent(config, session_id, prompt, env_ref) do
    backend_for(config).continue_agent(config, session_id, prompt, env_ref)
  end

  def await_event(config, session, timeout_ms) do
    backend_for(config).await_event(session, timeout_ms)
  end

  def stop_agent(config, session) do
    backend_for(config).stop_agent(session)
  end

  def run_after_hook(config, env_ref) do
    backend_for(config).run_after_hook(config, env_ref)
  end

  def parse_event(config, line) do
    backend_for(config).parse_event(config, line)
  end
end
