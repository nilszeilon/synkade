defmodule Synkade.Agent.EventParser.OpenCode do
  @moduledoc """
  Event parser for OpenCode agent.

  OpenCode JSON format:
    - tool_use: {"type": "tool_use", "part": {"tool": "Read", "state": {"status": "completed"|"running", "input": {...}, "output": "..."}}}
    - No separate tool_result events — status is carried inside part.state.status.
  """

  @behaviour Synkade.Agent.EventParser

  @impl true
  def extract_name_and_input(raw) do
    part = raw["part"] || %{}
    state = part["state"] || %{}
    name = part["tool"] || raw["name"] || "tool"
    input = state["input"] || part["input"] || %{}
    input = if is_map(input), do: input, else: %{}
    {name, input}
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
