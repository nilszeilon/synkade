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
          workspace_key: key
        }

        if created_now do
          with :ok <- maybe_clone_repo(config, path),
               :ok <- run_after_create_hook(config, path) do
            {:ok, workspace}
          else
            {:error, reason} ->
              File.rm_rf!(path)
              {:error, reason}
          end
        else
          {:ok, workspace}
        end
      end
    end
  end

  defp maybe_clone_repo(config, path) do
    repo = Config.get(config, "tracker", "repo")

    if repo && repo != "" do
      api_key = Config.get(config, "tracker", "api_key")
      clone_repo(repo, api_key, path)
    else
      :ok
    end
  end

  defp clone_repo(repo, api_key, path) do
    url =
      if api_key && api_key != "" do
        "https://#{api_key}@github.com/#{repo}.git"
      else
        "https://github.com/#{repo}.git"
      end

    Logger.info("Cloning #{repo} into #{path}")

    case System.cmd("git", ["clone", url, "."], cd: path, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        Logger.error("git clone failed (exit #{exit_code}): #{output}")
        {:error, {:clone_failed, output}}
    end
  end

  defp run_after_create_hook(config, path) do
    hooks_config = Config.get_section(config, "hooks")
    hook_script = hooks_config["after_create"]
    timeout = hooks_config["timeout_ms"] || 60_000

    case Hooks.run_hook(hook_script, path, timeout_ms: timeout) do
      :ok -> :ok
      {:error, reason} -> {:error, {:hook_failed, :after_create, reason}}
    end
  end

end
