defmodule SynkadeWeb.ProjectsLive do
  use SynkadeWeb, :live_view

  alias Synkade.Orchestrator
  alias Synkade.Settings
  alias Synkade.Settings.Project

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic())
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())
    end

    orc_state = Orchestrator.get_state()

    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:nav_active_tab, :projects)
     |> assign(:current_project, nil)
     |> assign(:projects, orc_state.projects)
     |> assign(:running, orc_state.running)
     |> assign(:db_projects, Settings.list_projects())
     |> assign(:agents, Settings.list_agents())
     |> assign(:editing, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("new", _params, socket) do
    changeset = Settings.change_project(%Project{})

    {:noreply,
     socket
     |> assign(:editing, :new)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    project = Settings.get_project!(id)
    changeset = Settings.change_project(project)

    {:noreply,
     socket
     |> assign(:editing, project)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, editing: nil, form: nil)}
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
    result =
      case socket.assigns.editing do
        :new -> Settings.create_project(params)
        %Project{} = project -> Settings.update_project(project, params)
      end

    case result do
      {:ok, _project} ->
        {:noreply,
         socket
         |> assign(:db_projects, Settings.list_projects())
         |> assign(:editing, nil)
         |> assign(:form, nil)
         |> put_flash(:info, "Project saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = Settings.get_project!(id)

    case Settings.delete_project(project) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:db_projects, Settings.list_projects())
         |> assign(:editing, nil)
         |> assign(:form, nil)
         |> put_flash(:info, "Project deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete project.")}
    end
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    project = Settings.get_project!(id)

    case Settings.update_project(project, %{enabled: !project.enabled}) do
      {:ok, _} ->
        {:noreply, assign(socket, :db_projects, Settings.list_projects())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update project.")}
    end
  end

  @impl true
  def handle_info({:agents_updated}, socket) do
    {:noreply, assign(socket, :agents, Settings.list_agents())}
  end

  @impl true
  def handle_info({:state_changed, snapshot}, socket) do
    {:noreply,
     socket
     |> assign(:projects, snapshot.projects)
     |> assign(:running, snapshot.running)}
  end

  @impl true
  def handle_info({:theme_updated, theme}, socket) do
    {:noreply, push_event(socket, "set-theme", %{theme: theme})}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      projects={@projects}
      running={@running}
      active_tab={@nav_active_tab}
      current_project={@current_project}
    >
      <div class="max-w-4xl mx-auto px-6 py-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold">Projects</h1>
          <button :if={@editing == nil} phx-click="new" class="btn btn-primary btn-sm">
            New Project
          </button>
        </div>

        <%= if @editing do %>
          <.project_form form={@form} editing={@editing} agents={@agents} />
        <% else %>
          <.project_list projects={@db_projects} />
        <% end %>
      </div>
    </Layouts.app>
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

  attr :form, :any, required: true
  attr :editing, :any, required: true
  attr :agents, :list, required: true

  defp project_form(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <h2 class="card-title text-lg">
          {if @editing == :new, do: "New Project", else: "Edit Project"}
        </h2>

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

            <div class="form-control">
              <label class="label"><span class="label-text">Default Agent</span></label>
              <select
                class="select select-bordered w-full"
                name={@form[:default_agent_id].name}
                id={@form[:default_agent_id].id}
              >
                <option value="" selected={is_nil(@form[:default_agent_id].value)}>
                  Use first agent
                </option>
                <%= for agent <- @agents do %>
                  <option value={agent.id} selected={@form[:default_agent_id].value == agent.id}>
                    {agent.name}
                  </option>
                <% end %>
              </select>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Prompt Template (Liquid, optional)</span>
              </label>
              <textarea
                class="textarea textarea-bordered w-full font-mono text-sm"
                rows="6"
                name={@form[:prompt_template].name}
                id={@form[:prompt_template].id}
              >{@form[:prompt_template].value}</textarea>
            </div>
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
