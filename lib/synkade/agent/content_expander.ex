defmodule Synkade.Agent.ContentExpander do
  @moduledoc """
  Expands Claude-format assistant messages with multiple content blocks
  (thinking, text, tool_use) into separate Agent.Event structs.

  Used by all Claude-compatible agents: ClaudeCode, Hermes.
  """

  alias Synkade.Agent.Event

  @doc """
  Given a decoded JSON map that has `type: "assistant"` with a `message.content`
  list, expands each content block into a separate Event.

  Returns a list of events, or an empty list if there are no expandable blocks.
  The `session_id_fn` extracts the session_id from the raw data (varies by adapter).
  """
  @spec expand(map(), (map() -> String.t() | nil)) :: [Event.t()]
  def expand(%{"type" => "assistant", "message" => %{"content" => content}} = data, session_id_fn)
      when is_list(content) do
    session_id = session_id_fn.(data)
    usage = data["usage"] || %{}
    model = data["model"] || usage["model"]

    Enum.flat_map(content, fn
      %{"type" => "thinking", "thinking" => text} when is_binary(text) and text != "" ->
        [
          %Event{
            type: "thinking",
            session_id: session_id,
            message: text,
            model: model,
            timestamp: DateTime.utc_now(),
            raw: %{"type" => "thinking", "text" => text}
          }
        ]

      %{"type" => "text", "text" => text} when is_binary(text) and text != "" ->
        [
          %Event{
            type: "assistant",
            session_id: session_id,
            message: text,
            model: model,
            input_tokens: usage["input_tokens"] || 0,
            output_tokens: usage["output_tokens"] || 0,
            total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0),
            timestamp: DateTime.utc_now(),
            raw: data
          }
        ]

      %{"type" => "tool_use", "name" => name} = tool ->
        [
          %Event{
            type: "tool_use",
            session_id: session_id,
            model: model,
            timestamp: DateTime.utc_now(),
            raw: %{
              "type" => "tool_use",
              "tool" => %{"name" => name, "input" => tool["input"] || %{}},
              "input" => tool["input"] || %{},
              "tool_use_id" => tool["id"]
            }
          }
        ]

      _ ->
        []
    end)
  end

  def expand(_data, _session_id_fn), do: []
end
