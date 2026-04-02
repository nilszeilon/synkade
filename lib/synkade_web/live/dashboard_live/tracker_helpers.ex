defmodule SynkadeWeb.DashboardLive.TrackerHelpers do
  @moduledoc "Tracker picker event handling for DashboardLive."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_patch: 2, push_navigate: 2]
  import SynkadeWeb.DashboardLive.BoardHelpers,
    only: [resolve_project: 1, resolve_db_id: 2, new_issue_path: 2, dashboard_path: 1]

  alias Synkade.Issues
  alias Synkade.Tracker.Client, as: TrackerClient

  @doc "Handle tracker-related events. Returns `{:halt, socket}` or `:cont`."
  def handle_tracker_event("tracker_filter", %{"filter" => filter} = params, socket) do
    if params["_target"] == nil do
      # Form was submitted — pick top match or create new
      filter_down = String.downcase(filter)

      filtered =
        if filter_down == "" do
          socket.assigns.tracker_issues
        else
          Enum.filter(socket.assigns.tracker_issues, fn issue ->
            String.contains?(String.downcase(issue.title), filter_down) ||
              String.contains?(String.downcase(issue.identifier), filter_down)
          end)
        end

      case filtered do
        [top | _] ->
          handle_tracker_event("pick_tracker_issue", %{"id" => top.id}, socket)

        [] when filter != "" ->
          {:halt,
           socket
           |> assign(:tracker_open, false)
           |> push_patch(to: new_issue_path(socket.assigns.current_project, body: "# #{filter}\n\n"))}

        _ ->
          {:halt, socket}
      end
    else
      {:halt, assign(socket, :tracker_filter, filter)}
    end
  end

  def handle_tracker_event("close_tracker", _params, socket) do
    {:halt,
     socket
     |> assign(:tracker_open, false)
     |> push_patch(to: dashboard_path(socket.assigns.current_project))}
  end

  def handle_tracker_event("pick_tracker_issue", %{"id" => tracker_id}, socket) do
    issue = Enum.find(socket.assigns.tracker_issues, &(&1.id == tracker_id))

    if issue do
      project = resolve_project(socket)
      project_id = resolve_db_id(project, socket.assigns.current_scope)

      body = "# #{issue.title}\n\n#{issue.description || ""}"

      case Issues.create_issue(%{
             "body" => body,
             "project_id" => project_id,
             "github_issue_url" => issue.url
           }) do
        {:ok, created} ->
          {:halt,
           socket
           |> assign(:tracker_open, false)
           |> put_flash(:info, "Issue imported from tracker")
           |> push_navigate(to: "/issues/#{created.id}")}

        {:error, _} ->
          {:halt, put_flash(socket, :error, "Failed to import issue")}
      end
    else
      {:halt, put_flash(socket, :error, "Issue not found")}
    end
  end

  def handle_tracker_event(_event, _params, _socket), do: :cont

  @doc "Handle tracker-related info messages. Returns `{:halt, socket}` or `:cont`."
  def handle_tracker_info(:load_tracker_issues, socket) do
    project = resolve_project(socket)

    tracker_issues =
      case project do
        nil ->
          []

        project ->
          case TrackerClient.fetch_all_issues(project.config, project.name, states: ["open"]) do
            {:ok, issues} -> Enum.sort_by(issues, & &1.created_at, {:desc, DateTime})
            {:error, _} -> []
          end
      end

    {:halt,
     socket
     |> assign(:tracker_issues, tracker_issues)
     |> assign(:tracker_loading, false)}
  end

  def handle_tracker_info(_msg, _socket), do: :cont
end
