defmodule SynkadeWeb.IdeWorkspaceHelpers do
  @moduledoc """
  Workspace, git, and diff helpers for IdeLive.
  Extracted to reduce ide_live.ex complexity.
  """
  import Phoenix.Component, only: [assign: 3]

  alias Synkade.{Settings}
  alias Synkade.Settings.ConfigAdapter
  alias Synkade.Workspace.{Git, Safety}
  alias Synkade.Workflow.Config

  def resolve_workspace_path(scope, project, issue) do
    setting = Settings.get_settings_for_user(scope.user.id)

    if setting do
      config = ConfigAdapter.to_config(setting)
      root = Config.workspace_root(config)
      identifier = "#{project.name}##{issue.id |> String.slice(0..7)}"
      key = Safety.sanitize_key("#{project.name}/#{identifier}")
      Path.join(root, key)
    else
      nil
    end
  end

  def detect_branches(nil), do: {"HEAD", nil}

  def detect_branches(path) do
    if File.dir?(path) && File.exists?(Path.join(path, ".git")) do
      {Git.detect_base_branch(path), Git.current_branch(path)}
    else
      {"HEAD", nil}
    end
  end

  def load_tracker_config(scope, project) do
    with setting when not is_nil(setting) <- Settings.get_settings_for_user(scope.user.id),
         agents = Settings.list_agents(scope),
         agent when not is_nil(agent) <-
           Settings.resolve_agent(agents,
             project_agent_id: project.default_agent_id,
             user_default_id: setting.default_agent_id
           ) do
      {:ok, ConfigAdapter.resolve_project_config(setting, project, agent)}
    else
      _ -> :error
    end
  end

  def load_commits_ahead(nil, _base_ref), do: 0

  def load_commits_ahead(path, base_ref) do
    if File.dir?(path) && File.exists?(Path.join(path, ".git")) do
      Git.commits_ahead(path, base_ref)
    else
      0
    end
  end

  def load_changed_files(nil, _base_ref), do: []

  def load_changed_files(path, base_ref) do
    if File.dir?(path) do
      case Git.changed_files(path, base_ref) do
        {:ok, files} -> files
        {:error, _} -> []
      end
    else
      []
    end
  end

  def load_file_diff(nil, _filename, _base_ref), do: []

  def load_file_diff(path, filename, base_ref) do
    case Git.file_diff(path, filename, base_ref) do
      {:ok, raw} -> Git.parse_diff(raw)
      {:error, _} -> []
    end
  end

  def maybe_refresh_selected_diff(socket) do
    if socket.assigns.selected_file do
      diff_lines =
        load_file_diff(
          socket.assigns.workspace_path,
          socket.assigns.selected_file,
          socket.assigns.base_branch
        )

      assign(socket, :file_diff, diff_lines)
    else
      socket
    end
  end

  def schedule_diff_refresh do
    Process.send_after(self(), :refresh_diff, 5_000)
  end

  def current_head_sha(nil), do: nil

  def current_head_sha(path) do
    if File.dir?(path) do
      case System.cmd("git", ["rev-parse", "HEAD"], cd: path, stderr_to_stdout: true) do
        {output, 0} -> String.trim(output)
        _ -> nil
      end
    end
  end

  def compute_turn_files(_path, nil), do: []

  def compute_turn_files(path, start_sha) do
    case Git.changed_files(path, start_sha) do
      {:ok, files} -> files
      _ -> []
    end
  end
end
