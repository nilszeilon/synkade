defmodule Synkade.Execution.Sprites do
  @moduledoc false
  @behaviour Synkade.Execution.Backend

  alias Synkade.Agent.Client, as: AgentClient
  alias Synkade.Workflow.Config

  require Logger

  @impl true
  def setup_env(config, project_name, issue_identifier) do
    client = build_client(config)
    user_id = config["user_id"]
    sprite_name = sanitize_sprite_name("synkade-u#{user_id}")

    # Try to get existing sprite, fall back to creating one
    sprite_handle = Sprites.sprite(client, sprite_name)

    case get_or_create_sprite(client, sprite_name, sprite_handle, config) do
      {:ok, sprite} ->
        case setup_worktree(sprite, config, project_name, issue_identifier) do
          :ok ->
            worktree_path = build_worktree_path(project_name, issue_identifier)

            {:ok,
             %{
               sprite: sprite,
               client: client,
               sprite_name: sprite_name,
               worktree_path: worktree_path
             }}

          {:error, reason} ->
            {:error, {:worktree_setup_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
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
          Sprites.cmd(env_ref.sprite, "sh", ["-c", script],
            timeout: timeout,
            dir: env_ref.worktree_path
          )

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

    case Sprites.spawn(env_ref.sprite, command, args,
           env: env_vars,
           dir: env_ref.worktree_path
         ) do
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

    case Sprites.spawn(env_ref.sprite, command, args,
           env: env_vars,
           dir: env_ref.worktree_path
         ) do
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
          Sprites.cmd(env_ref.sprite, "sh", ["-c", script],
            timeout: timeout,
            dir: env_ref.worktree_path
          )

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

  @doc """
  Removes the git worktree for a completed issue, reclaiming disk space.
  """
  def cleanup_worktree(env_ref, project_name, issue_identifier) do
    bare_path = build_bare_repo_path(project_name)
    worktree_path = build_worktree_path(project_name, issue_identifier)

    {_output, exit_code} =
      Sprites.cmd(
        env_ref.sprite,
        "git",
        ["-C", bare_path, "worktree", "remove", worktree_path, "--force"],
        timeout: 30_000
      )

    if exit_code == 0 do
      :ok
    else
      Logger.warning("Failed to remove worktree #{worktree_path}, exit code #{exit_code}")
      {:error, {:worktree_remove_failed, exit_code}}
    end
  end

  # --- Private ---

  defp get_or_create_sprite(client, sprite_name, sprite_handle, config) do
    case Sprites.get_sprite(client, sprite_name) do
      {:ok, _info} ->
        {:ok, sprite_handle}

      {:error, _} ->
        case Sprites.create(client, sprite_name) do
          {:ok, sprite} ->
            # Run after_create hook inside the sprite if configured
            # This runs once per user sprite (tool installs, SSH keys, etc.)
            hooks = Config.get_section(config, "hooks")

            if hooks["after_create"] do
              timeout = hooks["timeout_ms"] || 60_000

              {_output, exit_code} =
                Sprites.cmd(sprite, "sh", ["-c", hooks["after_create"]], timeout: timeout)

              if exit_code == 0 do
                {:ok, sprite}
              else
                Sprites.destroy(sprite)
                {:error, {:hook_failed, :after_create, "exited with code #{exit_code}"}}
              end
            else
              {:ok, sprite}
            end

          {:error, reason} ->
            {:error, {:sprites_create_failed, reason}}
        end
    end
  end

  defp setup_worktree(sprite, config, project_name, issue_identifier) do
    repo_url = build_repo_url(config)
    bare_path = build_bare_repo_path(project_name)
    worktree_path = build_worktree_path(project_name, issue_identifier)

    # 1. Ensure bare clone exists
    {_output, clone_exit} =
      Sprites.cmd(
        sprite,
        "sh",
        ["-c", "test -d #{bare_path} || git clone --bare #{repo_url} #{bare_path}"],
        timeout: 120_000
      )

    if clone_exit != 0 do
      {:error, "bare clone failed with exit code #{clone_exit}"}
    else
      # 2. Fetch latest (idempotent)
      {_output, fetch_exit} =
        Sprites.cmd(
          sprite,
          "git",
          ["-C", bare_path, "fetch", "origin"],
          timeout: 60_000
        )

      if fetch_exit != 0 do
        {:error, "git fetch failed with exit code #{fetch_exit}"}
      else
        # 3. Create worktree if it doesn't exist
        {_output, wt_exit} =
          Sprites.cmd(
            sprite,
            "sh",
            [
              "-c",
              "test -d #{worktree_path} || git -C #{bare_path} worktree add #{worktree_path} origin/HEAD"
            ],
            timeout: 60_000
          )

        if wt_exit != 0 do
          {:error, "worktree add failed with exit code #{wt_exit}"}
        else
          :ok
        end
      end
    end
  end

  defp build_repo_url(config) do
    tracker = Config.get_section(config, "tracker")
    repo = tracker["repo"]
    api_key = tracker["api_key"]

    if api_key do
      "https://x-access-token:#{api_key}@github.com/#{repo}.git"
    else
      "https://github.com/#{repo}.git"
    end
  end

  @doc false
  def build_bare_repo_path(project_name) do
    sanitized = sanitize_path_segment(project_name)
    "/repos/#{sanitized}.git"
  end

  @doc false
  def build_worktree_path(project_name, issue_identifier) do
    sanitized_project = sanitize_path_segment(project_name)
    sanitized_issue = sanitize_path_segment(issue_identifier)
    "/workspaces/#{sanitized_project}/#{sanitized_issue}"
  end

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

  @doc false
  def sanitize_path_segment(segment) do
    segment
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._\-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim_leading("-")
    |> String.trim_trailing("-")
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
