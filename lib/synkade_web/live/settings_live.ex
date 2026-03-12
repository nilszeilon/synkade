defmodule SynkadeWeb.SettingsLive do
  use SynkadeWeb, :live_view

  alias Synkade.Orchestrator
  alias Synkade.Settings
  alias Synkade.Settings.{Agent, ConnectionTest}

  @impl true
  def mount(_params, _session, socket) do
    setting = Settings.get_settings()
    changeset = Settings.change_settings(setting)
    orc_state = Orchestrator.get_state()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:setting, setting)
     |> assign(:nav_active_tab, :settings)
     |> assign(:current_project, nil)
     |> assign(:projects, orc_state.projects)
     |> assign(:running, orc_state.running)
     |> assign(:active_tab, "github")
     |> assign(:connection_status, nil)
     |> assign(:connection_testing, false)
     |> assign(:agents, Settings.list_agents())
     |> assign(:agent_editing, nil)
     |> assign(:agent_form, nil)
     |> assign(:agent_token_visible, MapSet.new())
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("validate", %{"setting" => params}, socket) do
    changeset =
      Settings.change_settings(socket.assigns.setting, params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"setting" => params}, socket) do
    case Settings.save_settings(params) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> assign(:setting, setting)
         |> assign_form(Settings.change_settings(setting))
         |> put_flash(:info, "Settings saved.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("test_connection", _params, socket) do
    socket = assign(socket, connection_testing: true, connection_status: nil)
    form_data = socket.assigns.form.params || %{}

    lv = self()

    Task.start(fn ->
      token = form_data["github_pat"] || ""
      result = ConnectionTest.test_pat(token, nil)
      send(lv, {:connection_result, result})
    end)

    {:noreply, socket}
  end

  # --- Agent events ---

  @impl true
  def handle_event("new_agent", _params, socket) do
    changeset = Settings.change_agent(%Agent{})

    {:noreply,
     socket
     |> assign(:agent_editing, :new)
     |> assign(:agent_form, to_form(changeset))}
  end

  @impl true
  def handle_event("edit_agent", %{"id" => id}, socket) do
    agent = Settings.get_agent!(id)
    changeset = Settings.change_agent(agent)

    {:noreply,
     socket
     |> assign(:agent_editing, agent)
     |> assign(:agent_form, to_form(changeset))}
  end

  @impl true
  def handle_event("cancel_agent", _params, socket) do
    {:noreply, assign(socket, agent_editing: nil, agent_form: nil)}
  end

  @impl true
  def handle_event("validate_agent", %{"agent" => params}, socket) do
    agent =
      case socket.assigns.agent_editing do
        :new -> %Agent{}
        %Agent{} = a -> a
      end

    changeset =
      Settings.change_agent(agent, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :agent_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_agent", %{"agent" => params}, socket) do
    result =
      case socket.assigns.agent_editing do
        :new -> Settings.create_agent(params)
        %Agent{} = agent -> Settings.update_agent(agent, params)
      end

    case result do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> assign(:agents, Settings.list_agents())
         |> assign(:agent_editing, nil)
         |> assign(:agent_form, nil)
         |> put_flash(:info, "Agent saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :agent_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_agent", %{"id" => id}, socket) do
    agent = Settings.get_agent!(id)

    case Settings.delete_agent(agent) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:agents, Settings.list_agents())
         |> assign(:agent_editing, nil)
         |> assign(:agent_form, nil)
         |> put_flash(:info, "Agent deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete agent.")}
    end
  end

  @impl true
  def handle_event("generate_agent_token", %{"id" => id}, socket) do
    agent = Settings.get_agent!(id)

    case Settings.generate_agent_token(agent) do
      {:ok, _plaintext} ->
        {:noreply,
         socket
         |> assign(:agents, Settings.list_agents())
         |> update(:agent_token_visible, &MapSet.put(&1, id))
         |> put_flash(:info, "Token regenerated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to generate token.")}
    end
  end

  @impl true
  def handle_event("show_agent_token", %{"id" => id}, socket) do
    {:noreply, update(socket, :agent_token_visible, &MapSet.put(&1, id))}
  end

  @impl true
  def handle_event("hide_agent_token", %{"id" => id}, socket) do
    {:noreply, update(socket, :agent_token_visible, &MapSet.delete(&1, id))}
  end

  @impl true
  def handle_event("revoke_agent_token", %{"id" => id}, socket) do
    agent = Settings.get_agent!(id)

    case Settings.revoke_agent_token(agent) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:agents, Settings.list_agents())
         |> update(:agent_token_visible, &MapSet.delete(&1, id))
         |> put_flash(:info, "Token revoked.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke token.")}
    end
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
      active_tab={@nav_active_tab}
      current_project={@current_project}
    >
      <div class="max-w-3xl mx-auto px-6 py-6">
        <h1 class="text-2xl font-bold mb-6">Settings</h1>

        <div role="tablist" class="tabs tabs-boxed mb-6">
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
            class={"tab #{if @active_tab == "agents", do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="agents"
          >
            Agents
          </button>
          <button
            role="tab"
            class={"tab #{if @active_tab == "execution", do: "tab-active"}"}
            phx-click="switch_tab"
            phx-value-tab="execution"
          >
            Execution
          </button>
        </div>

        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class={if @active_tab != "github", do: "hidden"}>
            <.github_tab
              form={@form}
              connection_status={@connection_status}
              connection_testing={@connection_testing}
            />
          </div>

          <div class={if @active_tab != "execution", do: "hidden"}>
            <.execution_tab form={@form} />
          </div>

          <div :if={@active_tab in ["github", "execution"]} class="mt-6">
            <button type="submit" class="btn btn-primary">Save Settings</button>
          </div>
        </.form>

        <div class={if @active_tab != "agents", do: "hidden"}>
          <.agents_tab
            agents={@agents}
            agent_editing={@agent_editing}
            agent_form={@agent_form}
            agent_token_visible={@agent_token_visible}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :form, :any, required: true
  attr :connection_status, :any, default: nil
  attr :connection_testing, :boolean, default: false

  defp github_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="form-control">
        <label class="label"><span class="label-text">Personal Access Token</span></label>
        <input
          type="password"
          class="input input-bordered w-full"
          name={@form[:github_pat].name}
          id={@form[:github_pat].id}
          value={@form[:github_pat].value}
          placeholder="ghp_..."
        />
        <.field_error field={@form[:github_pat]} />
      </div>

      <div class="form-control">
        <label class="label"><span class="label-text">Webhook Secret (optional)</span></label>
        <input
          type="password"
          class="input input-bordered w-full"
          name={@form[:github_webhook_secret].name}
          id={@form[:github_webhook_secret].id}
          value={@form[:github_webhook_secret].value}
        />
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
  attr :agent_editing, :any, required: true
  attr :agent_form, :any, required: true
  attr :agent_token_visible, :any, required: true

  defp agents_tab(assigns) do
    ~H"""
    <div>
      <%= if @agent_editing do %>
        <.agent_form form={@agent_form} editing={@agent_editing} />
      <% else %>
        <div class="flex items-center justify-between mb-4">
          <p class="text-sm text-base-content/60">Manage agent configurations for your projects.</p>
          <button type="button" phx-click="new_agent" class="btn btn-primary btn-sm">
            New Agent
          </button>
        </div>

        <%= if @agents == [] do %>
          <div class="text-center py-12 text-base-content/50">
            <p>No agents configured yet.</p>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Kind</th>
                  <th>Model</th>
                  <th>Token</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= for agent <- @agents do %>
                  <tr>
                    <td class="font-medium">{agent.name}</td>
                    <td class="text-sm text-base-content/60">{agent.kind}</td>
                    <td class="text-sm text-base-content/60">{agent.model || "-"}</td>
                    <td>
                      <%= if agent.api_token_hash do %>
                        <%= if MapSet.member?(@agent_token_visible, agent.id) do %>
                          <code class="text-xs break-all select-all">{agent.api_token}</code>
                        <% else %>
                          <span class="badge badge-success badge-sm">Active</span>
                        <% end %>
                      <% else %>
                        <span class="badge badge-ghost badge-sm">None</span>
                      <% end %>
                    </td>
                    <td class="text-right space-x-1">
                      <%= if agent.api_token_hash do %>
                        <%= if MapSet.member?(@agent_token_visible, agent.id) do %>
                          <button
                            type="button"
                            phx-click="hide_agent_token"
                            phx-value-id={agent.id}
                            class="btn btn-ghost btn-xs"
                          >
                            Hide
                          </button>
                        <% else %>
                          <button
                            type="button"
                            phx-click="show_agent_token"
                            phx-value-id={agent.id}
                            class="btn btn-ghost btn-xs"
                          >
                            Show
                          </button>
                        <% end %>
                        <button
                          type="button"
                          phx-click="generate_agent_token"
                          phx-value-id={agent.id}
                          class="btn btn-ghost btn-xs"
                          data-confirm="Regenerate token? The current token will be invalidated."
                        >
                          Regenerate
                        </button>
                        <button
                          type="button"
                          phx-click="revoke_agent_token"
                          phx-value-id={agent.id}
                          class="btn btn-ghost btn-xs text-warning"
                          data-confirm="Revoke this agent's API token?"
                        >
                          Revoke
                        </button>
                      <% else %>
                        <button
                          type="button"
                          phx-click="generate_agent_token"
                          phx-value-id={agent.id}
                          class="btn btn-ghost btn-xs"
                        >
                          Generate Token
                        </button>
                      <% end %>
                      <button
                        type="button"
                        phx-click="edit_agent"
                        phx-value-id={agent.id}
                        class="btn btn-ghost btn-xs"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        phx-click="delete_agent"
                        phx-value-id={agent.id}
                        class="btn btn-ghost btn-xs text-error"
                        data-confirm="Delete this agent?"
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
      <% end %>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :editing, :any, required: true

  defp agent_form(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <h2 class="card-title text-lg">
          {if @editing == :new, do: "New Agent", else: "Edit Agent"}
        </h2>

        <.form for={@form} phx-change="validate_agent" phx-submit="save_agent">
          <div class="space-y-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                class="input input-bordered w-full"
                name={@form[:name].name}
                id={@form[:name].id}
                value={@form[:name].value}
                placeholder="my-agent"
              />
              <.field_error field={@form[:name]} />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Kind</span></label>
              <select
                class="select select-bordered w-full"
                name={@form[:kind].name}
                id={@form[:kind].id}
              >
                <option value="claude" selected={(@form[:kind].value || "claude") == "claude"}>
                  Claude
                </option>
                <option value="codex" selected={@form[:kind].value == "codex"}>Codex</option>
                <option value="opencode" selected={@form[:kind].value == "opencode"}>OpenCode</option>
              </select>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Auth Mode</span></label>
              <select
                class="select select-bordered w-full"
                name={@form[:auth_mode].name}
                id={@form[:auth_mode].id}
              >
                <option value="api_key" selected={(@form[:auth_mode].value || "api_key") == "api_key"}>
                  API Key
                </option>
                <option value="oauth" selected={@form[:auth_mode].value == "oauth"}>
                  OAuth Token
                </option>
              </select>
            </div>

            <%= if (@form[:auth_mode].value || "api_key") == "api_key" do %>
              <div class="form-control">
                <label class="label"><span class="label-text">API Key</span></label>
                <input
                  type="password"
                  class="input input-bordered w-full"
                  name={@form[:api_key].name}
                  id={@form[:api_key].id}
                  value={@form[:api_key].value}
                  placeholder="sk-ant-..."
                />
              </div>
            <% else %>
              <div class="form-control">
                <label class="label"><span class="label-text">OAuth Token</span></label>
                <input
                  type="password"
                  class="input input-bordered w-full"
                  name={@form[:oauth_token].name}
                  id={@form[:oauth_token].id}
                  value={@form[:oauth_token].value}
                  placeholder="oauth-token-..."
                />
              </div>
            <% end %>

            <div class="form-control">
              <label class="label"><span class="label-text">Model (optional)</span></label>
              <input
                type="text"
                class="input input-bordered w-full"
                name={@form[:model].name}
                id={@form[:model].id}
                value={@form[:model].value}
                placeholder="claude-sonnet-4-5-20250929"
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Max Turns</span></label>
              <input
                type="number"
                class="input input-bordered w-full"
                name={@form[:max_turns].name}
                id={@form[:max_turns].id}
                value={@form[:max_turns].value}
                placeholder="20"
                min="1"
              />
              <.field_error field={@form[:max_turns]} />
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Allowed Tools (comma-separated)</span>
              </label>
              <input
                type="text"
                class="input input-bordered w-full"
                name={@form[:allowed_tools].name <> "[]"}
                id={@form[:allowed_tools].id}
                value={Enum.join(@form[:allowed_tools].value || [], ", ")}
                placeholder="Read, Edit, Write, Bash, Glob, Grep"
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">System Prompt (optional)</span></label>
              <textarea
                class="textarea textarea-bordered w-full font-mono text-sm"
                rows="6"
                name={@form[:system_prompt].name}
                id={@form[:system_prompt].id}
              >{@form[:system_prompt].value}</textarea>
            </div>
          </div>

          <div class="flex gap-2 mt-6">
            <button type="submit" class="btn btn-primary">Save Agent</button>
            <button type="button" phx-click="cancel_agent" class="btn btn-ghost">Cancel</button>
          </div>
        </.form>
      </div>
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
end
