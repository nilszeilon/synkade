defmodule SynkadeWeb.SettingsLive do
  use SynkadeWeb, :live_view

  alias Synkade.Settings
  alias Synkade.Settings.ConnectionTest, as: ConnTest

  @impl true
  def mount(_params, _session, socket) do
    setting = Settings.get_settings()
    changeset = Settings.change_settings(setting)

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:setting, setting)
     |> assign(:active_tab, "github")
     |> assign(:connection_status, nil)
     |> assign(:connection_testing, false)
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
    auth_mode = form_data["github_auth_mode"] || "pat"

    lv = self()

    Task.start(fn ->
      result =
        case auth_mode do
          "pat" ->
            token = form_data["github_pat"] || ""
            endpoint = form_data["github_endpoint"]
            ConnTest.test_pat(token, endpoint)

          "app" ->
            app_id = form_data["github_app_id"] || ""
            pem = form_data["github_private_key"] || ""
            endpoint = form_data["github_endpoint"]
            ConnTest.test_app(app_id, pem, endpoint)
        end

      send(lv, {:connection_result, result})
    end)

    {:noreply, socket}
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
    <Layouts.app flash={@flash}>
      <div class="max-w-3xl mx-auto px-4 py-6">
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
        </div>

        <.form for={@form} phx-change="validate" phx-submit="save">
          <div class={if @active_tab != "github", do: "hidden"}>
            <.github_tab form={@form} connection_status={@connection_status} connection_testing={@connection_testing} />
          </div>

          <div class={if @active_tab != "agents", do: "hidden"}>
            <.agents_tab form={@form} />
          </div>

          <div class="mt-6">
            <button type="submit" class="btn btn-primary">Save Settings</button>
          </div>
        </.form>
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
        <label class="label"><span class="label-text">Auth Mode</span></label>
        <select class="select select-bordered w-full" name={@form[:github_auth_mode].name} id={@form[:github_auth_mode].id}>
          <option value="pat" selected={@form[:github_auth_mode].value == "pat"}>Personal Access Token</option>
          <option value="app" selected={@form[:github_auth_mode].value == "app"}>GitHub App</option>
        </select>
      </div>

      <%= if (@form[:github_auth_mode].value || "pat") == "pat" do %>
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
          <label class="label"><span class="label-text">Repository</span></label>
          <input
            type="text"
            class="input input-bordered w-full"
            name={@form[:github_repo].name}
            id={@form[:github_repo].id}
            value={@form[:github_repo].value}
            placeholder="owner/repo"
          />
          <.field_error field={@form[:github_repo]} />
        </div>
      <% else %>
        <div class="form-control">
          <label class="label"><span class="label-text">App ID</span></label>
          <input
            type="text"
            class="input input-bordered w-full"
            name={@form[:github_app_id].name}
            id={@form[:github_app_id].id}
            value={@form[:github_app_id].value}
            placeholder="123456"
          />
          <.field_error field={@form[:github_app_id]} />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">Private Key (PEM)</span></label>
          <textarea
            class="textarea textarea-bordered w-full font-mono text-xs"
            rows="6"
            name={@form[:github_private_key].name}
            id={@form[:github_private_key].id}
            placeholder="-----BEGIN RSA PRIVATE KEY-----"
          >{@form[:github_private_key].value}</textarea>
          <.field_error field={@form[:github_private_key]} />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">Webhook Secret</span></label>
          <input
            type="password"
            class="input input-bordered w-full"
            name={@form[:github_webhook_secret].name}
            id={@form[:github_webhook_secret].id}
            value={@form[:github_webhook_secret].value}
          />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">Installation ID (optional)</span></label>
          <input
            type="text"
            class="input input-bordered w-full"
            name={@form[:github_installation_id].name}
            id={@form[:github_installation_id].id}
            value={@form[:github_installation_id].value}
          />
        </div>
      <% end %>

      <div class="form-control">
        <label class="label"><span class="label-text">API Endpoint (optional)</span></label>
        <input
          type="text"
          class="input input-bordered w-full"
          name={@form[:github_endpoint].name}
          id={@form[:github_endpoint].id}
          value={@form[:github_endpoint].value}
          placeholder="https://api.github.com"
        />
      </div>

      <div class="form-control">
        <label class="label"><span class="label-text">Issue Labels (comma-separated, optional)</span></label>
        <input
          type="text"
          class="input input-bordered w-full"
          name={@form[:tracker_labels].name <> "[]"}
          id={@form[:tracker_labels].id}
          value={Enum.join(@form[:tracker_labels].value || [], ", ")}
          placeholder="synkade, automated"
        />
      </div>

      <div class="flex items-center gap-4 mt-4">
        <button type="button" class="btn btn-outline btn-sm" phx-click="test_connection" disabled={@connection_testing}>
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

  attr :form, :any, required: true

  defp agents_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="form-control">
        <label class="label"><span class="label-text">Agent Kind</span></label>
        <select class="select select-bordered w-full" name={@form[:agent_kind].name} id={@form[:agent_kind].id}>
          <option value="claude" selected={@form[:agent_kind].value == "claude"}>Claude</option>
          <option value="codex" selected={@form[:agent_kind].value == "codex"}>Codex</option>
        </select>
      </div>

      <div class="form-control">
        <label class="label"><span class="label-text">API Key</span></label>
        <input
          type="password"
          class="input input-bordered w-full"
          name={@form[:agent_api_key].name}
          id={@form[:agent_api_key].id}
          value={@form[:agent_api_key].value}
          placeholder="sk-ant-..."
        />
      </div>

      <div class="form-control">
        <label class="label"><span class="label-text">Model (optional)</span></label>
        <input
          type="text"
          class="input input-bordered w-full"
          name={@form[:agent_model].name}
          id={@form[:agent_model].id}
          value={@form[:agent_model].value}
          placeholder="claude-sonnet-4-5-20250929"
        />
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div class="form-control">
          <label class="label"><span class="label-text">Max Turns</span></label>
          <input
            type="number"
            class="input input-bordered w-full"
            name={@form[:agent_max_turns].name}
            id={@form[:agent_max_turns].id}
            value={@form[:agent_max_turns].value}
            placeholder="20"
            min="1"
          />
          <.field_error field={@form[:agent_max_turns]} />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">Max Concurrent Agents</span></label>
          <input
            type="number"
            class="input input-bordered w-full"
            name={@form[:agent_max_concurrent].name}
            id={@form[:agent_max_concurrent].id}
            value={@form[:agent_max_concurrent].value}
            placeholder="10"
            min="1"
          />
          <.field_error field={@form[:agent_max_concurrent]} />
        </div>
      </div>

      <div class="form-control">
        <label class="label"><span class="label-text">Allowed Tools (comma-separated)</span></label>
        <input
          type="text"
          class="input input-bordered w-full"
          name={@form[:agent_allowed_tools].name <> "[]"}
          id={@form[:agent_allowed_tools].id}
          value={Enum.join(@form[:agent_allowed_tools].value || [], ", ")}
          placeholder="Read, Edit, Write, Bash, Glob, Grep"
        />
      </div>

      <div class="form-control">
        <label class="label"><span class="label-text">Prompt Template (Liquid, optional)</span></label>
        <textarea
          class="textarea textarea-bordered w-full font-mono text-sm"
          rows="8"
          name={@form[:prompt_template].name}
          id={@form[:prompt_template].id}
        >{@form[:prompt_template].value}</textarea>
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

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
