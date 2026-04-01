defmodule Synkade.Agent.OpenClaw do
  @moduledoc false
  @behaviour Synkade.Agent.Behaviour

  alias Synkade.Agent.Event
  alias Synkade.Workflow.Config

  require Logger

  @impl true
  def fetch_models(_api_key) do
    # OpenClaw routes to multiple LLM providers. Model selection is done
    # via `openclaw configure` or per-session with `/model`.
    {:ok,
     [
       {"Anthropic Claude Sonnet", "anthropic/claude-sonnet-4-20250514"},
       {"Anthropic Claude Haiku", "anthropic/claude-haiku-4-5-20251001"},
       {"OpenAI GPT-4o", "openai/gpt-4o"},
       {"Google Gemini 2.5 Pro", "google/gemini-2.5-pro"}
     ]}
  end

  @port_line_bytes 1_048_576

  @impl true
  def start_session(config, prompt, workspace_path) do
    args = build_args(config, prompt, [])
    run_agent(config, args, workspace_path)
  end

  @impl true
  def continue_session(config, _session_id, prompt, workspace_path) do
    args = build_args(config, prompt, ["--continue"])
    run_agent(config, args, workspace_path)
  end

  @impl true
  defdelegate stop_session(session), to: Synkade.Agent.Client, as: :stop_port_session

  @impl true
  def build_args(config, prompt, extra_args) do
    model = Config.get(config, "agent", "model")

    args = ["agent", "--message", prompt, "--format", "json", "--local"]

    args = if model, do: args ++ ["--model", model], else: args
    args = args ++ extra_args
    args
  end

  @impl true
  def build_env(config) do
    env =
      case Config.get(config, "agent", "api_key") do
        nil -> []
        "" -> []
        key -> [{~c"ANTHROPIC_API_KEY", String.to_charlist(key)}]
      end

    env =
      case resolve_github_token(config) do
        nil -> env
        token -> [{~c"GITHUB_TOKEN", String.to_charlist(token)} | env]
      end

    env =
      case Config.get(config, "agent", "synkade_api_url") do
        nil -> env
        "" -> env
        url -> [{~c"SYNKADE_API_URL", String.to_charlist(url)} | env]
      end

    case Config.get(config, "agent", "synkade_api_token") do
      nil -> env
      "" -> env
      token -> [{~c"SYNKADE_API_TOKEN", String.to_charlist(token)} | env]
    end
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

  # --- Private ---

  defp run_agent(config, args, workspace_path) do
    env = build_env(config)
    command = Config.agent_command(config)

    bash_command =
      "exec " <> Enum.map_join([command | args], " ", &shell_escape/1) <> " </dev/null"

    bash_path = System.find_executable("bash") || "/bin/bash"

    Logger.info("OpenClaw: starting agent in #{workspace_path}")

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(bash_path)},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:args, [~c"-lc", String.to_charlist(bash_command)]},
          {:cd, String.to_charlist(workspace_path)},
          {:env, env},
          {:line, @port_line_bytes}
        ]
      )

    session = %{
      session_id: nil,
      port: port,
      os_pid: port_os_pid(port),
      events: []
    }

    {:ok, session}
  rescue
    e ->
      Logger.error("OpenClaw: failed to start agent: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp shell_escape(arg) do
    "'" <> String.replace(arg, "'", "'\\''") <> "'"
  end

  defp resolve_github_token(config) do
    case Config.get(config, "tracker", "api_key") do
      nil ->
        case System.get_env("GITHUB_TOKEN") do
          nil -> nil
          "" -> nil
          token -> token
        end

      token ->
        token
    end
  end

  defp port_os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> pid
      nil -> nil
    end
  end

  defp extract_session_id(data) do
    data["session_id"]
  end

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

  defp extract_message(%{"type" => "assistant", "message" => msg}) when is_binary(msg), do: msg
  defp extract_message(%{"type" => "text", "part" => %{"text" => text}}), do: text
  defp extract_message(%{"type" => "result", "result" => result}), do: result
  defp extract_message(%{"type" => "error", "error" => %{"message" => msg}}), do: msg
  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil
end
