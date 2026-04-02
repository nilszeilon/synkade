defmodule Synkade.Agent.PortHelper do
  @moduledoc false

  alias Synkade.Workflow.Config

  @port_line_bytes 1_048_576

  @doc "Single-quote shell escape."
  def shell_escape(arg) do
    "'" <> String.replace(arg, "'", "'\\''") <> "'"
  end

  @doc "Get OS PID from an Erlang port."
  def port_os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> pid
      nil -> nil
    end
  end

  @doc "Resolve GitHub token from config or env."
  def resolve_github_token(config) do
    case Config.get(config, "tracker", "api_key") do
      nil -> non_empty_env("GITHUB_TOKEN")
      "" -> non_empty_env("GITHUB_TOKEN")
      token -> token
    end
  end

  @doc """
  Build the common env vars shared by all adapters:
  GITHUB_TOKEN, SYNKADE_API_URL, SYNKADE_API_TOKEN.

  Takes an initial env list (adapter-specific vars like API keys)
  and appends the shared vars.
  """
  def common_env(config, agent_env) do
    agent_env
    |> maybe_prepend(~c"GITHUB_TOKEN", resolve_github_token(config))
    |> maybe_prepend(~c"SYNKADE_API_URL", Config.get(config, "agent", "synkade_api_url"))
    |> maybe_prepend(~c"SYNKADE_API_TOKEN", Config.get(config, "agent", "synkade_api_token"))
  end

  @doc """
  Open a bash port with exec + </dev/null (no PTY).
  Used by OpenCode, Hermes, and OpenClaw.
  """
  def open_bash_port(config, args, workspace_path, env) do
    command = Config.agent_command(config)

    bash_command =
      "exec " <> Enum.map_join([command | args], " ", &shell_escape/1) <> " </dev/null"

    bash_path = System.find_executable("bash") || "/bin/bash"

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

    {:ok, %{session_id: nil, port: port, os_pid: port_os_pid(port), events: []}}
  end

  defp maybe_prepend(env, _key, nil), do: env
  defp maybe_prepend(env, _key, ""), do: env
  defp maybe_prepend(env, key, value), do: [{key, String.to_charlist(value)} | env]

  defp non_empty_env(var) do
    case System.get_env(var) do
      nil -> nil
      "" -> nil
      val -> val
    end
  end
end
