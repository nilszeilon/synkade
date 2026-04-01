defmodule Synkade.Agent.EventParser do
  @moduledoc """
  Per-agent extraction of structured tool info from raw events.
  Dispatches to agent-specific parsers based on agent_kind.
  """

  alias Synkade.Agent.Event
  alias Synkade.Agent.EventParser.{Claude, OpenCode}

  @type tool_info :: %{
          name: String.t(),
          detail: String.t() | nil,
          input_preview: String.t() | nil,
          file_name: String.t() | nil,
          output: String.t() | nil,
          status: :running | :done
        }

  @callback extract_name_and_input(raw :: map()) :: {String.t(), map()}
  @callback extract_output(event :: Event.t()) :: String.t() | nil
  @callback resolve_status(status :: :running | :done, raw :: map()) :: :running | :done

  @doc "Extract structured tool info from an event, dispatching by agent kind."
  @spec build_tool_info(Event.t(), :running | :done, String.t() | nil) :: tool_info()
  def build_tool_info(event, status, agent_kind) do
    parser = parser_for(agent_kind)
    raw = event.raw || %{}

    status = parser.resolve_status(status, raw)
    {name, input} = parser.extract_name_and_input(raw)
    {detail, input_preview, file_name} = extract_detail(name, input)

    # Fallback: use OpenCode's state.title, then event message
    {detail, file_name} =
      cond do
        not is_nil(detail) or not is_nil(file_name) ->
          {detail, file_name}

        # OpenCode puts a human-friendly title in part.state.title
        is_binary(title = get_in(raw, ["part", "state", "title"])) and title != "" ->
          {String.slice(title, 0..100), nil}

        is_binary(event.message) and event.message != "" ->
          {String.slice(event.message, 0..100), nil}

        true ->
          {detail, file_name}
      end

    output = if status == :done, do: parser.extract_output(event), else: nil

    base = %{
      name: name,
      detail: detail,
      input_preview: input_preview,
      file_name: file_name,
      output: output,
      status: status
    }

    # For Edit tools, capture old/new strings for diff rendering
    if name in ~w(Edit edit MultiEdit) and is_map(input) do
      old = input["old_string"] || input["old"] || ""
      new = input["new_string"] || input["new"] || ""

      Map.merge(base, %{
        edit_old: old,
        edit_new: new,
        edit_additions: length(String.split(new, "\n")),
        edit_deletions: length(String.split(old, "\n"))
      })
    else
      base
    end
  end

  @doc "Mark a tool as done with output from a result event."
  @spec mark_done(tool_info(), Event.t(), String.t() | nil) :: tool_info()
  def mark_done(tool, result_event, agent_kind) do
    parser = parser_for(agent_kind)
    %{tool | status: :done, output: parser.extract_output(result_event)}
  end

  @doc "Display name for rendering."
  @spec display_name(tool_info()) :: String.t()
  def display_name(%{name: name, detail: detail}) do
    case name do
      n when n in ~w(Read read) -> "Read#{detail || ""}"
      n when n in ~w(Write write) -> "Write"
      n when n in ~w(Edit edit MultiEdit) -> "Edit"
      n when n in ~w(Bash bash) -> "Bash"
      n when n in ~w(Glob glob) -> "Glob"
      n when n in ~w(Grep grep) -> "Grep"
      n when n in ~w(Agent) -> "Agent"
      n when n in ~w(WebSearch) -> "Search"
      n when n in ~w(WebFetch) -> "Fetch"
      other -> other
    end
  end

  @doc "Icon character for rendering."
  @spec icon(String.t()) :: String.t()
  def icon(name) do
    case name do
      n when n in ~w(Read read) -> "\u{1F4C4}"
      n when n in ~w(Write write) -> "\u{1F4DD}"
      n when n in ~w(Edit edit MultiEdit) -> "\u{270F}\u{FE0F}"
      n when n in ~w(Bash bash) -> "\u{2318}"
      n when n in ~w(Glob glob) -> "\u{1F50D}"
      n when n in ~w(Grep grep) -> "\u{1F50E}"
      n when n in ~w(Agent) -> "\u{1F916}"
      n when n in ~w(WebSearch WebFetch) -> "\u{1F310}"
      n when n in ~w(TodoRead TodoWrite) -> "\u{1F4CB}"
      _ -> "\u{1F527}"
    end
  end

  # --- Shared detail extraction (input is already resolved by agent parser) ---

  @doc false
  def extract_detail(name, input) when is_map(input) do
    case name do
      n when n in ~w(Read read) ->
        path = input["file_path"] || input["path"]
        limit = input["limit"]
        suffix = if limit, do: " #{limit} lines", else: ""
        {suffix, nil, path && Path.basename(path)}

      n when n in ~w(Write write) ->
        path = input["file_path"] || input["path"]
        {nil, nil, path && Path.basename(path)}

      n when n in ~w(Edit edit MultiEdit) ->
        path = input["file_path"] || input["path"]
        old = input["old_string"] || input["old"]
        preview = if old, do: String.slice(to_string(old), 0..120), else: nil
        {nil, preview, path && Path.basename(path)}

      n when n in ~w(Bash bash) ->
        cmd = input["command"] || input["cmd"]
        {nil, cmd, nil}

      n when n in ~w(Glob glob) ->
        {input["pattern"], nil, nil}

      n when n in ~w(Grep grep) ->
        pattern = input["pattern"]
        path = input["path"]
        detail = [pattern, path] |> Enum.filter(& &1) |> Enum.join(" in ")
        {detail, nil, nil}

      n when n in ~w(Agent) ->
        {input["description"] || input["prompt"], nil, nil}

      n when n in ~w(WebSearch WebFetch) ->
        {input["query"] || input["url"], nil, nil}

      _ ->
        first_val =
          input
          |> Map.values()
          |> Enum.find(&is_binary/1)

        {first_val && String.slice(first_val, 0..100), nil, nil}
    end
  end

  def extract_detail(_name, _input), do: {nil, nil, nil}

  # --- Event Grouping ---

  @doc """
  Groups flat session events into renderable groups:
  - `:step` — consecutive thinking + tool events (collapsible "Step N")
  - `:text` — agent text/assistant messages
  - `:result` — final result text
  - `:error` — error messages
  - `:system` — system/stderr messages

  When `agent_running?` is false, all `:running` tools are forced to `:done`.
  """
  @spec group_events([Event.t()], String.t() | nil, boolean()) :: [map()]
  def group_events(events, agent_kind, agent_running?) do
    {groups, current_step, _num} =
      Enum.reduce(events, {[], nil, 0}, fn event, {acc, step, num} ->
        case event.type do
          type when type in ~w(thinking reasoning) ->
            msg = event.message || ""

            if msg == "" do
              {acc, step, num}
            else
              {step, num} = ensure_step(step, num)
              {acc, %{step | thinking: step.thinking ++ [msg]}, num}
            end

          "tool_use" ->
            tool = build_tool_info(event, :running, agent_kind)
            {step, num} = ensure_step(step, num)

            tools =
              if tool.status == :done do
                update_or_append_tool(step.tools, tool)
              else
                step.tools ++ [tool]
              end

            {acc, %{step | tools: tools}, num}

          "tool_result" ->
            {step, num} = ensure_step(step, num)
            {acc, %{step | tools: do_mark_tool_done(step.tools, event, agent_kind)}, num}

          "step_finish" ->
            msg = event.message || ""

            if msg in ["tool-calls", ""] do
              {acc, step, num}
            else
              {acc, _} = close_step(acc, step)
              {[%{type: :result, text: msg} | acc], nil, num}
            end

          type when type in ~w(assistant text) ->
            msg = event.message || ""

            if msg == "" || noise_text?(msg) do
              {acc, step, num}
            else
              {acc, _} = close_step(acc, step)
              {[%{type: :text, text: msg, first_in_turn: !has_preceding_text?(acc)} | acc], nil, num}
            end

          "result" ->
            msg = event.message || ""

            if msg == "" || noise_result?(msg) do
              {acc, step, num}
            else
              {acc, _} = close_step(acc, step)
              {[%{type: :result, text: msg} | acc], nil, num}
            end

          "error" ->
            {acc, _} = close_step(acc, step)
            {[%{type: :error, text: event.message || "Unknown error"} | acc], nil, num}

          type when type in ~w(system stderr) ->
            msg = event.message || ""
            if msg != "", do: {[%{type: :system, text: msg} | acc], step, num}, else: {acc, step, num}

          _ ->
            {acc, step, num}
        end
      end)

    {groups, _} = close_step(groups, current_step)

    groups = Enum.reverse(groups)

    if agent_running? do
      groups
    else
      Enum.map(groups, fn
        %{type: :step, tools: tools} = step ->
          %{step | tools: Enum.map(tools, &force_tool_done/1)}

        other ->
          other
      end)
    end
  end

  defp ensure_step(nil, num), do: {%{type: :step, number: num + 1, thinking: [], tools: []}, num + 1}
  defp ensure_step(step, num), do: {step, num}

  defp close_step(acc, nil), do: {acc, nil}
  defp close_step(acc, step), do: {[step | acc], nil}

  defp force_tool_done(%{status: :running} = tool), do: %{tool | status: :done}
  defp force_tool_done(tool), do: tool

  defp update_or_append_tool(tools, done_tool) do
    idx = Enum.find_index(tools, &(&1.name == done_tool.name and &1.status == :running))

    if idx do
      List.replace_at(tools, idx, done_tool)
    else
      tools ++ [done_tool]
    end
  end

  defp do_mark_tool_done(tools, result_event, agent_kind) do
    case Enum.reverse(tools) do
      [last | rest] ->
        Enum.reverse([mark_done(last, result_event, agent_kind) | rest])

      [] ->
        [build_tool_info(result_event, :done, agent_kind)]
    end
  end

  defp has_preceding_text?(groups) do
    Enum.any?(groups, fn
      %{type: :text} -> true
      _ -> false
    end)
  end

  # Filter out prompt echoes and noise
  defp noise_text?(msg) do
    trimmed = String.trim(msg)
    # Agent echoes back the system prompt as first text event
    String.starts_with?(trimmed, "\"You are working on issue") ||
      String.starts_with?(trimmed, "You are working on issue")
  end

  defp noise_result?(msg) do
    String.trim(msg) in ~w(stop end-turn end_turn)
  end

  # --- Agent dispatch ---

  defp parser_for("claude"), do: Claude
  defp parser_for("opencode"), do: OpenCode
  defp parser_for(_), do: Claude
end
