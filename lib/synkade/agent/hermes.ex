defmodule Synkade.Agent.Hermes do
  @moduledoc false
  @behaviour Synkade.Agent.Behaviour

  alias Synkade.Agent.{Event, PortHelper}
  alias Synkade.Workflow.Config

  require Logger

  @impl true
  def fetch_models(_api_key) do
    case Req.get("https://openrouter.ai/api/v1/models", receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        items =
          models
          |> Enum.filter(&("tools" in (&1["supported_parameters"] || [])))
          |> Enum.sort_by(& &1["name"])
          |> Enum.map(fn m -> {m["name"] || m["id"], m["id"]} end)

        {:ok, items}

      {:ok, %{status: status}} ->
        {:error, "OpenRouter returned #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def start_session(config, prompt, workspace_path) do
    args = build_args(config, prompt, [])
    run_agent(config, args, workspace_path)
  end

  @impl true
  def continue_session(config, nil, prompt, workspace_path) do
    start_session(config, prompt, workspace_path)
  end

  def continue_session(config, session_id, prompt, workspace_path) do
    args = build_args(config, prompt, ["--resume", session_id])
    run_agent(config, args, workspace_path)
  end

  @impl true
  defdelegate stop_session(session), to: Synkade.Agent.Client, as: :stop_port_session

  @impl true
  def build_args(config, prompt, extra_args) do
    model = Config.get(config, "agent", "model")

    args = ["chat", "-q", prompt, "--quiet"]

    args = if model, do: args ++ ["--model", model], else: args
    args = args ++ extra_args
    args
  end

  @impl true
  def build_env(config) do
    agent_env =
      case Config.get(config, "agent", "api_key") do
        nil -> []
        "" -> []
        key -> [{~c"OPENROUTER_API_KEY", String.to_charlist(key)}]
      end

    PortHelper.common_env(config, agent_env)
  end

  # Hermes outputs decorated terminal text, not JSON.
  # We parse the text lines into structured events.

  # Box drawing lines (banner open/close) — skip these
  @box_open_pattern ~r/^╭─.*╮$/
  @box_close_pattern ~r/^╰.*╯$/

  # Tool progress: "  ┊ 🔎 preparing search_files…" or "  ┊ 💻 $  ls -la  2.8s"
  @tool_pattern ~r/^\s*┊\s+(.+)/

  # Session ID line: "session_id: 20260402_212839_2c5034"
  @session_id_pattern ~r/^session_id:\s+(\S+)/

  @impl true
  def parse_event(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        :skip

      Regex.match?(@box_open_pattern, trimmed) ->
        :skip

      Regex.match?(@box_close_pattern, trimmed) ->
        :skip

      match = Regex.run(@session_id_pattern, trimmed) ->
        [_, session_id] = match
        {:ok, %Event{type: "system", session_id: session_id, message: nil, timestamp: DateTime.utc_now()}}

      match = Regex.run(@tool_pattern, trimmed) ->
        [_, tool_info] = match

        if String.contains?(tool_info, "preparing") do
          {:ok, %Event{type: "tool_use", message: tool_info, timestamp: DateTime.utc_now()}}
        else
          {:ok, %Event{type: "tool_result", message: tool_info, timestamp: DateTime.utc_now()}}
        end

      true ->
        # Try JSON first (in case hermes ever outputs structured data)
        case Jason.decode(line) do
          {:ok, data} ->
            {:ok, build_json_event(data)}

          {:error, _} ->
            # Regular text content — treat as assistant message
            {:ok, %Event{type: "assistant", message: trimmed, timestamp: DateTime.utc_now()}}
        end
    end
  end

  # --- Private ---

  defp run_agent(config, args, workspace_path) do
    env = build_env(config)
    Logger.info("Hermes: starting agent in #{workspace_path}")
    PortHelper.open_bash_port(config, args, workspace_path, env)
  rescue
    e ->
      Logger.error("Hermes: failed to start agent: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp build_json_event(data) do
    %Event{
      type: data["type"] || "unknown",
      session_id: data["session_id"] || get_in(data, ["metadata", "session_id"]),
      message: data["message"] || data["result"],
      model: data["model"] || get_in(data, ["usage", "model"]),
      input_tokens: get_in(data, ["usage", "input_tokens"]) || 0,
      output_tokens: get_in(data, ["usage", "output_tokens"]) || 0,
      total_tokens:
        (get_in(data, ["usage", "input_tokens"]) || 0) +
          (get_in(data, ["usage", "output_tokens"]) || 0),
      timestamp: DateTime.utc_now(),
      raw: data
    }
  end
end
