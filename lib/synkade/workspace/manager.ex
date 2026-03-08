defmodule Synkade.Workspace.Manager do
  @moduledoc false

  require Logger

  alias Synkade.Workspace
  alias Synkade.Workspace.{Hooks, Safety}
  alias Synkade.Workflow.Config

  @spec ensure_workspace(map(), String.t(), String.t()) ::
          {:ok, Workspace.t()} | {:error, term()}
  def ensure_workspace(config, project_name, issue_identifier) do
    root = Config.workspace_root(config)
    key = Safety.sanitize_key("#{project_name}/#{issue_identifier}")

    with :ok <- Safety.validate_key(key) do
      path = Path.join(root, key)

      with :ok <- Safety.validate_path_containment(path, root) do
        created_now = not File.dir?(path)

        if created_now do
          File.mkdir_p!(path)
        end

        workspace = %Workspace{
          project_name: project_name,
          path: path,
          workspace_key: key,
          created_now: created_now
        }

        if created_now do
          hooks_config = Config.get_section(config, "hooks")
          hook_script = hooks_config["after_create"]
          timeout = hooks_config["timeout_ms"] || 60_000

          case Hooks.run_hook(hook_script, path, timeout_ms: timeout) do
            :ok ->
              {:ok, workspace}

            {:error, reason} ->
              # Abort workspace creation on hook failure
              File.rm_rf!(path)
              {:error, {:hook_failed, :after_create, reason}}
          end
        else
          {:ok, workspace}
        end
      end
    end
  end

  @spec cleanup_workspace(map(), Workspace.t()) :: :ok
  def cleanup_workspace(config, workspace) do
    hooks_config = Config.get_section(config, "hooks")
    hook_script = hooks_config["before_remove"]
    timeout = hooks_config["timeout_ms"] || 60_000

    if File.dir?(workspace.path) do
      case Hooks.run_hook(hook_script, workspace.path, timeout_ms: timeout) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("before_remove hook failed: #{reason}")
      end

      File.rm_rf!(workspace.path)
    end

    :ok
  end
end
