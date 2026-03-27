defmodule Synkade.Agent.EventParser.Claude do
  @moduledoc """
  Event parser for Claude Code agent.

  Claude Code stream-json format:
    - tool_use:   {"type": "tool_use", "tool": "Read" | {"name": "Read", "input": {...}}, "input": {...}}
    - tool_result: {"type": "tool_result", "tool": "Read", "output": "...", "content": "..."}
  """

  @behaviour Synkade.Agent.EventParser

  @impl true
  def extract_name_and_input(raw) do
    case raw["tool"] do
      %{"name" => n} = tool_map ->
        {n, tool_map["input"] || %{}}

      n when is_binary(n) ->
        {n, raw["input"] || raw["tool_input"] || %{}}

      _ ->
        n = raw["name"] || "tool"
        {n, raw["input"] || raw["tool_input"] || %{}}
    end
  end

  @impl true
  def extract_output(event) do
    raw = event.raw || %{}
    raw["output"] || raw["content"] || raw["result"] || event.message
  end

  @impl true
  def resolve_status(status, _raw), do: status
end
