defmodule Synkade.Agent.Client do
  @moduledoc false

  alias Synkade.Workflow.Config

  @adapters %{
    "claude" => Synkade.Agent.ClaudeCode,
    "opencode" => Synkade.Agent.OpenCode
  }

  def start_session(config, prompt, workspace_path) do
    adapter = adapter_for(config)
    adapter.start_session(config, prompt, workspace_path)
  end

  def continue_session(config, session_id, prompt, workspace_path) do
    adapter = adapter_for(config)
    adapter.continue_session(config, session_id, prompt, workspace_path)
  end

  def stop_session(config, session) do
    adapter = adapter_for(config)
    adapter.stop_session(session)
  end

  def build_args(config, prompt, extra_args) do
    adapter = adapter_for(config)
    adapter.build_args(config, prompt, extra_args)
  end

  def build_env(config) do
    adapter = adapter_for(config)
    adapter.build_env(config)
  end

  def parse_event(config, line) do
    adapter = adapter_for(config)
    adapter.parse_event(line)
  end

  defp adapter_for(config) do
    kind = Config.agent_kind(config)
    Map.get(@adapters, kind) || raise "Unsupported agent kind: #{kind}"
  end
end
