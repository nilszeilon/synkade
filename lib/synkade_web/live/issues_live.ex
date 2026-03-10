defmodule SynkadeWeb.IssuesLive do
  use SynkadeWeb, :live_view

  alias Synkade.{Issues, Orchestrator, Settings}
  alias Synkade.Issues.Issue

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Issues.pubsub_topic())
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())
    end

    orc_state = Orchestrator.get_state()
    projects = Settings.list_projects()

    socket =
      socket
      |> assign(:page_title, "Issues")
      |> assign(:active_tab, :issues)
      |> assign(:current_project, nil)
      |> assign(:projects, orc_state.projects)
      |> assign(:running, orc_state.running)
      |> assign(:db_projects, projects)
      |> assign(:selected_project_id, nil)
      |> assign(:issues, [])
      |> assign(:selected_issue, nil)
      |> assign(:show_form, false)
      |> assign(:form, nil)
      |> assign(:collapsed, MapSet.new())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = params["project_id"]

    socket =
      if project_id do
        socket
        |> assign(:selected_project_id, project_id)
        |> load_issues(project_id)
      else
        case socket.assigns.db_projects do
          [first | _] ->
            socket
            |> assign(:selected_project_id, first.id)
            |> load_issues(first.id)

          [] ->
            socket
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:issues_updated}, socket) do
    socket =
      if socket.assigns.selected_project_id do
        load_issues(socket, socket.assigns.selected_project_id)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_changed, snapshot}, socket) do
    {:noreply, assign(socket, :running, snapshot.running)}
  end

  @impl true
  def handle_event("select_project", %{"id" => project_id}, socket) do
    socket =
      socket
      |> assign(:selected_project_id, project_id)
      |> assign(:selected_issue, nil)
      |> load_issues(project_id)

    {:noreply, socket}
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
    issue = Issues.get_issue!(issue_id)
    ancestors = Issues.ancestor_chain(issue)
    {:noreply, assign(socket, :selected_issue, %{issue: issue, ancestors: ancestors})}
  end

  @impl true
  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :selected_issue, nil)}
  end

  @impl true
  def handle_event("new_issue", params, socket) do
    parent_id = params["parent_id"]
    changeset = Issues.change_issue(%Issue{}, %{parent_id: parent_id})

    socket =
      socket
      |> assign(:show_form, true)
      |> assign(:form, to_form(changeset))
      |> assign(:form_parent_id, parent_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:form, nil)}
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
  def handle_event("save_issue", %{"issue" => params}, socket) do
    params =
      params
      |> Map.put("project_id", socket.assigns.selected_project_id)
      |> maybe_put_parent(socket.assigns[:form_parent_id])

    case Issues.create_issue(params) do
      {:ok, _issue} ->
        socket =
          socket
          |> assign(:show_form, false)
          |> assign(:form, nil)
          |> load_issues(socket.assigns.selected_project_id)
          |> put_flash(:info, "Issue created")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("queue_issue", %{"id" => issue_id}, socket) do
    issue = Issues.get_issue!(issue_id)

    case Issues.queue_issue(issue) do
      {:ok, _} ->
        {:noreply, socket |> load_issues(socket.assigns.selected_project_id) |> put_flash(:info, "Issue queued")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot queue from current state")}
    end
  end

  @impl true
  def handle_event("cancel_issue", %{"id" => issue_id}, socket) do
    issue = Issues.get_issue!(issue_id)

    case Issues.cancel_issue(issue) do
      {:ok, _} ->
        {:noreply, socket |> load_issues(socket.assigns.selected_project_id) |> put_flash(:info, "Issue cancelled")}

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
          |> assign(:selected_issue, nil)
          |> load_issues(socket.assigns.selected_project_id)
          |> put_flash(:info, "Issue deleted")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete issue")}
    end
  end

  # --- Private ---

  defp load_issues(socket, project_id) do
    issues = Issues.list_root_issues(project_id)
    assign(socket, :issues, issues)
  end

  defp maybe_put_parent(params, nil), do: params
  defp maybe_put_parent(params, parent_id), do: Map.put(params, "parent_id", parent_id)

  defp state_badge_class("backlog"), do: "badge-ghost"
  defp state_badge_class("queued"), do: "badge-info"
  defp state_badge_class("in_progress"), do: "badge-warning"
  defp state_badge_class("awaiting_review"), do: "badge-secondary"
  defp state_badge_class("done"), do: "badge-success"
  defp state_badge_class("cancelled"), do: "badge-error"
  defp state_badge_class(_), do: "badge-ghost"

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      projects={@projects}
      running={@running}
      active_tab={@active_tab}
      current_project={@current_project}
    >
      <div class="px-6 py-4">
        <div class="flex items-center justify-between mb-4">
          <h1 class="text-2xl font-bold">Issues</h1>
          <div class="flex items-center gap-2">
            <select
              phx-change="select_project"
              class="select select-sm select-bordered"
              name="id"
            >
              <option :for={p <- @db_projects} value={p.id} selected={p.id == @selected_project_id}>
                {p.name}
              </option>
            </select>
            <button phx-click="new_issue" class="btn btn-sm btn-primary">
              New Issue
            </button>
          </div>
        </div>

        <!-- New issue form -->
        <div :if={@show_form} class="card bg-base-200 p-4 mb-4">
          <.form for={@form} phx-change="validate_issue" phx-submit="save_issue">
            <div class="flex flex-col gap-3">
              <div class="form-control">
                <input
                  type="text"
                  name="issue[title]"
                  value={@form[:title].value}
                  placeholder="Issue title"
                  class="input input-bordered input-sm w-full"
                  phx-debounce="300"
                />
                <span
                  :for={msg <- Enum.map(@form[:title].errors, &translate_error/1)}
                  class="text-error text-xs"
                >
                  {msg}
                </span>
              </div>
              <div class="form-control">
                <textarea
                  name="issue[description]"
                  placeholder="Description (optional)"
                  class="textarea textarea-bordered textarea-sm w-full"
                  rows="3"
                  phx-debounce="300"
                >{@form[:description].value}</textarea>
              </div>
              <div class="flex gap-2">
                <button type="submit" class="btn btn-sm btn-primary">Create</button>
                <button type="button" phx-click="cancel_form" class="btn btn-sm btn-ghost">Cancel</button>
              </div>
            </div>
          </.form>
        </div>

        <div class="flex gap-4">
          <!-- Issue tree -->
          <div class={["flex-1 min-w-0", @selected_issue && "max-w-[60%]"]}>
            <div :if={@issues == []} class="text-base-content/50 text-sm py-8 text-center">
              No issues yet. Create one to get started.
            </div>
            <div :for={issue <- @issues} class="mb-1">
              <.issue_tree_row
                issue={issue}
                depth={0}
                collapsed={@collapsed}
                selected_id={@selected_issue && @selected_issue.issue.id}
              />
            </div>
          </div>

          <!-- Detail panel -->
          <div :if={@selected_issue} class="w-[40%] flex-shrink-0">
            <.issue_detail
              issue={@selected_issue.issue}
              ancestors={@selected_issue.ancestors}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :issue, :map, required: true
  attr :depth, :integer, required: true
  attr :collapsed, :any, required: true
  attr :selected_id, :string, default: nil

  defp issue_tree_row(assigns) do
    has_children = assigns.issue.children != [] and is_list(assigns.issue.children)
    is_collapsed = MapSet.member?(assigns.collapsed, assigns.issue.id)

    assigns =
      assigns
      |> assign(:has_children, has_children)
      |> assign(:is_collapsed, is_collapsed)

    ~H"""
    <div>
      <div
        class={[
          "flex items-center gap-2 py-1.5 px-2 rounded cursor-pointer hover:bg-base-200 group",
          @issue.id == @selected_id && "bg-base-200"
        ]}
        style={"padding-left: #{@depth * 24 + 8}px"}
      >
        <button
          :if={@has_children}
          phx-click="toggle_collapse"
          phx-value-id={@issue.id}
          class="btn btn-ghost btn-xs btn-circle"
        >
          <span class={["text-xs", @is_collapsed && "rotate-[-90deg]"]}>
            &#9660;
          </span>
        </button>
        <span :if={!@has_children} class="w-6"></span>

        <div class="flex-1 min-w-0 flex items-center gap-2" phx-click="select_issue" phx-value-id={@issue.id}>
          <span class="text-sm truncate">{@issue.title}</span>
          <span class={"badge badge-xs #{state_badge_class(@issue.state)} ml-auto flex-shrink-0"}>
            {@issue.state}
          </span>
        </div>

        <div class="opacity-0 group-hover:opacity-100 flex gap-1 flex-shrink-0">
          <button
            :if={@issue.state == "backlog"}
            phx-click="queue_issue"
            phx-value-id={@issue.id}
            class="btn btn-ghost btn-xs"
            title="Queue"
          >
            Queue
          </button>
          <button
            phx-click="new_issue"
            phx-value-parent_id={@issue.id}
            class="btn btn-ghost btn-xs"
            title="Add child"
          >
            +
          </button>
        </div>
      </div>

      <div :if={@has_children && !@is_collapsed}>
        <.issue_tree_row
          :for={child <- @issue.children}
          issue={child}
          depth={@depth + 1}
          collapsed={@collapsed}
          selected_id={@selected_id}
        />
      </div>
    </div>
    """
  end

  attr :issue, :map, required: true
  attr :ancestors, :list, required: true

  defp issue_detail(assigns) do
    ~H"""
    <div class="card bg-base-200 p-4 sticky top-4">
      <div class="flex items-start justify-between mb-3">
        <div>
          <div class="flex items-center gap-2 mb-1">
            <span class={"badge badge-sm #{state_badge_class(@issue.state)}"}>{@issue.state}</span>
          </div>
          <h2 class="text-lg font-bold">{@issue.title}</h2>
        </div>
        <button phx-click="close_detail" class="btn btn-ghost btn-sm btn-circle">x</button>
      </div>

      <!-- Ancestor chain -->
      <div :if={@ancestors != []} class="mb-3">
        <p class="text-xs text-base-content/50 mb-1">Path</p>
        <div class="flex items-center gap-1 text-xs flex-wrap">
          <span
            :for={{ancestor, idx} <- Enum.with_index(@ancestors)}
            class="flex items-center gap-1"
          >
            <span :if={idx > 0} class="text-base-content/30">/</span>
            <span class="text-base-content/70">{ancestor.title}</span>
          </span>
        </div>
      </div>

      <!-- Description -->
      <div :if={@issue.description} class="mb-3">
        <p class="text-xs text-base-content/50 mb-1">Description</p>
        <p class="text-sm whitespace-pre-wrap">{@issue.description}</p>
      </div>

      <!-- Agent output -->
      <div :if={@issue.agent_output} class="mb-3">
        <p class="text-xs text-base-content/50 mb-1">Agent Output</p>
        <pre class="text-xs bg-base-300 p-2 rounded overflow-auto max-h-64">{@issue.agent_output}</pre>
      </div>

      <!-- GitHub links -->
      <div :if={@issue.github_issue_url || @issue.github_pr_url} class="mb-3 flex gap-2">
        <a :if={@issue.github_issue_url} href={@issue.github_issue_url} target="_blank" class="link link-primary text-xs">
          GitHub Issue
        </a>
        <a :if={@issue.github_pr_url} href={@issue.github_pr_url} target="_blank" class="link link-primary text-xs">
          Pull Request
        </a>
      </div>

      <!-- Children list -->
      <div :if={@issue.children != [] and is_list(@issue.children)} class="mb-3">
        <p class="text-xs text-base-content/50 mb-1">Children ({length(@issue.children)})</p>
        <div :for={child <- @issue.children} class="flex items-center gap-2 py-1">
          <span
            class="text-sm cursor-pointer hover:underline"
            phx-click="select_issue"
            phx-value-id={child.id}
          >
            {child.title}
          </span>
          <span class={"badge badge-xs #{state_badge_class(child.state)} ml-auto"}>{child.state}</span>
        </div>
      </div>

      <!-- Actions -->
      <div class="flex gap-2 pt-2 border-t border-base-300">
        <button
          :if={@issue.state == "backlog"}
          phx-click="queue_issue"
          phx-value-id={@issue.id}
          class="btn btn-sm btn-info"
        >
          Queue
        </button>
        <button
          :if={@issue.state not in ["done", "cancelled"]}
          phx-click="cancel_issue"
          phx-value-id={@issue.id}
          class="btn btn-sm btn-ghost"
        >
          Cancel
        </button>
        <button
          phx-click="new_issue"
          phx-value-parent_id={@issue.id}
          class="btn btn-sm btn-ghost"
        >
          Add Child
        </button>
        <button
          phx-click="delete_issue"
          phx-value-id={@issue.id}
          class="btn btn-sm btn-error btn-ghost ml-auto"
          data-confirm="Delete this issue and orphan its children?"
        >
          Delete
        </button>
      </div>
    </div>
    """
  end
end
