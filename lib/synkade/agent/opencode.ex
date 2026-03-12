defmodule Synkade.Agent.OpenCode do
  @moduledoc false
  @behaviour Synkade.Agent.Behaviour

  alias Synkade.Agent.Event
  alias Synkade.Workflow.Config

  require Logger

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

  @impl true
  def build_args(config, prompt, extra_args) do
    model = Config.get(config, "agent", "model")

    args = ["run", "--format", "json"]

    args = if model, do: args ++ ["--model", model], else: args
    args = args ++ extra_args ++ [prompt]
    args
  end

  @impl true
  def build_env(config) do
    env =
      case Config.get(config, "agent", "api_key") do
        nil -> []
        "" -> []
        key -> [{~c"OPENROUTER_API_KEY", String.to_charlist(key)}]
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
        {:ok, build_event(data)}

      {:error, _} ->
        :skip
    end
  end

  # --- Private ---

  defp run_agent(config, args, workspace_path) do
    env = build_env(config)

    command = Config.agent_command(config)
    turn_timeout = Config.get(config, "agent", "turn_timeout_ms") || 3_600_000

    # Build the bash command string with single-quote escaping for each arg.
    # Then launch via spawn_executable on `script` so each OS-level argument
    # is passed directly — no nested shell interpretation.
    bash_command =
      Enum.map_join([command | args], " ", &shell_escape/1)

    script_path = System.find_executable("script") || "/usr/bin/script"

    Logger.info("OpenCode: starting agent in #{workspace_path}, script=#{script_path}")

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(script_path)},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:args, [~c"-q", ~c"/dev/null", ~c"bash", ~c"-lc", String.to_charlist(bash_command)]},
          {:cd, String.to_charlist(workspace_path)},
          {:env, env},
          {:line, @port_line_bytes}
        ]
      )

    session = %{
      session_id: nil,
      port: port,
      os_pid: port_os_pid(port),
      events: [],
      turn_timeout_ms: turn_timeout,
      started_at: System.monotonic_time(:millisecond)
    }

    Logger.info("OpenCode: port opened, os_pid=#{inspect(port_os_pid(port))}")

    {:ok, session}
  rescue
    e ->
      Logger.error("OpenCode: failed to start agent: #{Exception.message(e)}")
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

  defp build_event(data) do
    %Event{
      type: data["type"] || "unknown",
      session_id: data["session_id"],
      message: extract_message(data),
      input_tokens: get_in(data, ["usage", "input_tokens"]) || 0,
      output_tokens: get_in(data, ["usage", "output_tokens"]) || 0,
      total_tokens:
        (get_in(data, ["usage", "input_tokens"]) || 0) +
          (get_in(data, ["usage", "output_tokens"]) || 0),
      timestamp: DateTime.utc_now(),
      raw: data
    }
  end

  defp extract_message(%{"type" => "assistant", "message" => msg}), do: msg
  defp extract_message(%{"type" => "result", "result" => result}), do: result
  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil
end
