defmodule Synkade.Agent.Client do
  @moduledoc false

  alias Synkade.Workflow.Config

  @adapters %{
    "claude" => Synkade.Agent.ClaudeCode,
    "opencode" => Synkade.Agent.OpenCode,
    "hermes" => Synkade.Agent.Hermes
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

  @doc "Stops a port-based agent session by closing the port and killing the OS process."
  def stop_port_session(%{port: port, os_pid: os_pid}) when not is_nil(port) do
    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    if os_pid do
      System.cmd("kill", [to_string(os_pid)], stderr_to_stdout: true)
    end

    :ok
  end

  def stop_port_session(_), do: :ok

  defp adapter_for(config) do
    kind = Config.agent_kind(config)
    Map.get(@adapters, kind) || raise "Unsupported agent kind: #{kind}"
  end
end
