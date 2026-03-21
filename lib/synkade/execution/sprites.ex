defmodule Synkade.Execution.Sprites do
  @moduledoc false
  @behaviour Synkade.Execution.Backend

  alias Synkade.Agent.Client, as: AgentClient
  alias Synkade.Workflow.Config

  require Logger

  @impl true
  def setup_env(config, project_name, issue_identifier) do
    client = build_client(config)
    sprite_name = sanitize_sprite_name("synkade-#{project_name}-#{issue_identifier}")

    # Try to get existing sprite, fall back to creating one
    sprite_handle = Sprites.sprite(client, sprite_name)

    case Sprites.get_sprite(client, sprite_name) do
      {:ok, _info} ->
        {:ok, %{sprite: sprite_handle, client: client, sprite_name: sprite_name}}

      {:error, _} ->
        case Sprites.create(client, sprite_name) do
          {:ok, sprite} ->
            # Run after_create hook inside the sprite if configured
            hooks = Config.get_section(config, "hooks")

            if hooks["after_create"] do
              timeout = hooks["timeout_ms"] || 60_000

              {_output, exit_code} =
                Sprites.cmd(sprite, "sh", ["-c", hooks["after_create"]], timeout: timeout)

              if exit_code == 0 do
                {:ok, %{sprite: sprite, client: client, sprite_name: sprite_name}}
              else
                Sprites.destroy(sprite)
                {:error, {:hook_failed, :after_create, "exited with code #{exit_code}"}}
              end
            else
              {:ok, %{sprite: sprite, client: client, sprite_name: sprite_name}}
            end

          {:error, reason} ->
            {:error, {:sprites_create_failed, reason}}
        end
    end
  end

  @impl true
  def run_before_hook(config, env_ref) do
    hooks = Config.get_section(config, "hooks")
    timeout = hooks["timeout_ms"] || 60_000

    case hooks["before_run"] do
      nil ->
        :ok

      script ->
        {_output, exit_code} =
          Sprites.cmd(env_ref.sprite, "sh", ["-c", script], timeout: timeout)

        if exit_code == 0 do
          :ok
        else
          {:error, {:hook_failed, :before_run, "exited with code #{exit_code}"}}
        end
    end
  end

  @impl true
  def start_agent(config, prompt, env_ref) do
    args = AgentClient.build_args(config, prompt, [])
    command = Config.agent_command(config)
    env_vars = build_env_list(config)

    case Sprites.spawn(env_ref.sprite, command, args, env: env_vars) do
      {:ok, cmd} ->
        session = %{
          session_id: nil,
          env_ref: env_ref,
          events: [],
          backend_data: %{command: cmd},
          agent_session: nil
        }

        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def continue_agent(config, session_id, prompt, env_ref) do
    args = AgentClient.build_args(config, prompt, ["--resume", session_id])
    command = Config.agent_command(config)
    env_vars = build_env_list(config)

    case Sprites.spawn(env_ref.sprite, command, args, env: env_vars) do
      {:ok, cmd} ->
        session = %{
          session_id: session_id,
          env_ref: env_ref,
          events: [],
          backend_data: %{command: cmd},
          agent_session: nil
        }

        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def await_event(session, timeout_ms) do
    cmd = session.backend_data.command

    receive do
      {:stdout, ^cmd, data} ->
        {:data, data}

      {:exit, ^cmd, code} ->
        {:exit, code}
    after
      timeout_ms ->
        :timeout
    end
  end

  @impl true
  def stop_agent(_session) do
    :ok
  end

  @impl true
  def run_after_hook(config, env_ref) do
    hooks = Config.get_section(config, "hooks")
    timeout = hooks["timeout_ms"] || 60_000

    case hooks["after_run"] do
      nil ->
        :ok

      script ->
        {_output, exit_code} =
          Sprites.cmd(env_ref.sprite, "sh", ["-c", script], timeout: timeout)

        if exit_code != 0 do
          Logger.warning("after_run hook failed with exit code #{exit_code}")
        end

        :ok
    end
  end

  @impl true
  def parse_event(config, line) do
    AgentClient.parse_event(config, line)
  end

  # --- Private ---

  @doc false
  def sanitize_sprite_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim_leading("-")
    |> String.trim_trailing("-")
    |> String.slice(0, 63)
  end

  defp build_client(config) do
    token = Config.get(config, "execution", "sprites_token")
    Sprites.new(token)
  end

  @doc false
  def build_env_list(config) do
    AgentClient.build_env(config)
    |> Enum.map(fn {key, value} ->
      {to_string(key), to_string(value)}
    end)
  end
end
