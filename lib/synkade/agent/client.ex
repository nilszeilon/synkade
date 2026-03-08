defmodule Synkade.Agent.Client do
  @moduledoc false

  alias Synkade.Workflow.Config

  @adapters %{
    "claude" => Synkade.Agent.ClaudeCode
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

  defp adapter_for(config) do
    kind = Config.agent_kind(config)
    Map.get(@adapters, kind) || raise "Unsupported agent kind: #{kind}"
  end
end
