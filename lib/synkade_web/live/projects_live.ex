defmodule SynkadeWeb.ProjectsLive do
  use SynkadeWeb, :live_view

  require Logger

  alias Synkade.Jobs
  alias Synkade.Settings
  alias Synkade.Settings.Project

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic(scope))
      Phoenix.PubSub.subscribe(Synkade.PubSub, Jobs.pubsub_topic(scope))
      Phoenix.PubSub.subscribe(Synkade.PubSub, Synkade.Issues.pubsub_topic(scope.user.id))
    end

    orc_state = Jobs.get_state(scope)

    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:nav_active_tab, :projects)
     |> assign(:current_project, nil)
     |> assign(:projects, orc_state.projects)
     |> assign(:running, orc_state.running)
     |> SynkadeWeb.Sidebar.assign_sidebar(scope)
     |> assign(:db_projects, Settings.list_projects(scope))
     |> assign(:agents, Settings.list_agents(scope))
     |> assign(:editing, nil)
     |> assign(:form, nil)
     |> assign(:project_mode, nil)
     |> assign(:repos, [])
     |> assign(:repos_loading, false)
     |> assign(:repo_filter, "")
     |> assign(:saving, false)}
  end

  @impl true
  def handle_params(%{"name" => name}, _uri, socket) do
    project = Enum.find(socket.assigns.db_projects, &(&1.name == name))

    if project do
      changeset = Settings.change_project(project)

      {:noreply,
       socket
       |> assign(:page_title, "#{name} Settings")
       |> assign(:editing, project)
       |> assign(:project_mode, nil)
       |> assign(:form, to_form(changeset))}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Project not found.")
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    {:noreply,
     socket
     |> assign(:page_title, "New Project")
     |> assign(:editing, :new)
     |> assign(:project_mode, :choosing)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign(:form, nil)
     |> assign(:project_mode, nil)}
  end

  # --- Events ---

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, push_navigate(socket, to: "/projects/new")}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    project = Settings.get_project!(id)
    {:noreply, push_navigate(socket, to: "/projects/#{project.name}/settings")}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, push_navigate(socket, to: "/projects")}
  end

  @impl true
  def handle_event("select_mode", %{"mode" => "existing"}, socket) do
    if socket.assigns.repos == [] do
      send(self(), :fetch_repos)
      {:noreply, assign(socket, project_mode: :existing_repo, repos_loading: true)}
    else
      {:noreply, assign(socket, project_mode: :existing_repo)}
    end
  end

  @impl true
  def handle_event("select_mode", %{"mode" => "new"}, socket) do
    changeset = Settings.change_project(%Project{})

    {:noreply,
     socket
     |> assign(:project_mode, :new_repo)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("back_to_choosing", _params, socket) do
    {:noreply,
     socket
     |> assign(:project_mode, :choosing)
     |> assign(:form, nil)
     |> assign(:repo_filter, "")}
  end

  @impl true
  def handle_event("filter_repos", %{"value" => filter}, socket) do
    {:noreply, assign(socket, :repo_filter, filter)}
  end

  @impl true
  def handle_event("select_repo", %{"repo" => full_name}, socket) do
    repo_name = full_name |> String.split("/") |> List.last()

    changeset =
      Settings.change_project(%Project{}, %{
        "name" => repo_name,
        "tracker_repo" => full_name
      })

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:repo_filter, "")}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    project =
      case socket.assigns.editing do
        :new -> %Project{}
        %Project{} = p -> p
      end

    changeset =
      Settings.change_project(project, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"project" => params}, socket) do
    scope = socket.assigns.current_scope

    case socket.assigns.editing do
      :new when socket.assigns.project_mode == :new_repo ->
        # Validate first, then create GitHub repo
        changeset = Settings.change_project(%Project{}, params) |> Map.put(:action, :validate)

        if changeset.valid? do
          send(self(), {:create_repo_and_project, params})

          {:noreply,
           socket
           |> assign(:saving, true)
           |> put_flash(:info, "Creating repository...")}
        else
          {:noreply, assign(socket, :form, to_form(changeset))}
        end

      :new ->
        save_project(socket, scope, params)

      %Project{} = project ->
        case Settings.update_project(scope, project, params) do
          {:ok, _project} ->
            {:noreply,
             socket
             |> assign(:db_projects, Settings.list_projects(scope))
             |> put_flash(:info, "Project saved.")
             |> push_navigate(to: "/projects")}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = Settings.get_project!(id)
    scope = socket.assigns.current_scope

    case Settings.delete_project(scope, project) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:db_projects, Settings.list_projects(scope))
         |> put_flash(:info, "Project deleted.")
         |> push_navigate(to: "/projects")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete project.")}
    end
  end

  @impl true
  def handle_event("complete_issue", %{"id" => issue_id}, socket) do
    issue = Synkade.Issues.get_issue!(issue_id)

    case Synkade.Issues.complete_issue(issue) do
      {:ok, _} ->
        {:noreply,
         socket
         |> SynkadeWeb.Sidebar.assign_sidebar(socket.assigns.current_scope)
         |> put_flash(:info, "Issue archived")}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot archive from current state")}
    end
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    project = Settings.get_project!(id)
    scope = socket.assigns.current_scope

    case Settings.update_project(scope, project, %{enabled: !project.enabled}) do
      {:ok, _} ->
        {:noreply, assign(socket, :db_projects, Settings.list_projects(scope))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update project.")}
    end
  end

  # --- Private ---

  defp save_project(socket, scope, params) do
    case Settings.create_project(scope, params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> assign(:db_projects, Settings.list_projects(scope))
         |> put_flash(:info, "Project saved.")
         |> push_navigate(to: "/projects")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # --- Info ---

  @impl true
  def handle_info({:create_repo_and_project, params}, socket) do
    scope = socket.assigns.current_scope
    settings = Settings.get_settings(scope)
    name = params["name"] || ""

    if settings && settings.github_pat do
      config = %{"tracker" => %{"api_key" => settings.github_pat}}

      case Synkade.Tracker.GitHub.create_repo(config, name) do
        {:ok, full_name} ->
          params = Map.put(params, "tracker_repo", full_name)

          case Settings.create_project(scope, params) do
            {:ok, _project} ->
              {:noreply,
               socket
               |> assign(:saving, false)
               |> assign(:db_projects, Settings.list_projects(scope))
               |> put_flash(:info, "Repository created and project saved.")
               |> push_navigate(to: "/projects")}

            {:error, changeset} ->
              {:noreply,
               socket
               |> assign(:saving, false)
               |> assign(:form, to_form(changeset))}
          end

        {:error, :already_exists} ->
          {:noreply,
           socket
           |> assign(:saving, false)
           |> put_flash(:error, "A repository named \"#{name}\" already exists on GitHub.")}

        {:error, reason} ->
          Logger.warning("Failed to create GitHub repo: #{inspect(reason)}")

          {:noreply,
           socket
           |> assign(:saving, false)
           |> put_flash(:error, "Failed to create repository. Check your GitHub PAT permissions.")}
      end
    else
      {:noreply,
       socket
       |> assign(:saving, false)
       |> put_flash(:error, "No GitHub PAT configured. Add one in Settings.")}
    end
  end

  @impl true
  def handle_info(:fetch_repos, socket) do
    scope = socket.assigns.current_scope
    settings = Settings.get_settings(scope)

    repos =
      if settings && settings.github_pat do
        config = %{"tracker" => %{"api_key" => settings.github_pat}}

        case Synkade.Tracker.GitHub.list_user_repos(config) do
          {:ok, %{repos: repos}} -> repos
          {:error, reason} ->
            Logger.warning("Failed to fetch GitHub repos: #{inspect(reason)}")
            []
        end
      else
        []
      end

    {:noreply,
     socket
     |> assign(:repos, repos)
     |> assign(:repos_loading, false)}
  end

  @impl true
  def handle_info({:agents_updated}, socket) do
    {:noreply, assign(socket, :agents, Settings.list_agents(socket.assigns.current_scope))}
  end

  @impl true
  def handle_info({:jobs_changed}, socket) do
    state = Jobs.get_state(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:projects, state.projects)
     |> assign(:running, state.running)}
  end

  @impl true
  def handle_info({:state_changed, snapshot}, socket) do
    {:noreply,
     socket
     |> assign(:projects, snapshot.projects)
     |> assign(:running, snapshot.running)}
  end

  @impl true
  def handle_info({:issues_updated}, socket) do
    {:noreply,
     SynkadeWeb.Sidebar.assign_sidebar(socket, socket.assigns.current_scope)}
  end

  @impl true
  def handle_info({:theme_updated, theme}, socket) do
    {:noreply, push_event(socket, "set-theme", %{theme: theme})}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
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
      active_tab={@nav_active_tab}
      current_project={@current_project}
      current_scope={@current_scope}
      picker={@picker}
    >
      <div class="max-w-4xl mx-auto px-6 py-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold">Projects</h1>
          <button :if={@editing == nil} phx-click="new" class="btn btn-primary btn-sm">
            New Project
          </button>
        </div>

        <%= cond do %>
          <% @editing == :new and @project_mode == :choosing -> %>
            <.mode_chooser />
          <% @editing == :new and @project_mode == :existing_repo -> %>
            <.existing_repo_form
              form={@form}
              agents={@agents}
              repos={@repos}
              repos_loading={@repos_loading}
              repo_filter={@repo_filter}
            />
          <% @editing == :new and @project_mode == :new_repo -> %>
            <.new_repo_form form={@form} agents={@agents} saving={@saving} />
          <% @editing != nil -> %>
            <.edit_form form={@form} agents={@agents} />
          <% true -> %>
            <.project_list projects={@db_projects} />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # --- Components ---

  defp mode_chooser(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <h2 class="card-title text-lg">New Project</h2>
        <p class="text-sm text-base-content/60 mb-4">How would you like to start?</p>
        <div class="grid grid-cols-2 gap-3">
          <button
            type="button"
            phx-click="select_mode"
            phx-value-mode="existing"
            class="card bg-base-100 border border-base-300 hover:border-primary p-6 text-left transition-all cursor-pointer"
          >
            <.icon name="hero-arrow-down-tray" class="size-6 mb-2 text-primary" />
            <p class="font-semibold text-sm">Existing repository</p>
            <p class="text-xs text-base-content/50 mt-1">Connect a GitHub repo you already have</p>
          </button>
          <button
            type="button"
            phx-click="select_mode"
            phx-value-mode="new"
            class="card bg-base-100 border border-base-300 hover:border-primary p-6 text-left transition-all cursor-pointer"
          >
            <.icon name="hero-plus-circle" class="size-6 mb-2 text-primary" />
            <p class="font-semibold text-sm">New project</p>
            <p class="text-xs text-base-content/50 mt-1">Start fresh with a new project name</p>
          </button>
        </div>
        <div class="mt-4">
          <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">Cancel</button>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :agents, :list, required: true
  attr :repos, :list, default: []
  attr :repos_loading, :boolean, default: false
  attr :repo_filter, :string, default: ""

  defp existing_repo_form(assigns) do
    filtered =
      if assigns.repo_filter == "" do
        assigns.repos
      else
        q = String.downcase(assigns.repo_filter)
        Enum.filter(assigns.repos, fn r -> String.contains?(String.downcase(r.full_name), q) end)
      end

    assigns = assign(assigns, :filtered_repos, filtered)

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <div class="flex items-center gap-2 mb-2">
          <button type="button" phx-click="back_to_choosing" class="btn btn-ghost btn-xs btn-circle">
            <.icon name="hero-arrow-left" class="size-4" />
          </button>
          <h2 class="card-title text-lg">Select repository</h2>
        </div>

        <%= if @repos_loading do %>
          <div class="flex items-center gap-2 text-sm text-base-content/50 py-8 justify-center">
            <span class="loading loading-spinner loading-sm"></span>
            Loading repositories...
          </div>
        <% else %>
          <%= if @repos == [] do %>
            <div class="py-8 text-center">
              <p class="text-sm text-base-content/50">
                No repos found. Add a GitHub PAT in
                <.link navigate="/settings" class="link link-primary">Settings</.link>.
              </p>
            </div>
          <% else %>
            <%= if @form do %>
              <%!-- Repo selected — show config form --%>
              <div class="flex items-center gap-2 py-2 mb-2 border-b border-base-300">
                <.icon name="hero-link" class="size-4 text-base-content/50" />
                <span class="text-sm font-medium">{@form[:tracker_repo].value}</span>
              </div>

              <.form for={@form} phx-change="validate" phx-submit="save">
                <input type="hidden" name={@form[:tracker_repo].name} value={@form[:tracker_repo].value} />
                <div class="space-y-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text">Project name</span></label>
                    <input
                      type="text"
                      class="input input-bordered w-full"
                      name={@form[:name].name}
                      id={@form[:name].id}
                      value={@form[:name].value}
                      placeholder="my-project"
                    />
                    <.field_error field={@form[:name]} />
                  </div>

                  <.agent_select form={@form} agents={@agents} />
                </div>

                <div class="flex gap-2 mt-6">
                  <button type="submit" class="btn btn-primary">Create Project</button>
                  <button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button>
                </div>
              </.form>
            <% else %>
              <%!-- Repo picker --%>
              <input
                type="text"
                class="input input-bordered input-sm w-full mb-2"
                placeholder="Search repositories..."
                phx-keyup="filter_repos"
                name="repo_filter"
                value={@repo_filter}
                phx-debounce="100"
                autocomplete="off"
                autofocus
              />
              <div class="bg-base-100 border border-base-300 rounded-lg max-h-72 overflow-y-auto">
                <div :if={@filtered_repos == []} class="px-3 py-6 text-sm text-base-content/50 text-center">
                  No matching repositories.
                </div>
                <button
                  :for={repo <- @filtered_repos}
                  type="button"
                  class="w-full text-left px-3 py-2.5 text-sm hover:bg-base-200 cursor-pointer border-b border-base-300 last:border-b-0"
                  phx-click="select_repo"
                  phx-value-repo={repo.full_name}
                >
                  {repo.full_name}
                </button>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :agents, :list, required: true
  attr :saving, :boolean, default: false

  defp new_repo_form(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <div class="flex items-center gap-2 mb-2">
          <button type="button" phx-click="back_to_choosing" class="btn btn-ghost btn-xs btn-circle" disabled={@saving}>
            <.icon name="hero-arrow-left" class="size-4" />
          </button>
          <h2 class="card-title text-lg">New project</h2>
        </div>

        <p class="text-xs text-base-content/50 mb-2">A GitHub repository will be created automatically.</p>

        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Project name</span></label>
              <input
                type="text"
                class="input input-bordered w-full"
                name={@form[:name].name}
                id={@form[:name].id}
                value={@form[:name].value}
                placeholder="my-project"
                autofocus
                disabled={@saving}
              />
              <.field_error field={@form[:name]} />
            </div>

            <.agent_select form={@form} agents={@agents} />
          </div>

          <div class="flex gap-2 mt-6">
            <button type="submit" class="btn btn-primary" disabled={@saving}>
              <%= if @saving do %>
                <span class="loading loading-spinner loading-xs"></span>
                Creating...
              <% else %>
                Create Project
              <% end %>
            </button>
            <button type="button" phx-click="cancel" class="btn btn-ghost" disabled={@saving}>Cancel</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :agents, :list, required: true

  defp edit_form(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <h2 class="card-title text-lg">Edit Project</h2>

        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                class="input input-bordered w-full"
                name={@form[:name].name}
                id={@form[:name].id}
                value={@form[:name].value}
                placeholder="my-project"
              />
              <.field_error field={@form[:name]} />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Repository</span></label>
              <input
                type="text"
                class="input input-bordered w-full"
                name={@form[:tracker_repo].name}
                id={@form[:tracker_repo].id}
                value={@form[:tracker_repo].value}
                placeholder="owner/repo"
              />
            </div>

            <.agent_select form={@form} agents={@agents} />
          </div>

          <div class="flex gap-2 mt-6">
            <button type="submit" class="btn btn-primary">Save</button>
            <button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :projects, :list, required: true

  defp project_list(assigns) do
    ~H"""
    <%= if @projects == [] do %>
      <div class="text-center py-12 text-base-content/50">
        <p>No projects configured yet.</p>
        <p class="text-sm mt-1">Projects let you manage multiple repos with per-project settings.</p>
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Repo</th>
              <th>Enabled</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <%= for project <- @projects do %>
              <tr>
                <td class="font-medium">{project.name}</td>
                <td class="text-sm text-base-content/60">{project.tracker_repo || "-"}</td>
                <td>
                  <input
                    type="checkbox"
                    class="toggle toggle-sm toggle-primary"
                    checked={project.enabled}
                    phx-click="toggle_enabled"
                    phx-value-id={project.id}
                  />
                </td>
                <td class="text-right">
                  <button phx-click="edit" phx-value-id={project.id} class="btn btn-ghost btn-xs">
                    Edit
                  </button>
                  <button
                    phx-click="delete"
                    phx-value-id={project.id}
                    class="btn btn-ghost btn-xs text-error"
                    data-confirm="Delete this project?"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  # --- Shared components ---

  attr :form, :any, required: true
  attr :agents, :list, required: true

  defp agent_select(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label"><span class="label-text">Agent override</span></label>
      <select
        class="select select-bordered w-full"
        name={@form[:default_agent_id].name}
        id={@form[:default_agent_id].id}
      >
        <option value="" selected={is_nil(@form[:default_agent_id].value)}>
          Use default
        </option>
        <%= for agent <- @agents do %>
          <option value={agent.id} selected={@form[:default_agent_id].value == agent.id}>
            {agent.name}
          </option>
        <% end %>
      </select>
    </div>
    """
  end

  defp field_error(assigns) do
    ~H"""
    <%= if @field.errors != [] do %>
      <div class="label">
        <%= for {msg, _opts} <- @field.errors do %>
          <span class="label-text-alt text-error">{msg}</span>
        <% end %>
      </div>
    <% end %>
    """
  end
end
