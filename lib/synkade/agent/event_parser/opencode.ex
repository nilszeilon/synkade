defmodule Synkade.Agent.EventParser.OpenCode do
  @moduledoc """
  Event parser for OpenCode agent.

  OpenCode JSON format (real observed output from `opencode run --format json`):
    - tool_use: {"type": "tool_use", "part": {"type": "tool", "tool": "read", "callID": "functions.read:0",
        "state": {"status": "completed"|"error", "input": {"filePath": "..."}, "output": "...",
                  "title": "short description", "metadata": {...}}}}
    - text:     {"type": "text", "part": {"type": "text", "text": "..."}}
    - step:     {"type": "step_start"|"step_finish", "part": {"type": "step-start"|"step-finish", ...}}
    - No separate tool_result events — status is carried inside part.state.status.
    - Input keys are camelCase (filePath, oldString, etc.) — normalized to snake_case.
  """

  @behaviour Synkade.Agent.EventParser

  @impl true
  def extract_name_and_input(raw) do
    part = raw["part"] || %{}
    state = part["state"] || %{}
    name = part["tool"] || raw["name"] || "tool"
    input = state["input"] || part["input"] || %{}
    input = if is_map(input), do: normalize_keys(input), else: %{}
    {name, input}
  end

  # OpenCode sends camelCase keys (filePath, oldString, etc.)
  # Normalize to snake_case so extract_detail finds them.
  @key_map %{
    "filePath" => "file_path",
    "oldString" => "old_string",
    "newString" => "new_string",
    "old_string" => "old_string",
    "new_string" => "new_string",
    "file_path" => "file_path"
  }

  defp normalize_keys(input) when is_map(input) do
    Map.new(input, fn {k, v} -> {Map.get(@key_map, k, k), v} end)
  end

  @impl true
  def extract_output(event) do
    raw = event.raw || %{}

    get_in(raw, ["part", "state", "output"]) || get_in(raw, ["part", "output"]) ||
      raw["output"] || event.message
  end

  @impl true
  def resolve_status(_status, raw) do
    case get_in(raw, ["part", "state", "status"]) do
      s when s in ["completed", "error"] -> :done
      _ -> :running
    end
  end
end
