defmodule SynkadeWeb.Sidebar do
  @moduledoc "Loads sidebar data: issues grouped by project with diff stats."

  import Phoenix.Component, only: [assign: 3]

  alias Synkade.{Issues, Settings}
  alias Synkade.Settings.ConfigAdapter
  alias Synkade.Workflow.Config
  alias Synkade.Workspace.{Git, Safety}

  @doc "Assigns `:sidebar_issues` and `:sidebar_diff_stats` to the socket."
  def assign_sidebar(socket, scope) do
    {issues, stats} = load(scope)

    socket
    |> assign(:sidebar_issues, issues)
    |> assign(:sidebar_diff_stats, stats)
  end

  @doc """
  Returns `{issues_by_project, diff_stats}` where diff_stats is `%{issue_id => {adds, dels}}`.
  """
  def load(scope) do
    user_id = scope.user.id
    issues_by_project = Issues.list_active_by_user(user_id)

    setting = Settings.get_settings_for_user(user_id)
    projects_by_id = load_projects_by_id(scope)

    diff_stats =
      if setting do
        config = ConfigAdapter.to_config(setting)
        root = Config.workspace_root(config)

        issues_by_project
        |> Enum.flat_map(fn {_project_id, issues} -> issues end)
        |> Task.async_stream(
          fn issue ->
            project = Map.get(projects_by_id, issue.project_id)

            if project do
              path = workspace_path(root, project.name, issue.id)
              {issue.id, Git.diff_shortstat(path)}
            else
              {issue.id, {0, 0}}
            end
          end,
          max_concurrency: 8,
          timeout: 3_000,
          on_timeout: :kill_task
        )
        |> Enum.reduce(%{}, fn
          {:ok, {id, stats}}, acc -> Map.put(acc, id, stats)
          _, acc -> acc
        end)
      else
        %{}
      end

    {issues_by_project, diff_stats}
  end

  defp workspace_path(root, project_name, issue_id) do
    identifier = "#{project_name}##{String.slice(issue_id, 0..7)}"
    key = Safety.sanitize_key("#{project_name}/#{identifier}")
    Path.join(root, key)
  end

  defp load_projects_by_id(scope) do
    Settings.list_projects(scope)
    |> Map.new(fn p -> {p.id, p} end)
  end
end
