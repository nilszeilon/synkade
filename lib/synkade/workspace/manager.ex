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
      worktree_path = Path.join(root, key)

      with :ok <- Safety.validate_path_containment(worktree_path, root) do
        workspace = %Workspace{
          project_name: project_name,
          path: worktree_path,
          workspace_key: key
        }

        if File.dir?(worktree_path) do
          # Worktree already exists
          {:ok, workspace}
        else
          repo = Config.get(config, "tracker", "repo")

          if repo && repo != "" do
            # Use worktree-based isolation
            with :ok <- ensure_main_repo(config, root, project_name),
                 :ok <- create_worktree(root, project_name, issue_identifier, worktree_path),
                 :ok <- run_after_create_hook(config, worktree_path) do
              {:ok, workspace}
            else
              {:error, reason} ->
                File.rm_rf(worktree_path)
                {:error, reason}
            end
          else
            # No repo configured — just create a directory (non-git workspace)
            File.mkdir_p!(worktree_path)

            case run_after_create_hook(config, worktree_path) do
              :ok ->
                {:ok, workspace}

              {:error, reason} ->
                File.rm_rf!(worktree_path)
                {:error, reason}
            end
          end
        end
      end
    end
  end

  @doc """
  Returns the path to the main repo clone for a project.
  """
  @spec main_repo_path(String.t(), String.t()) :: String.t()
  def main_repo_path(root, project_name) do
    sanitized = Safety.sanitize_key(project_name)
    Path.join(root, sanitized)
  end

  # --- Private ---

  defp ensure_main_repo(config, root, project_name) do
    repo_path = main_repo_path(root, project_name)

    if File.dir?(Path.join(repo_path, ".git")) do
      # Already cloned — fetch latest
      fetch_main_repo(repo_path)
    else
      # First time — clone
      clone_main_repo(config, repo_path)
    end
  end

  defp clone_main_repo(config, repo_path) do
    repo = Config.get(config, "tracker", "repo")
    api_key = Config.get(config, "tracker", "api_key")

    url =
      cond do
        # Local path (for development/testing)
        String.starts_with?(repo, "/") -> repo
        # Authenticated GitHub URL
        api_key && api_key != "" -> "https://#{api_key}@github.com/#{repo}.git"
        # Public GitHub URL
        true -> "https://github.com/#{repo}.git"
      end

    File.mkdir_p!(repo_path)
    Logger.info("Cloning #{repo} into #{repo_path}")

    case System.cmd("git", ["clone", url, "."], cd: repo_path, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        Logger.error("git clone failed (exit #{exit_code}): #{output}")
        File.rm_rf!(repo_path)
        {:error, {:clone_failed, output}}
    end
  end

  defp fetch_main_repo(repo_path) do
    case System.cmd("git", ["fetch", "origin"], cd: repo_path, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        Logger.warning("git fetch failed (exit #{exit_code}): #{output}")
        # Non-fatal — worktree can still be created from existing state
        :ok
    end
  end

  defp create_worktree(root, project_name, issue_identifier, worktree_path) do
    repo_path = main_repo_path(root, project_name)
    branch_name = worktree_branch_name(issue_identifier)

    # Detect the default branch to branch from
    base_branch = detect_head_branch(repo_path)

    Logger.info("Creating worktree #{worktree_path} (branch #{branch_name} from #{base_branch})")

    case System.cmd(
           "git",
           ["worktree", "add", "-b", branch_name, worktree_path, base_branch],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        Logger.error("git worktree add failed (exit #{exit_code}): #{output}")
        {:error, {:worktree_failed, output}}
    end
  end

  defp detect_head_branch(repo_path) do
    # Try to find the default branch
    case System.cmd("git", ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        String.trim(output)

      _ ->
        # Fall back to checking common names
        cond do
          ref_exists?(repo_path, "origin/main") -> "origin/main"
          ref_exists?(repo_path, "origin/master") -> "origin/master"
          ref_exists?(repo_path, "main") -> "main"
          ref_exists?(repo_path, "master") -> "master"
          true -> "HEAD"
        end
    end
  end

  defp ref_exists?(repo_path, ref) do
    case System.cmd("git", ["rev-parse", "--verify", ref],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp worktree_branch_name(issue_identifier) do
    sanitized = Safety.sanitize_key(issue_identifier)
    "synkade/#{sanitized}"
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
