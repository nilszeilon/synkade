defmodule Synkade.Agent.ClaudeCode do
  @moduledoc false
  @behaviour Synkade.Agent.Behaviour

  alias Synkade.Agent.{Event, PortHelper}
  alias Synkade.Workflow.Config

  require Logger

  @impl true
  def fetch_models(api_key) do
    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]

    case Req.get("https://api.anthropic.com/v1/models",
           headers: headers,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        items =
          models
          |> Enum.filter(&String.starts_with?(&1["id"], "claude-"))
          |> Enum.sort_by(& &1["created_at"], :desc)
          |> Enum.map(fn m -> {humanize_model_id(m["id"]), m["id"]} end)

        {:ok, items}

      {:ok, %{status: status}} ->
        {:error, "Anthropic API returned #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp humanize_model_id(id) do
    id
    |> String.replace("claude-", "Claude ")
    |> String.replace("-", " ")
    |> String.replace(~r/\d{8}$/, "")
    |> String.trim()
  end

  @impl true
  def start_session(config, prompt, workspace_path) do
    args = build_args(config, prompt, [])
    run_agent(config, args, workspace_path)
  end

  @impl true
  def continue_session(config, session_id, prompt, workspace_path) do
    args = build_args(config, prompt, ["--resume", session_id])
    run_agent(config, args, workspace_path)
  end

  @impl true
  defdelegate stop_session(session), to: Synkade.Agent.Client, as: :stop_port_session

  @impl true
  def build_args(config, prompt, extra_args) do
    model = Config.get(config, "agent", "model")
    max_tokens = Config.get(config, "agent", "max_tokens")

    args = [
      "-p",
      prompt,
      "--output-format",
      "stream-json",
      "--verbose"
    ]

    args = if model, do: args ++ ["--model", model], else: args
    args = if max_tokens, do: args ++ ["--max-tokens", to_string(max_tokens)], else: args
    args = args ++ extra_args
    args
  end

  @impl true
  def parse_event(line) do
    case Jason.decode(line) do
      {:ok, data} ->
        case Synkade.Agent.ContentExpander.expand(data, &extract_session_id/1) do
          [] -> {:ok, build_event(data)}
          events -> {:ok, events}
        end

      {:error, _} ->
        :skip
    end
  end

  @port_line_bytes 1_048_576

  # --- Private ---

  # ClaudeCode uses `script` for PTY wrapping (unlike the other adapters)
  defp run_agent(config, args, workspace_path) do
    command = Config.agent_command(config)

    bash_command =
      Enum.map_join([command | args], " ", &PortHelper.shell_escape/1)

    script_path = System.find_executable("script") || "/usr/bin/script"

    Logger.info("ClaudeCode: starting agent in #{workspace_path}, script=#{script_path}")

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(script_path)},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:args, [~c"-q", ~c"/dev/null", ~c"bash", ~c"-lc", String.to_charlist(bash_command)]},
          {:cd, String.to_charlist(workspace_path)},
          {:env, build_env(config)},
          {:line, @port_line_bytes}
        ]
      )

    session = %{
      session_id: nil,
      port: port,
      os_pid: PortHelper.port_os_pid(port),
      events: []
    }

    {:ok, session}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def build_env(config) do
    agent_env =
      case Config.get(config, "agent", "auth_mode") do
        "oauth" ->
          charlist_env(~c"CLAUDE_CODE_OAUTH_TOKEN", Config.get(config, "agent", "oauth_token"))

        _ ->
          charlist_env(~c"ANTHROPIC_API_KEY", Config.get(config, "agent", "api_key"))
      end

    PortHelper.common_env(config, agent_env)
  end

  defp charlist_env(_key, nil), do: []
  defp charlist_env(_key, ""), do: []
  defp charlist_env(key, value), do: [{key, String.to_charlist(value)}]

  defp build_event(data) do
    %Event{
      type: data["type"] || "unknown",
      session_id: extract_session_id(data),
      message: extract_message(data),
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

  defp extract_session_id(data) do
    data["session_id"] || get_in(data, ["metadata", "session_id"])
  end

  defp extract_message(%{"type" => "assistant", "message" => msg}) when is_binary(msg), do: msg
  defp extract_message(%{"type" => "result", "result" => result}), do: result
  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil
end
