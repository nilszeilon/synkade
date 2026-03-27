defmodule SynkadeWeb.IssuesLive do
  use SynkadeWeb, :live_view

  import SynkadeWeb.Components.IssueView
  import SynkadeWeb.IssueLiveHelpers

  alias Synkade.{Issues, Jobs, Settings}
  alias Synkade.Issues.Issue

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Issues.pubsub_topic(scope.user.id))
      Phoenix.PubSub.subscribe(Synkade.PubSub, Jobs.pubsub_topic(scope))
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic(scope))
    end

    orc_state = Jobs.get_state(scope)
    projects = Settings.list_projects(scope)

    socket =
      socket
      |> assign(:page_title, "Issues")
      |> assign(:active_tab, :issues)
      |> assign(:current_project, nil)
      |> assign(:projects, orc_state.projects)
      |> assign(:running, orc_state.running)
      |> assign(:db_projects, projects)
      |> assign(:state_filter, nil)
      |> assign(:project_names, Map.new(projects, &{&1.id, &1.name}))
      |> assign(:issues, [])
      |> assign(:selected_issue, nil)
      |> assign(:view_mode, :list)
      |> assign(:form, nil)
      |> assign(:form_project_id, nil)
      |> assign(:form_parent_id, nil)
      |> assign(:create_ancestors, [])
      |> assign(:collapsed, MapSet.new())
      |> SynkadeWeb.Sidebar.assign_sidebar(scope)
      |> assign(:agents, Settings.list_agents(scope))
      |> assign(:selected_agent_id, nil)
      |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
      |> assign(:session_events, [])
      |> assign(:session_id, nil)
      |> assign(:session_subscribed, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = params["filter"]
    filter = if filter == "done", do: "done", else: nil

    socket =
      socket
      |> assign(:state_filter, filter)
      |> load_issues()

    # Handle view mode from URL params
    socket =
      cond do
        params["issue"] ->
          socket
          |> assign(:view_mode, :list)
          |> push_navigate(to: "/issues/#{params["issue"]}")

        params["new"] == "true" ->
          init_create_view(socket, params, fn s ->
            case s.assigns.db_projects do
              [first | _] -> first.id
              [] -> nil
            end
          end)

        true ->
          socket = unsubscribe_session(socket)

          socket
          |> assign(:selected_issue, nil)
          |> assign(:view_mode, :list)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:issues_updated}, socket) do
    socket =
      socket
      |> load_issues()
      |> reload_selected_issue(:list)
      |> SynkadeWeb.Sidebar.assign_sidebar(socket.assigns.current_scope)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:jobs_changed}, socket) do
    state = Jobs.get_state(socket.assigns.current_scope)

    socket =
      socket
      |> assign(:running, state.running)
      |> assign(:projects, state.projects)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_changed, snapshot}, socket) do
    socket =
      socket
      |> assign(:running, snapshot.running)
      |> assign(:projects, snapshot.projects)
      |> update_session_from_snapshot(snapshot)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:theme_updated, theme}, socket) do
    {:noreply, push_event(socket, "set-theme", %{theme: theme})}
  end

  @impl true
  def handle_info({:agents_updated}, socket) do
    {:noreply, assign(socket, :agents, Settings.list_agents(socket.assigns.current_scope))}
  end

  @impl true
  def handle_info({:projects_updated}, socket) do
    projects = Settings.list_projects(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:db_projects, projects)
     |> assign(:project_names, Map.new(projects, &{&1.id, &1.name}))}
  end

  @impl true
  def handle_info({:agent_event, event}, socket) do
    events = socket.assigns.session_events ++ [event]
    # Cap at 500 events in the UI
    events = Enum.take(events, -500)

    socket =
      socket
      |> assign(:session_events, events)
      |> assign(:session_id, event.session_id || socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_filter", %{"filter" => filter}, socket) do
    filter = if filter == "", do: nil, else: filter
    {:noreply, push_patch(socket, to: issues_path(filter))}
  end

  @impl true
  def handle_event("toggle_collapse", %{"id" => issue_id}, socket) do
    collapsed = socket.assigns.collapsed

    collapsed =
      if MapSet.member?(collapsed, issue_id) do
        MapSet.delete(collapsed, issue_id)
      else
        MapSet.put(collapsed, issue_id)
      end

    {:noreply, assign(socket, :collapsed, collapsed)}
  end

  @impl true
  def handle_event("select_issue", %{"id" => issue_id}, socket) do
    {:noreply, push_navigate(socket, to: "/issues/#{issue_id}")}
  end

  @impl true
  def handle_event("close_detail", _params, socket) do
    path = issues_path(socket.assigns.state_filter)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("new_issue", params, socket) do
    parent_id = params["parent_id"]
    path = new_issue_path(socket.assigns.state_filter, parent_id)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply, push_patch(socket, to: issues_path(socket.assigns.state_filter))}
  end

  @impl true
  def handle_event("validate_issue", %{"issue" => params}, socket) do
    changeset =
      %Issue{}
      |> Issues.change_issue(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("select_create_agent", %{"id" => agent_id}, socket) do
    {:noreply, assign(socket, :selected_agent_id, agent_id)}
  end

  @impl true
  def handle_event("save_issue", params, socket) do
    issue_params = params["issue"]
    project_id = issue_params["project_id"] || socket.assigns.form_project_id

    issue_params =
      issue_params
      |> Map.put("project_id", project_id)
      |> SynkadeWeb.IssueLiveHelpers.maybe_put_parent(socket.assigns[:form_parent_id])

    case Issues.create_issue(issue_params) do
      {:ok, issue} ->
        if params["dispatch"] == "true" do
          agent_id = params["agent_id"]
          agent_id = if agent_id == "", do: nil, else: agent_id

          case Issues.dispatch_issue(issue, issue.body, agent_id) do
            {:ok, _} ->
              socket =
                socket
                |> load_issues()
                |> put_flash(:info, "Issue created and dispatched")

              {:noreply, push_patch(socket, to: issues_path(socket.assigns.state_filter))}

            {:error, _} ->
              socket =
                socket
                |> load_issues()
                |> put_flash(:error, "Issue created but dispatch failed")

              {:noreply,
               push_patch(socket, to: issues_path(socket.assigns.state_filter, issue.id))}
          end
        else
          path = issues_path(socket.assigns.state_filter, issue.id)

          socket =
            socket
            |> load_issues()
            |> put_flash(:info, "Issue created")

          {:noreply, push_patch(socket, to: path)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("queue_issue", %{"id" => issue_id}, socket) do
    issue = Issues.get_issue!(issue_id)

    case Issues.queue_issue(issue) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_issues()
         |> put_flash(:info, "Issue queued")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot queue from current state")}
    end
  end

  @impl true
  def handle_event("unqueue_issue", %{"id" => issue_id}, socket) do
    issue = Issues.get_issue!(issue_id)

    case Issues.transition_state(issue, "backlog") do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_issues()
         |> put_flash(:info, "Issue moved to backlog")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot move to backlog from current state")}
    end
  end

  @impl true
  def handle_event("dispatch_issue", %{"dispatch" => %{"message" => message}}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, put_flash(socket, :error, "Dispatch message cannot be empty")}
    else
      issue = socket.assigns.selected_issue.issue

      {agent_name, instruction, agent_id} =
        resolve_dispatch(socket.assigns.current_scope, message)

      case Issues.dispatch_issue(issue, instruction, agent_id) do
        {:ok, _} ->
          socket =
            socket
            |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
            |> load_issues()
            |> put_flash(
              :info,
              "Issue dispatched" <> if(agent_name, do: " to #{agent_name}", else: "")
            )

          {:noreply, push_patch(socket, to: issues_path(socket.assigns.state_filter))}

        {:error, :invalid_transition} ->
          {:noreply, put_flash(socket, :error, "Cannot dispatch from current state")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to dispatch issue")}
      end
    end
  end

  @impl true
  def handle_event("cancel_issue", %{"id" => issue_id}, socket) do
    issue = Issues.get_issue!(issue_id)

    case Issues.cancel_issue(issue) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_issues()
         |> put_flash(:info, "Issue cancelled")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot cancel from current state")}
    end
  end

  @impl true
  def handle_event("delete_issue", %{"id" => issue_id}, socket) do
    issue = Issues.get_issue!(issue_id)

    case Issues.delete_issue(issue) do
      {:ok, _} ->
        socket =
          socket
          |> load_issues()
          |> put_flash(:info, "Issue deleted")

        {:noreply, push_patch(socket, to: issues_path(socket.assigns.state_filter))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete issue")}
    end
  end

  @impl true
  def handle_event("copy_resume", _params, socket) do
    session_id = socket.assigns.session_id

    if session_id do
      {:noreply, push_event(socket, "phx:copy", %{text: "claude --resume #{session_id}"})}
    else
      {:noreply, put_flash(socket, :error, "No session ID available")}
    end
  end

  # --- Private ---

  defp load_issues(socket) do
    states =
      case socket.assigns.state_filter do
        "done" -> ~w(done cancelled)
        _ -> ~w(backlog queued in_progress awaiting_review)
      end

    issues =
      Enum.flat_map(socket.assigns.db_projects, fn project ->
        Issues.list_issues_filtered(project.id, states)
      end)

    assign(socket, :issues, issues)
  end

  defp issues_path(filter, issue_id \\ nil) do
    params = %{}
    params = if filter, do: Map.put(params, "filter", filter), else: params
    params = if issue_id, do: Map.put(params, "issue", issue_id), else: params

    if params == %{} do
      "/issues"
    else
      "/issues?" <> URI.encode_query(params)
    end
  end

  defp new_issue_path(filter, parent_id) do
    params = %{"new" => "true"}
    params = if filter, do: Map.put(params, "filter", filter), else: params
    params = if parent_id, do: Map.put(params, "parent_id", parent_id), else: params
    "/issues?" <> URI.encode_query(params)
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      projects={@projects}
      running={@running}
      sidebar_issues={@sidebar_issues}
      sidebar_diff_stats={@sidebar_diff_stats}
      active_tab={@active_tab}
      current_project={@current_project}
      current_scope={@current_scope}
    >
      <div class="px-6 py-4">
        <%= cond do %>
          <% @view_mode == :detail && @selected_issue -> %>
            <.issue_full_view
              issue={@selected_issue.issue}
              ancestors={@selected_issue.ancestors}
              dispatch_form={@dispatch_form}
              agents={@agents}
              session_events={@session_events}
              session_id={@session_id}
              running_entry={find_running_entry(@running, @selected_issue.issue.id)}
              back_path={issues_path(@state_filter)}
              back_label="Issues"
            />
          <% @view_mode == :create -> %>
            <.issue_create_view
              form={@form}
              db_projects={@db_projects}
              agents={@agents}
              selected_agent_id={@selected_agent_id}
              form_project_id={@form_project_id}
              form_parent_id={@form_parent_id}
              create_ancestors={@create_ancestors}
              back_path={issues_path(@state_filter)}
            />
          <% true -> %>
            <div class="flex items-center justify-between mb-4">
              <h1 class="text-2xl font-bold">Issues</h1>
              <div class="flex items-center gap-2">
                <div class="flex items-center gap-1">
                  <button
                    :for={
                      {label, value} <- [
                        {"Open", nil},
                        {"Done", "done"}
                      ]
                    }
                    phx-click="set_filter"
                    phx-value-filter={value || ""}
                    class={[
                      "btn btn-xs",
                      if(@state_filter == value, do: "btn-primary", else: "btn-ghost")
                    ]}
                  >
                    {label}
                  </button>
                </div>
                <button phx-click="new_issue" class="btn btn-sm btn-primary">
                  New Issue
                </button>
              </div>
            </div>

            <div>
              <div :if={@issues == []} class="text-base-content/50 text-sm py-8 text-center">
                No issues
              </div>

              <div :for={issue <- @issues} class="mb-1">
                <.issue_flat_row
                  issue={issue}
                  project_name={Map.get(@project_names, issue.project_id)}
                />
              </div>
            </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :issue, :map, required: true
  attr :project_name, :string, default: nil

  defp issue_flat_row(assigns) do
    ~H"""
    <div
      class="flex items-center gap-2 py-1.5 px-2 rounded cursor-pointer hover:bg-base-200 group"
      phx-click="select_issue"
      phx-value-id={@issue.id}
    >
      <span :if={@project_name} class="text-xs text-base-content/50 w-24 truncate flex-shrink-0">
        {@project_name}
      </span>
      <span class="text-sm truncate flex-1 min-w-0">{Issue.title(@issue)}</span>
      <span :if={@issue.auto_merge} class="badge badge-xs badge-warning flex-shrink-0">
        auto-merge
      </span>
      <span :if={@issue.recurring} class="badge badge-xs badge-accent flex-shrink-0">recurring</span>
      <span class={"badge badge-xs #{state_badge_class(@issue.state)} flex-shrink-0"}>
        {@issue.state}
      </span>
      <a
        :if={@issue.github_pr_url}
        href={@issue.github_pr_url}
        target="_blank"
        class="flex-shrink-0 text-xs link link-primary"
        title="View Pull Request"
        onclick="event.stopPropagation()"
      >
        PR
      </a>
    </div>
    """
  end
end
