defmodule SynkadeWeb.SettingsLive.AgentHelpers do
  @moduledoc "Ephemeral agent management event handling and components for SettingsLive."

  use Phoenix.Component

  import SynkadeWeb.Components.AgentBrand

  alias Synkade.Settings
  alias Synkade.Settings.Agent

  @doc "Handle ephemeral agent events. Returns `{:halt, socket}` or `:cont`."
  def handle_agent_event("configure_ephemeral", %{"kind" => kind}, socket) do
    scope = socket.assigns.current_scope
    agent = Settings.get_agent_by_kind(scope, kind) || %Agent{kind: kind}
    changeset = Settings.change_agent(agent)

    {:halt,
     socket
     |> assign(:editing_ephemeral_kind, kind)
     |> assign(:agent_form, to_form(changeset))}
  end

  def handle_agent_event("cancel_ephemeral", _params, socket) do
    {:halt, assign(socket, editing_ephemeral_kind: nil, agent_form: nil)}
  end

  def handle_agent_event("validate_ephemeral", %{"agent" => params}, socket) do
    kind = socket.assigns.editing_ephemeral_kind
    scope = socket.assigns.current_scope
    agent = Settings.get_agent_by_kind(scope, kind) || %Agent{kind: kind}

    changeset =
      Settings.change_agent(agent, normalize_agent_params(Map.put(params, "kind", kind)))
      |> Map.put(:action, :validate)

    {:halt, assign(socket, :agent_form, to_form(changeset))}
  end

  def handle_agent_event("save_ephemeral", %{"agent" => params}, socket) do
    scope = socket.assigns.current_scope
    kind = socket.assigns.editing_ephemeral_kind
    params = normalize_agent_params(Map.put(params, "kind", kind))

    case Settings.upsert_agent(scope, params) do
      {:ok, _agent} ->
        {:halt,
         socket
         |> refresh_agent_lists(scope)
         |> assign(:editing_ephemeral_kind, nil)
         |> assign(:agent_form, nil)
         |> Phoenix.LiveView.put_flash(:info, "#{kind} configured.")}

      {:error, changeset} ->
        {:halt, assign(socket, :agent_form, to_form(changeset))}
    end
  end

  def handle_agent_event("remove_ephemeral", %{"kind" => kind}, socket) do
    scope = socket.assigns.current_scope

    case Settings.get_agent_by_kind(scope, kind) do
      nil ->
        {:halt, socket}

      agent ->
        case Settings.delete_agent(scope, agent) do
          {:ok, _} ->
            {:halt,
             socket
             |> refresh_agent_lists(scope)
             |> Phoenix.LiveView.put_flash(:info, "#{kind} removed.")}

          {:error, _} ->
            {:halt, Phoenix.LiveView.put_flash(socket, :error, "Failed to remove agent.")}
        end
    end
  end

  def handle_agent_event(_event, _params, _socket), do: :cont

  # --- Helpers ---

  def refresh_agent_lists(socket, scope) do
    assign(socket, :agents, Settings.list_agents(scope))
  end

  defp normalize_agent_params(params), do: params

  # --- Components ---

  attr :agents, :list, required: true
  attr :editing_ephemeral_kind, :string, default: nil
  attr :agent_form, :any, required: true
  attr :setting, :any, default: nil

  def agents_tab(assigns) do
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

  def ephemeral_form(assigns) do
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
end
