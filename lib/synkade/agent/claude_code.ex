defmodule Synkade.Agent.ClaudeCode do
  @moduledoc false
  @behaviour Synkade.Agent.Behaviour

  alias Synkade.Agent.Event
  alias Synkade.Workflow.Config

  require Logger

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
  def stop_session(%{port: port, os_pid: os_pid}) when not is_nil(port) do
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

  def stop_session(_), do: :ok

  @doc "Build the CLI args list for claude command."
  def build_args(config, prompt, extra_args) do
    allowed_tools = Config.get(config, "agent", "allowed_tools") ||
      ["Read", "Edit", "Write", "Bash", "Glob", "Grep"]

    model = Config.get(config, "agent", "model")
    append_prompt = Config.get(config, "agent", "append_system_prompt")
    max_tokens = Config.get(config, "agent", "max_tokens")

    args = [
      "-p", prompt,
      "--output-format", "stream-json",
      "--verbose",
      "--allowedTools", Enum.join(allowed_tools, ",")
    ]

    args = if model, do: args ++ ["--model", model], else: args
    args = if append_prompt, do: args ++ ["--append-system-prompt", append_prompt], else: args
    args = if max_tokens, do: args ++ ["--max-tokens", to_string(max_tokens)], else: args
    args = args ++ extra_args
    args
  end

  @doc "Parse a line of JSON output from claude CLI."
  def parse_event(line) do
    case Jason.decode(line) do
      {:ok, data} ->
        {:ok, build_event(data)}

      {:error, _} ->
        :skip
    end
  end

  # --- Private ---

  defp run_agent(config, args, workspace_path) do
    command = Config.agent_command(config)
    turn_timeout = Config.get(config, "agent", "turn_timeout_ms") || 3_600_000

    port =
      Port.open({:spawn_executable, find_executable(command)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, args},
        {:cd, workspace_path},
        {:env, build_env(config)}
      ])

    session = %{
      session_id: nil,
      port: port,
      os_pid: port_os_pid(port),
      events: [],
      turn_timeout_ms: turn_timeout,
      started_at: System.monotonic_time(:millisecond)
    }

    {:ok, session}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp find_executable(command) do
    # Handle commands with arguments (e.g. "codex app-server")
    cmd = command |> String.split(" ") |> hd()

    case System.find_executable(cmd) do
      nil -> cmd
      path -> path
    end
  end

  @doc false
  def build_env(config) do
    case Config.get(config, "agent", "auth_mode") do
      "oauth" ->
        case Config.get(config, "agent", "oauth_token") do
          nil -> []
          "" -> []
          token -> [{~c"CLAUDE_OAUTH_TOKEN", String.to_charlist(token)}]
        end

      _ ->
        case Config.get(config, "agent", "api_key") do
          nil -> []
          "" -> []
          key -> [{~c"ANTHROPIC_API_KEY", String.to_charlist(key)}]
        end
    end
  end

  defp port_os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> pid
      nil -> nil
    end
  end

  defp build_event(data) do
    %Event{
      type: data["type"] || "unknown",
      session_id: extract_session_id(data),
      message: extract_message(data),
      input_tokens: get_in(data, ["usage", "input_tokens"]) || 0,
      output_tokens: get_in(data, ["usage", "output_tokens"]) || 0,
      total_tokens: (get_in(data, ["usage", "input_tokens"]) || 0) +
        (get_in(data, ["usage", "output_tokens"]) || 0),
      timestamp: DateTime.utc_now(),
      raw: data
    }
  end

  defp extract_session_id(data) do
    data["session_id"] || get_in(data, ["metadata", "session_id"])
  end

  defp extract_message(%{"type" => "assistant", "message" => msg}), do: msg
  defp extract_message(%{"type" => "result", "result" => result}), do: result
  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil
end
