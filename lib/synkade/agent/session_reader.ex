defmodule Synkade.Agent.SessionReader do
  @moduledoc """
  Reads completed agent session data from the agent's own storage.

  Claude Code: JSONL files at ~/.claude/projects/{encoded-path}/{session_id}.jsonl
  OpenCode: SQLite DB at ~/.local/share/opencode/opencode.db
  """

  alias Synkade.Agent.Event

  require Logger

  @doc """
  Load events from the agent's session storage.

  Returns a list of Agent.Event structs, or [] if loading fails.
  """
  @spec load(String.t(), String.t(), String.t() | nil) :: [Event.t()]
  def load(agent_kind, session_id, workspace_path \\ nil)

  def load("claude", session_id, workspace_path) when is_binary(session_id) do
    load_claude_session(session_id, workspace_path)
  end

  def load("hermes", session_id, workspace_path) when is_binary(session_id) do
    # Hermes is a Claude Code fork — same JSONL session format
    load_claude_session(session_id, workspace_path)
  end

  def load("opencode", session_id, _workspace_path) when is_binary(session_id) do
    load_opencode_session(session_id)
  end

  def load("openclaw", session_id, _workspace_path) when is_binary(session_id) do
    # OpenClaw uses the OpenCode session format (SQLite)
    load_opencode_session(session_id)
  end

  def load(_agent_kind, _session_id, _workspace_path), do: []

  # --- Claude Code ---

  defp load_claude_session(session_id, workspace_path) do
    path = claude_session_path(session_id, workspace_path)

    if path && File.exists?(path) do
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.flat_map(&parse_claude_line/1)
      |> Enum.take(500)
    else
      []
    end
  rescue
    e ->
      Logger.warning("SessionReader: failed to read Claude session #{session_id}: #{inspect(e)}")
      []
  end

  defp claude_session_path(session_id, workspace_path) do
    # Claude Code stores sessions in ~/.claude/projects/{encoded-path}/{session_id}.jsonl
    # The encoded path replaces / with -
    claude_home = Path.expand("~/.claude/projects")
    filename = "#{session_id}.jsonl"

    # Try workspace_path-based lookup first (with symlink resolution),
    # then fall back to scanning all project directories.
    path_from_workspace =
      if workspace_path do
        # macOS: /var/folders/... is a symlink to /private/var/folders/...
        # Claude Code resolves symlinks, so we must too.
        resolved = resolve_real_path(workspace_path)
        # Claude Code replaces all non-alphanumeric chars (except -) with -
        encoded = String.replace(resolved, ~r/[^a-zA-Z0-9\-]/, "-")
        candidate = Path.join([claude_home, encoded, filename])
        if File.exists?(candidate), do: candidate
      end

    path_from_workspace || find_claude_session_file(claude_home, session_id)
  end

  # macOS: /var → /private/var, /tmp → /private/tmp
  # Claude Code resolves symlinks so we need the real path.
  defp resolve_real_path(path) do
    case System.cmd("realpath", [path], stderr_to_stdout: true) do
      {resolved, 0} -> String.trim(resolved)
      _ -> path
    end
  rescue
    _ -> path
  end

  defp find_claude_session_file(claude_home, session_id) do
    filename = "#{session_id}.jsonl"

    case File.ls(claude_home) do
      {:ok, dirs} ->
        Enum.find_value(dirs, fn dir ->
          full = Path.join([claude_home, dir, filename])
          if File.exists?(full), do: full
        end)

      _ ->
        nil
    end
  end

  defp parse_claude_line(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "assistant", "message" => %{"content" => content}} = data}
      when is_list(content) ->
        timestamp = parse_timestamp(data["timestamp"])
        session_id = data["sessionId"]

        Enum.flat_map(content, fn
          %{"type" => "tool_use", "name" => name, "input" => input} = tool ->
            [
              %Event{
                type: "tool_use",
                session_id: session_id,
                message: nil,
                timestamp: timestamp,
                raw: %{
                  "type" => "tool_use",
                  "tool" => %{"name" => name, "input" => input || %{}},
                  "input" => input || %{},
                  "tool_use_id" => tool["id"]
                }
              }
            ]

          %{"type" => "text", "text" => text} ->
            [
              %Event{
                type: "text",
                session_id: session_id,
                message: text,
                timestamp: timestamp,
                raw: %{"type" => "text", "text" => text}
              }
            ]

          %{"type" => "thinking", "thinking" => text} ->
            [
              %Event{
                type: "thinking",
                session_id: session_id,
                message: text,
                timestamp: timestamp,
                raw: %{"type" => "thinking", "text" => text}
              }
            ]

          _ ->
            []
        end)

      {:ok, %{"type" => "user", "message" => %{"content" => content}} = data}
      when is_list(content) ->
        timestamp = parse_timestamp(data["timestamp"])
        session_id = data["sessionId"]

        Enum.flat_map(content, fn
          %{"type" => "tool_result", "tool_use_id" => tool_id, "content" => result_content} ->
            output = extract_tool_result_text(result_content)

            [
              %Event{
                type: "tool_result",
                session_id: session_id,
                message: output,
                timestamp: timestamp,
                raw: %{
                  "type" => "tool_result",
                  "tool_use_id" => tool_id,
                  "output" => output
                }
              }
            ]

          _ ->
            []
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp extract_tool_result_text(content) when is_binary(content), do: content

  defp extract_tool_result_text(content) when is_list(content) do
    content
    |> Enum.filter(&(is_map(&1) && &1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end

  defp extract_tool_result_text(_), do: nil

  # --- OpenCode ---

  defp load_opencode_session(session_id) do
    db_path = Path.expand("~/.local/share/opencode/opencode.db")

    if File.exists?(db_path) do
      query_opencode_parts(db_path, session_id)
    else
      []
    end
  end

  defp query_opencode_parts(db_path, session_id) do
    # Use sqlite3 CLI to query - avoids needing an Elixir SQLite dependency
    sanitized = sanitize_sql(session_id)
    query =
      "SELECT data, time_created FROM part WHERE session_id = '#{sanitized}' ORDER BY time_created LIMIT 500"

    case System.cmd("sqlite3", ["-json", db_path, query], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, rows} when is_list(rows) ->
            Enum.flat_map(rows, &parse_opencode_row/1)

          _ ->
            []
        end

      _ ->
        []
    end
  rescue
    e ->
      Logger.warning("SessionReader: failed to read OpenCode session #{session_id}: #{inspect(e)}")
      []
  end

  defp parse_opencode_row(%{"data" => data_str, "time_created" => ts}) do
    case Jason.decode(data_str) do
      {:ok, data} ->
        event = build_opencode_event(data, ts)
        if event, do: [event], else: []

      _ ->
        []
    end
  end

  defp parse_opencode_row(_), do: []

  defp build_opencode_event(%{"type" => "tool"} = data, ts) do
    part = data["part"] || data
    state = (part["state"] || data["state"]) || %{}
    tokens = data["tokens"] || %{}

    %Event{
      type: "tool_use",
      session_id: nil,
      message: state["title"],
      input_tokens: tokens["input"] || 0,
      output_tokens: tokens["output"] || 0,
      total_tokens: tokens["total"] || 0,
      timestamp: timestamp_from_unix_ms(ts),
      raw: data
    }
  end

  defp build_opencode_event(%{"type" => "text", "text" => text}, ts) do
    %Event{
      type: "text",
      message: text,
      timestamp: timestamp_from_unix_ms(ts),
      raw: %{"type" => "text", "text" => text}
    }
  end

  defp build_opencode_event(%{"type" => "reasoning", "text" => text}, ts) when is_binary(text) do
    %Event{
      type: "thinking",
      message: text,
      timestamp: timestamp_from_unix_ms(ts),
      raw: %{"type" => "thinking", "text" => text}
    }
  end

  defp build_opencode_event(%{"type" => "step-finish"} = data, ts) do
    tokens = data["tokens"] || %{}

    %Event{
      type: "step_finish",
      message: data["reason"],
      input_tokens: tokens["input"] || 0,
      output_tokens: tokens["output"] || 0,
      total_tokens: tokens["total"] || 0,
      timestamp: timestamp_from_unix_ms(ts),
      raw: data
    }
  end

  defp build_opencode_event(%{"type" => "step-start"}, _ts), do: nil
  defp build_opencode_event(%{"type" => "compaction"}, _ts), do: nil
  defp build_opencode_event(%{"type" => "patch"}, _ts), do: nil
  defp build_opencode_event(_, _), do: nil

  # --- Helpers ---

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(iso_str) when is_binary(iso_str) do
    case DateTime.from_iso8601(iso_str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp timestamp_from_unix_ms(nil), do: DateTime.utc_now()

  defp timestamp_from_unix_ms(ms) when is_integer(ms) do
    DateTime.from_unix!(ms, :millisecond)
  rescue
    _ -> DateTime.utc_now()
  end

  defp timestamp_from_unix_ms(_), do: DateTime.utc_now()

  # Prevent SQL injection - only allow alphanumeric, dashes, underscores
  defp sanitize_sql(str) when is_binary(str) do
    String.replace(str, ~r/[^a-zA-Z0-9_\-]/, "")
  end
end
