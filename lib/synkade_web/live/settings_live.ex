defmodule SynkadeWeb.SettingsLive do
  use SynkadeWeb, :live_view

  alias Synkade.Jobs
  alias Synkade.Settings
  alias Synkade.Settings.{Agent, ConnectionTest}
  alias Synkade.Skills

  import SynkadeWeb.Components.AgentBrand

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic(scope))
      Phoenix.PubSub.subscribe(Synkade.PubSub, Jobs.pubsub_topic(scope))
      Phoenix.PubSub.subscribe(Synkade.PubSub, Synkade.Issues.pubsub_topic(scope.user.id))
    end

    setting = Settings.get_settings(scope)
    changeset = Settings.change_settings(scope, setting)
    orc_state = Jobs.get_state(scope)
    current_theme = (setting && setting.theme) || "paper"

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:setting, setting)
     |> assign(:nav_active_tab, :settings)
     |> assign(:current_project, nil)
     |> assign(:projects, orc_state.projects)
     |> assign(:running, orc_state.running)
     |> SynkadeWeb.Sidebar.assign_sidebar(scope)
     |> assign(:active_tab, "agents")
     |> assign(:current_theme, current_theme)
     |> assign(:connection_status, nil)
     |> assign(:connection_testing, false)
     |> refresh_agent_lists(scope)
     |> assign(:editing_ephemeral_kind, nil)
     |> assign(:agent_form, nil)
     |> assign(:skills, Skills.list_skills(scope))
     |> assign(:skill_form, nil)
     |> assign(:pat_mode, if(setting && setting.github_pat, do: :masked, else: :editing))
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("validate", %{"setting" => params}, socket) do
    changeset =
      Settings.change_settings(socket.assigns.current_scope, socket.assigns.setting, params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"setting" => params}, socket) do
    scope = socket.assigns.current_scope

    case Settings.save_settings(scope, params) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> assign(:setting, setting)
         |> assign(:pat_mode, if(setting.github_pat, do: :masked, else: :editing))
         |> assign_form(Settings.change_settings(scope, setting))
         |> put_flash(:info, "Settings saved.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("change_pat", _params, socket) do
    {:noreply, assign(socket, :pat_mode, :editing)}
  end

  @impl true
  def handle_event("cancel_change_pat", _params, socket) do
    {:noreply, assign(socket, :pat_mode, :masked)}
  end

  @impl true
  def handle_event("test_connection", _params, socket) do
    socket = assign(socket, connection_testing: true, connection_status: nil)
    form_data = socket.assigns.form.params || %{}

    token =
      case socket.assigns.pat_mode do
        :masked -> socket.assigns.setting && socket.assigns.setting.github_pat
        :editing -> form_data["github_pat"]
      end || ""

    lv = self()

    Task.start(fn ->
      result = ConnectionTest.test_pat(token, nil)
      send(lv, {:connection_result, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_default_agent", %{"default_agent_id" => agent_id}, socket) do
    scope = socket.assigns.current_scope
    agent_id = if agent_id == "", do: nil, else: agent_id

    case Settings.save_settings(scope, %{default_agent_id: agent_id}) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> assign(:setting, setting)
         |> put_flash(:info, "Default agent updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update default agent.")}
    end
  end

  @impl true
  def handle_event("set_default_model", %{"value" => model}, socket) do
    scope = socket.assigns.current_scope
    model = if model == "", do: nil, else: model

    case Settings.save_settings(scope, %{default_model: model}) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> assign(:setting, setting)
         |> put_flash(:info, "Default model updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update default model.")}
    end
  end

  # --- Ephemeral agent events ---

  @impl true
  def handle_event("configure_ephemeral", %{"kind" => kind}, socket) do
    scope = socket.assigns.current_scope
    agent = Settings.get_agent_by_kind(scope, kind) || %Agent{kind: kind}
    changeset = Settings.change_agent(agent)

    {:noreply,
     socket
     |> assign(:editing_ephemeral_kind, kind)
     |> assign(:agent_form, to_form(changeset))}
  end

  @impl true
  def handle_event("cancel_ephemeral", _params, socket) do
    {:noreply, assign(socket, editing_ephemeral_kind: nil, agent_form: nil)}
  end

  @impl true
  def handle_event("validate_ephemeral", %{"agent" => params}, socket) do
    kind = socket.assigns.editing_ephemeral_kind
    scope = socket.assigns.current_scope
    agent = Settings.get_agent_by_kind(scope, kind) || %Agent{kind: kind}

    changeset =
      Settings.change_agent(agent, normalize_agent_params(Map.put(params, "kind", kind)))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :agent_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_ephemeral", %{"agent" => params}, socket) do
    scope = socket.assigns.current_scope
    kind = socket.assigns.editing_ephemeral_kind
    params = normalize_agent_params(Map.put(params, "kind", kind))

    case Settings.upsert_agent(scope, params) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> refresh_agent_lists(scope)
         |> assign(:editing_ephemeral_kind, nil)
         |> assign(:agent_form, nil)
         |> put_flash(:info, "#{kind} configured.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :agent_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("remove_ephemeral", %{"kind" => kind}, socket) do
    scope = socket.assigns.current_scope

    case Settings.get_agent_by_kind(scope, kind) do
      nil ->
        {:noreply, socket}

      agent ->
        case Settings.delete_agent(scope, agent) do
          {:ok, _} ->
            {:noreply,
             socket
             |> refresh_agent_lists(scope)
             |> put_flash(:info, "#{kind} removed.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove agent.")}
        end
    end
  end

  # --- Skill events ---

  @impl true
  def handle_event("new_skill", _params, socket) do
    changeset = Skills.change_skill(%Synkade.Skills.Skill{})
    {:noreply, assign(socket, :skill_form, to_form(changeset))}
  end

  @impl true
  def handle_event("cancel_skill", _params, socket) do
    {:noreply, assign(socket, :skill_form, nil)}
  end

  @impl true
  def handle_event("save_skill", %{"skill" => params}, socket) do
    scope = socket.assigns.current_scope

    case Skills.create_skill(scope, params) do
      {:ok, _skill} ->
        {:noreply,
         socket
         |> assign(:skills, Skills.list_skills(scope))
         |> assign(:skill_form, nil)
         |> put_flash(:info, "Skill created.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :skill_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_skill", %{"id" => id}, socket) do
    skill = Skills.get_skill!(id)
    scope = socket.assigns.current_scope

    case Skills.delete_skill(scope, skill) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:skills, Skills.list_skills(scope))
         |> put_flash(:info, "Skill removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove skill.")}
    end
  end

  @impl true
  def handle_event("restore_skill", %{"name" => name}, socket) do
    scope = socket.assigns.current_scope
    default = Enum.find(Skills.defaults(), &(&1["name"] == name))

    if default do
      Skills.create_skill(scope, %{
        "name" => default["name"],
        "content" => default["content"],
        "built_in" => true
      })

      {:noreply,
       socket
       |> assign(:skills, Skills.list_skills(scope))
       |> put_flash(:info, "Skill re-enabled.")}
    else
      {:noreply, socket}
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
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    case Settings.save_theme(socket.assigns.current_scope, theme) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> assign(:current_theme, theme)
         |> push_event("set-theme", %{theme: theme})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save theme.")}
    end
  end

  @impl true
  def handle_info({:theme_updated, theme}, socket) do
    {:noreply,
     socket
     |> assign(:current_theme, theme)
     |> push_event("set-theme", %{theme: theme})}
  end

  @impl true
  def handle_info({:settings_updated, _settings}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agents_updated}, socket) do
    {:noreply, refresh_agent_lists(socket, socket.assigns.current_scope)}
  end

  @impl true
  def handle_info({:projects_updated}, socket) do
    state = Jobs.get_state(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:projects, state.projects)
     |> assign(:running, state.running)
     |> SynkadeWeb.Sidebar.assign_sidebar(socket.assigns.current_scope)}
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
    {:noreply, SynkadeWeb.Sidebar.assign_sidebar(socket, socket.assigns.current_scope)}
  end

  @impl true
  def handle_info({:connection_result, result}, socket) do
    status =
      case result do
        {:ok, msg} -> {:ok, msg}
        {:error, msg} -> {:error, msg}
      end

    {:noreply, assign(socket, connection_status: status, connection_testing: false)}
  end

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
      <div class="max-w-3xl mx-auto px-6 py-6">
        <h1 class="text-2xl font-bold mb-6">Settings</h1>

        <div role="tablist" class="tabs tabs-boxed mb-6">
          <button
            role="tab"
            class={"tab #{if @active_tab == "agents", do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="agents"
          >
            Agents
          </button>
          <button
            role="tab"
            class={"tab #{if @active_tab == "appearance", do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="appearance"
          >
            Appearance
          </button>
          <button
            role="tab"
            class={"tab #{if @active_tab == "github", do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="github"
          >
            GitHub
          </button>
          <button
            role="tab"
            class={"tab #{if @active_tab == "skills", do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="skills"
          >
            Skills
          </button>
          <button
            :if={not Synkade.Deployment.hosted?()}
            role="tab"
            class={"tab #{if @active_tab == "execution", do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="execution"
          >
            Execution
          </button>
        </div>

        <div class={if @active_tab != "appearance", do: "hidden"}>
          <.appearance_tab current_theme={@current_theme} />
        </div>

        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class={if @active_tab != "github", do: "hidden"}>
            <.github_tab
              form={@form}
              connection_status={@connection_status}
              connection_testing={@connection_testing}
              pat_mode={@pat_mode}
            />
          </div>

          <div
            :if={not Synkade.Deployment.hosted?()}
            class={if @active_tab != "execution", do: "hidden"}
          >
            <.execution_tab form={@form} />
          </div>

          <div
            :if={
              @active_tab == "github" or
                (@active_tab == "execution" and not Synkade.Deployment.hosted?())
            }
            class="mt-6"
          >
            <button type="submit" class="btn btn-primary">Save Settings</button>
          </div>
        </.form>

        <div class={if @active_tab != "agents", do: "hidden"}>
          <.agents_tab
            agents={@agents}
            editing_ephemeral_kind={@editing_ephemeral_kind}
            agent_form={@agent_form}
            setting={@setting}
          />
        </div>

        <div class={if @active_tab != "skills", do: "hidden"}>
          <.skills_tab skills={@skills} skill_form={@skill_form} />
        </div>

        <div class="border-t border-base-300 mt-8 pt-6">
          <.link
            href="/users/log-out"
            method="delete"
            class="btn btn-outline btn-error btn-sm"
          >
            Log out
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @theme_meta %{
    "ops" => %{
      label: "Ops",
      desc: "Terminal green + amber",
      swatches: ["oklch(87.82% 0.246 145.09)", "oklch(74.5% 0.155 80)", "oklch(10% 0 0)"]
    },
    "copper" => %{
      label: "Copper",
      desc: "Warm peach + copper accents",
      swatches: ["oklch(85% 0.08 55)", "oklch(70% 0.14 50)", "oklch(12% 0.01 50)"]
    },
    "midnight" => %{
      label: "Midnight",
      desc: "Cool cyan + blue on navy",
      swatches: ["oklch(85% 0.10 200)", "oklch(70% 0.16 240)", "oklch(12% 0.02 250)"]
    },
    "phantom" => %{
      label: "Phantom",
      desc: "Lavender + violet/magenta",
      swatches: ["oklch(85% 0.08 300)", "oklch(68% 0.18 310)", "oklch(12% 0.02 300)"]
    },
    "ember" => %{
      label: "Ember",
      desc: "Warm sand + fire accents",
      swatches: ["oklch(85% 0.06 70)", "oklch(68% 0.20 30)", "oklch(12% 0.015 30)"]
    },
    "daylight" => %{
      label: "Daylight",
      desc: "Crisp white + slate-blue",
      swatches: ["oklch(20% 0.02 250)", "oklch(50% 0.18 250)", "oklch(98% 0 0)"]
    },
    "paper" => %{
      label: "Paper",
      desc: "Warm off-white + olive/forest",
      swatches: ["oklch(22% 0.02 80)", "oklch(45% 0.12 145)", "oklch(96% 0.01 80)"]
    }
  }

  attr :current_theme, :string, required: true

  defp appearance_tab(assigns) do
    assigns = assign(assigns, :themes, @theme_meta)

    ~H"""
    <div>
      <p class="text-sm text-base-content/60 mb-4">
        Choose a theme. All themes keep the ops console aesthetic.
      </p>
      <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
        <button
          :for={{id, meta} <- @themes}
          type="button"
          phx-click="set_theme"
          phx-value-theme={id}
          class={[
            "card bg-base-200 border p-4 text-left transition-all",
            if(@current_theme == id,
              do: "border-primary ring-1 ring-primary",
              else: "border-base-300 hover:border-base-content/30"
            )
          ]}
        >
          <div class="flex gap-1.5 mb-2">
            <span
              :for={color <- meta.swatches}
              class="inline-block w-5 h-5 border border-base-300"
              style={"background:#{color}"}
            >
            </span>
          </div>
          <p class="font-semibold text-sm">{meta.label}</p>
          <p class="text-xs text-base-content/50">{meta.desc}</p>
        </button>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :connection_status, :any, default: nil
  attr :connection_testing, :boolean, default: false
  attr :pat_mode, :atom, required: true

  defp github_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="form-control">
        <label class="label"><span class="label-text">Personal Access Token</span></label>
        <%= if @pat_mode == :masked do %>
          <div class="flex gap-2">
            <input
              type="password"
              class="input input-bordered w-full"
              value="••••••••••••"
              disabled
            />
            <button type="button" phx-click="change_pat" class="btn btn-outline btn-sm shrink-0">
              Change
            </button>
          </div>
        <% else %>
          <input
            type="password"
            class="input input-bordered w-full"
            name={@form[:github_pat].name}
            id={@form[:github_pat].id}
            placeholder="ghp_..."
          />
          <.field_error field={@form[:github_pat]} />
        <% end %>
      </div>

      <div class="flex items-center gap-4 mt-4">
        <button
          type="button"
          class="btn btn-outline btn-sm"
          phx-click="test_connection"
          disabled={@connection_testing}
        >
          <%= if @connection_testing do %>
            <span class="loading loading-spinner loading-xs"></span> Testing...
          <% else %>
            Test Connection
          <% end %>
        </button>
        <%= if @connection_status do %>
          <span class={[
            "text-sm",
            elem(@connection_status, 0) == :ok && "text-success",
            elem(@connection_status, 0) == :error && "text-error"
          ]}>
            {elem(@connection_status, 1)}
          </span>
        <% end %>
      </div>
    </div>
    """
  end

  attr :agents, :list, required: true
  attr :editing_ephemeral_kind, :string, default: nil
  attr :agent_form, :any, required: true
  attr :setting, :any, default: nil

  defp agents_tab(assigns) do
    agents_by_kind = Map.new(assigns.agents, fn a -> {a.kind, a} end)
    assigns = assign(assigns, :agents_by_kind, agents_by_kind)

    ~H"""
    <div>
      <%!-- Global defaults --%>
      <%= if @agents != [] do %>
        <div class="form-control mb-6">
          <label class="label"><span class="label-text font-medium">Default Agent</span></label>
          <p class="text-xs text-base-content/50 mb-2">
            Used for all projects unless overridden per-project.
          </p>
          <select
            class="select select-bordered w-full max-w-xs"
            phx-change="set_default_agent"
            name="default_agent_id"
          >
            <option value="" selected={is_nil(@setting && @setting.default_agent_id)}>
              First agent
            </option>
            <%= for agent <- @agents do %>
              <option
                value={agent.id}
                selected={@setting && @setting.default_agent_id == agent.id}
              >
                {brand_label(agent.kind)}
              </option>
            <% end %>
          </select>
        </div>

        <div class="form-control mb-6">
          <label class="label"><span class="label-text font-medium">Default Model</span></label>
          <p class="text-xs text-base-content/50 mb-2">
            Leave blank to use each agent's built-in default. For OpenCode, use provider/model format.
          </p>
          <input
            type="text"
            class="input input-bordered w-full max-w-xs"
            name="default_model"
            value={@setting && @setting.default_model}
            placeholder="e.g. claude-sonnet-4-5-20250929"
            phx-blur="set_default_model"
          />
        </div>
      <% end %>

      <%!-- Agent integrations --%>
      <div class="mb-8">
        <h3 class="text-sm font-semibold mb-1">Agents</h3>
        <p class="text-xs text-base-content/50 mb-4">Configure your coding agents. One per type.</p>

        <div class="grid grid-cols-3 gap-3">
          <%= for kind <- Agent.kinds() do %>
            <% agent = @agents_by_kind[kind] %>
            <div class={[
              "card bg-base-200 border p-4 transition-all",
              if(agent, do: "border-success/30", else: "border-base-300")
            ]}>
              <div class="flex flex-col items-center gap-2 mb-3">
                <span class={brand_color(kind)}>
                  <.agent_icon kind={kind} class="size-6" />
                </span>
                <span class="font-medium text-sm">{brand_label(kind)}</span>
                <%= if agent do %>
                  <span class="badge badge-success badge-sm">Connected</span>
                <% else %>
                  <span class="badge badge-ghost badge-sm">Not configured</span>
                <% end %>
              </div>

              <%= if @editing_ephemeral_kind == kind do %>
                <.ephemeral_form form={@agent_form} kind={kind} />
              <% else %>
                <div class="flex justify-center gap-2">
                  <button
                    type="button"
                    phx-click="configure_ephemeral"
                    phx-value-kind={kind}
                    class="btn btn-ghost btn-xs"
                  >
                    {if agent, do: "Edit", else: "Configure"}
                  </button>
                  <%= if agent do %>
                    <button
                      type="button"
                      phx-click="remove_ephemeral"
                      phx-value-kind={kind}
                      class="btn btn-ghost btn-xs text-error"
                      data-confirm={"Remove #{brand_label(kind)} integration?"}
                    >
                      Remove
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

    </div>
    """
  end

  attr :form, :any, required: true
  attr :kind, :string, required: true

  defp ephemeral_form(assigns) do
    ~H"""
    <.form for={@form} phx-change="validate_ephemeral" phx-submit="save_ephemeral" class="mt-2">
      <div class="space-y-3">
        <div class="form-control">
          <label class="label label-text text-xs">Auth Mode</label>
          <select
            class="select select-bordered select-sm w-full"
            name={@form[:auth_mode].name}
            id={@form[:auth_mode].id}
          >
            <option value="api_key" selected={(@form[:auth_mode].value || "api_key") == "api_key"}>
              API Key
            </option>
            <option value="oauth" selected={@form[:auth_mode].value == "oauth"}>OAuth Token</option>
          </select>
        </div>

        <%= if (@form[:auth_mode].value || "api_key") == "api_key" do %>
          <div class="form-control">
            <label class="label label-text text-xs">API Key</label>
            <input
              type="password"
              class="input input-bordered input-sm w-full"
              name={@form[:api_key].name}
              id={@form[:api_key].id}
              value={@form[:api_key].value}
              placeholder="sk-ant-..."
            />
          </div>
        <% else %>
          <div class="form-control">
            <label class="label label-text text-xs">OAuth Token</label>
            <input
              type="password"
              class="input input-bordered input-sm w-full"
              name={@form[:oauth_token].name}
              id={@form[:oauth_token].id}
              value={@form[:oauth_token].value}
              placeholder="oauth-token-..."
            />
          </div>
        <% end %>
      </div>

      <div class="flex gap-2 mt-3">
        <button type="submit" class="btn btn-primary btn-xs">Save</button>
        <button type="button" phx-click="cancel_ephemeral" class="btn btn-ghost btn-xs">
          Cancel
        </button>
      </div>
    </.form>
    """
  end

  attr :skills, :list, required: true
  attr :skill_form, :any, required: true

  defp skills_tab(assigns) do
    defaults = Skills.defaults()
    present_names = MapSet.new(assigns.skills, & &1.name)
    missing_defaults = Enum.reject(defaults, fn d -> d["name"] in present_names end)
    built_in = Enum.filter(assigns.skills, & &1.built_in)
    custom = Enum.reject(assigns.skills, & &1.built_in)

    assigns =
      assign(assigns, built_in: built_in, custom: custom, missing_defaults: missing_defaults)

    ~H"""
    <div>
      <p class="text-sm text-base-content/60 mb-4">
        Skills are prompt files written into every agent's workspace. They define capabilities like creating follow-up issues.
      </p>

      <%!-- Built-in skills --%>
      <%= for skill <- @built_in do %>
        <div class="bg-base-300 rounded p-3 mb-2">
          <div class="flex items-center justify-between mb-1">
            <div class="flex items-center gap-2">
              <span class="font-mono text-sm font-medium">{skill.name}</span>
              <span class="badge badge-primary badge-xs">built-in</span>
            </div>
            <button
              type="button"
              phx-click="delete_skill"
              phx-value-id={skill.id}
              class="btn btn-ghost btn-xs text-warning"
              data-confirm="Disable this built-in skill?"
            >
              Disable
            </button>
          </div>
          <details class="mt-1">
            <summary class="text-xs text-base-content/50 cursor-pointer">View content</summary>
            <pre class="text-xs mt-2 whitespace-pre-wrap opacity-60">{String.trim(skill.content)}</pre>
          </details>
        </div>
      <% end %>

      <%!-- Disabled defaults that can be re-enabled --%>
      <%= for default <- @missing_defaults do %>
        <div class="bg-base-300/50 rounded p-3 mb-2 border border-dashed border-base-300">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="font-mono text-sm font-medium opacity-50">{default["name"]}</span>
              <span class="badge badge-ghost badge-xs">disabled</span>
            </div>
            <button
              type="button"
              phx-click="restore_skill"
              phx-value-name={default["name"]}
              class="btn btn-ghost btn-xs"
            >
              Enable
            </button>
          </div>
        </div>
      <% end %>

      <%!-- Custom skills --%>
      <%= for skill <- @custom do %>
        <div class="bg-base-300 rounded p-3 mb-2">
          <div class="flex items-center justify-between mb-1">
            <span class="font-mono text-sm font-medium">{skill.name}</span>
            <button
              type="button"
              phx-click="delete_skill"
              phx-value-id={skill.id}
              class="btn btn-ghost btn-xs text-error"
              data-confirm="Delete this skill?"
            >
              Remove
            </button>
          </div>
          <details class="mt-1">
            <summary class="text-xs text-base-content/50 cursor-pointer">View content</summary>
            <pre class="text-xs mt-2 whitespace-pre-wrap opacity-60">{String.trim(skill.content)}</pre>
          </details>
        </div>
      <% end %>

      <%!-- New skill form --%>
      <%= if @skill_form do %>
        <div class="card bg-base-200 mt-4">
          <div class="card-body">
            <h3 class="card-title text-sm">New Skill</h3>
            <.form for={@skill_form} phx-submit="save_skill">
              <div class="space-y-3">
                <div class="form-control">
                  <label class="label"><span class="label-text">Name</span></label>
                  <input
                    type="text"
                    class="input input-bordered input-sm w-full font-mono"
                    name="skill[name]"
                    value={@skill_form[:name].value}
                    placeholder="my-skill-name"
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Content</span></label>
                  <textarea
                    class="textarea textarea-bordered w-full font-mono text-xs"
                    rows="8"
                    name="skill[content]"
                    placeholder="---\nname: my-skill\ndescription: What this skill does\nuser-invocable: false\n---\n\nSkill instructions here..."
                  >{@skill_form[:content].value}</textarea>
                </div>
              </div>
              <div class="flex gap-2 mt-4">
                <button type="submit" class="btn btn-primary btn-sm">Save Skill</button>
                <button type="button" phx-click="cancel_skill" class="btn btn-ghost btn-sm">
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% else %>
        <button type="button" phx-click="new_skill" class="btn btn-ghost btn-sm mt-2">
          + Add custom skill
        </button>
      <% end %>
    </div>
    """
  end

  attr :form, :any, required: true

  defp execution_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="form-control">
        <label class="label"><span class="label-text">Execution Backend</span></label>
        <select
          class="select select-bordered w-full"
          name={@form[:execution_backend].name}
          id={@form[:execution_backend].id}
        >
          <option value="local" selected={(@form[:execution_backend].value || "local") == "local"}>
            Local
          </option>
          <option value="sprites" selected={@form[:execution_backend].value == "sprites"}>
            Sprites
          </option>
        </select>
      </div>

      <%= if @form[:execution_backend].value == "sprites" do %>
        <div class="form-control">
          <label class="label"><span class="label-text">Sprites Token</span></label>
          <input
            type="password"
            class="input input-bordered w-full"
            name={@form[:execution_sprites_token].name}
            id={@form[:execution_sprites_token].id}
            value={@form[:execution_sprites_token].value}
          />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">Sprites Organization (optional)</span></label>
          <input
            type="text"
            class="input input-bordered w-full"
            name={@form[:execution_sprites_org].name}
            id={@form[:execution_sprites_org].id}
            value={@form[:execution_sprites_org].value}
          />
        </div>
      <% end %>
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

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp normalize_agent_params(params), do: params

  defp refresh_agent_lists(socket, scope) do
    assign(socket, :agents, Settings.list_agents(scope))
  end
end
