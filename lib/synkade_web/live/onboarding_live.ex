defmodule SynkadeWeb.OnboardingLive do
  use SynkadeWeb, :live_view

  import Ecto.Query

  alias Synkade.{Repo, Settings}
  alias Synkade.Settings.{Agent, ConnectionTest}

  import SynkadeWeb.Components.AgentBrand

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Settings.onboarding_completed?(scope) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      mode = Synkade.Deployment.mode()
      total_steps = if mode == :hosted, do: 2, else: 3

      setting = Settings.get_settings(scope)
      has_pat = setting != nil and setting.github_pat != nil
      user_id = scope.user.id
      has_agent = Repo.exists?(from a in Agent, where: a.user_id == ^user_id)

      # Resume from where the user left off
      step =
        cond do
          not has_pat -> 1
          not has_agent -> 2
          true -> 3
        end

      settings_changeset = Settings.change_settings(scope, setting)
      agent_changeset = Settings.change_agent(%Agent{})

      {:ok,
       socket
       |> assign(:page_title, "Get Started")
       |> assign(:step, step)
       |> assign(:total_steps, total_steps)
       |> assign(:mode, mode)
       |> assign(:setting, setting)
       |> assign(:settings_form, to_form(settings_changeset))
       |> assign(:connection_status, nil)
       |> assign(:testing_connection, false)
       |> assign(:pat_saved, has_pat)
       |> assign(:agent_form, to_form(agent_changeset))
       |> assign(:agent_created, nil)
       |> assign(:selected_backend, (setting && setting.execution_backend) || "local")}
    end
  end

  # --- Step 1: GitHub PAT ---

  @impl true
  def handle_event("validate_settings", %{"setting" => params}, socket) do
    changeset =
      Settings.change_settings(socket.assigns.current_scope, socket.assigns.setting, params)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:settings_form, to_form(changeset))
      |> assign(:selected_backend, params["execution_backend"] || socket.assigns.selected_backend)

    {:noreply, socket}
  end

  @impl true
  def handle_event("test_connection", _params, socket) do
    form_data = socket.assigns.settings_form.params || %{}
    token = (form_data["github_pat"] || "") |> String.trim()

    if token == "" do
      {:noreply, put_flash(socket, :error, "Please enter a Personal Access Token.")}
    else
      socket = assign(socket, testing_connection: true, connection_status: nil)
      lv = self()

      Task.start(fn ->
        result = ConnectionTest.test_pat(token, nil)
        send(lv, {:connection_result, result, form_data})
      end)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_pat", %{"setting" => params}, socket) do
    if socket.assigns.pat_saved do
      {:noreply, socket}
    else
      token = (params["github_pat"] || "") |> String.trim()

      if token == "" do
        {:noreply, put_flash(socket, :error, "Please enter a Personal Access Token.")}
      else
        socket = assign(socket, testing_connection: true, connection_status: nil)
        lv = self()

        Task.start(fn ->
          result = ConnectionTest.test_pat(token, nil)
          send(lv, {:pat_save_result, result, params})
        end)

        {:noreply, socket}
      end
    end
  end

  # --- Step 2: Agent ---

  @impl true
  def handle_event("select_agent_kind", %{"kind" => kind}, socket) do
    current_params = socket.assigns.agent_form.params || %{}
    params = Map.put(current_params, "kind", kind)

    changeset =
      Settings.change_agent(%Agent{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :agent_form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate_agent", %{"agent" => params}, socket) do
    changeset =
      Settings.change_agent(%Agent{}, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :agent_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_agent", %{"agent" => params}, socket) do
    scope = socket.assigns.current_scope

    case Settings.upsert_agent(scope, params) do
      {:ok, agent} ->
        next_step = socket.assigns.step + 1

        socket =
          socket
          |> assign(:agent_created, agent)
          |> put_flash(:info, "Agent connected.")

        if next_step > socket.assigns.total_steps do
          {:noreply, push_navigate(socket, to: ~p"/projects/new")}
        else
          {:noreply, assign(socket, :step, next_step)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :agent_form, to_form(changeset))}
    end
  end

  # --- Step 3: Backend ---

  @impl true
  def handle_event("save_backend", %{"setting" => params}, socket) do
    scope = socket.assigns.current_scope

    case Settings.save_settings(scope, params) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> put_flash(:info, "Setup complete!")
         |> push_navigate(to: ~p"/projects/new")}

      {:error, changeset} ->
        {:noreply, assign(socket, :settings_form, to_form(changeset))}
    end
  end

  # --- Navigation ---

  @impl true
  def handle_event("continue", _params, socket) do
    next_step = socket.assigns.step + 1

    if next_step > socket.assigns.total_steps do
      {:noreply, push_navigate(socket, to: ~p"/projects/new")}
    else
      {:noreply, assign(socket, :step, next_step)}
    end
  end

  @impl true
  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :step, max(socket.assigns.step - 1, 1))}
  end

  # --- Info handlers ---

  @impl true
  def handle_info({:connection_result, result, params}, socket) do
    scope = socket.assigns.current_scope

    case result do
      {:ok, _msg} ->
        case Settings.save_settings(scope, params) do
          {:ok, setting} ->
            {:noreply,
             socket
             |> assign(:setting, setting)
             |> assign(:pat_saved, true)
             |> assign(:testing_connection, false)
             |> assign(:connection_status, result)
             |> assign(:settings_form, to_form(Settings.change_settings(scope, setting)))
             |> put_flash(:info, "GitHub connected.")}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:testing_connection, false)
             |> assign(:connection_status, result)
             |> put_flash(:error, "Connection valid but failed to save. Try Save & Continue.")}
        end

      {:error, _reason} ->
        {:noreply, assign(socket, testing_connection: false, connection_status: result)}
    end
  end

  @impl true
  def handle_info({:pat_save_result, result, params}, socket) do
    scope = socket.assigns.current_scope

    case result do
      {:ok, _msg} ->
        case Settings.save_settings(scope, params) do
          {:ok, setting} ->
            next_step = socket.assigns.step + 1

            socket =
              socket
              |> assign(:setting, setting)
              |> assign(:pat_saved, true)
              |> assign(:testing_connection, false)
              |> assign(:connection_status, result)
              |> assign(:settings_form, to_form(Settings.change_settings(scope, setting)))
              |> put_flash(:info, "GitHub connected.")

            if next_step > socket.assigns.total_steps do
              {:noreply, push_navigate(socket, to: ~p"/projects/new")}
            else
              {:noreply, assign(socket, :step, next_step)}
            end

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:testing_connection, false)
             |> assign(:settings_form, to_form(changeset))}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:testing_connection, false)
         |> assign(:connection_status, result)
         |> put_flash(:error, "Invalid token: #{reason}")}
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100 flex items-center justify-center p-4">
      <SynkadeWeb.Layouts.flash_group flash={@flash} />
      <div class="w-full max-w-lg">
        <div class="text-center mb-8">
          <h1 class="text-2xl font-bold">Get Started</h1>
          <p class="text-base-content/60 mt-1">Set up the essentials to start using Synkade</p>
        </div>

        <.step_indicator step={@step} total_steps={@total_steps} />

        <div class="card bg-base-200 shadow-lg">
          <div class="card-body">
            <%= case @step do %>
              <% 1 -> %>
                <.step_github
                  form={@settings_form}
                  connection_status={@connection_status}
                  testing_connection={@testing_connection}
                  pat_saved={@pat_saved}
                />
              <% 2 -> %>
                <.step_agent
                  form={@agent_form}
                  agent_created={@agent_created}
                />
              <% 3 -> %>
                <.step_backend
                  form={@settings_form}
                  selected_backend={@selected_backend}
                />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :step, :integer, required: true
  attr :total_steps, :integer, required: true

  defp step_indicator(assigns) do
    ~H"""
    <ul class="steps steps-horizontal w-full mb-6">
      <li class={["step", @step >= 1 && "step-primary"]}>GitHub</li>
      <li class={["step", @step >= 2 && "step-primary"]}>Agent</li>
      <li :if={@total_steps == 3} class={["step", @step >= 3 && "step-primary"]}>Backend</li>
    </ul>
    """
  end

  attr :form, :any, required: true
  attr :connection_status, :any, default: nil
  attr :testing_connection, :boolean, default: false
  attr :pat_saved, :boolean, default: false

  defp step_github(assigns) do
    ~H"""
    <h2 class="card-title text-lg mb-1">Connect GitHub</h2>
    <p class="text-sm text-base-content/60 mb-4">
      Synkade needs a GitHub Personal Access Token to manage repositories and issues.
    </p>

    <.form for={@form} phx-change="validate_settings" phx-submit="save_pat">
      <div class="space-y-4">
        <div class="form-control">
          <label class="label"><span class="label-text">Personal Access Token</span></label>
          <%= if @pat_saved do %>
            <input
              type="password"
              class="input input-bordered w-full"
              value="••••••••••••"
              disabled
            />
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

        <div class="flex items-center gap-3">
          <button
            type="button"
            class="btn btn-outline btn-sm"
            phx-click="test_connection"
            disabled={@testing_connection}
          >
            <%= if @testing_connection do %>
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

      <div class="flex justify-end mt-6">
        <%= if @pat_saved do %>
          <button type="button" phx-click="continue" class="btn btn-primary">Continue</button>
        <% else %>
          <button type="submit" class="btn btn-primary" disabled={@testing_connection}>
            <%= if @testing_connection do %>
              <span class="loading loading-spinner loading-xs"></span> Validating...
            <% else %>
              Save & Continue
            <% end %>
          </button>
        <% end %>
      </div>
    </.form>
    """
  end

  attr :form, :any, required: true
  attr :agent_created, :any, default: nil

  defp step_agent(assigns) do
    ~H"""
    <h2 class="card-title text-lg mb-1">Connect an Agent</h2>
    <p class="text-sm text-base-content/60 mb-4">
      Choose a coding agent and provide its credentials.
    </p>

    <%= if @agent_created do %>
      <div class="flex flex-col items-center gap-4 py-4">
        <div class="text-success text-4xl">
          <.icon name="hero-check-circle" class="w-12 h-12" />
        </div>
        <p class="text-center">
          <span class="font-semibold">{brand_label(@agent_created.kind)}</span> connected.
        </p>
        <button type="button" phx-click="continue" class="btn btn-primary">Continue</button>
      </div>
    <% else %>
      <.form for={@form} phx-change="validate_agent" phx-submit="save_agent">
        <div class="space-y-4">
          <div class="form-control">
            <label class="label"><span class="label-text">Agent</span></label>
            <input type="hidden" name={@form[:kind].name} value={@form[:kind].value || "claude"} />
            <div class="grid grid-cols-3 gap-2">
              <.agent_card kind="claude" selected={(@form[:kind].value || "claude") == "claude"} />
              <.agent_card kind="opencode" selected={@form[:kind].value == "opencode"} />
              <.agent_card kind="codex" selected={@form[:kind].value == "codex"} />
            </div>
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
        </div>

        <div class="flex justify-between mt-6">
          <button type="button" phx-click="back" class="btn btn-ghost">Back</button>
          <button type="submit" class="btn btn-primary">Connect</button>
        </div>
      </.form>
    <% end %>
    """
  end

  attr :form, :any, required: true
  attr :selected_backend, :string, default: "local"

  defp step_backend(assigns) do
    ~H"""
    <h2 class="card-title text-lg mb-1">Execution Backend</h2>
    <p class="text-sm text-base-content/60 mb-4">
      Choose where your agents run code. <strong>Local</strong> runs on this machine.
      <strong>Sprites</strong> runs in isolated cloud containers.
    </p>

    <.form for={@form} phx-change="validate_settings" phx-submit="save_backend">
      <div class="space-y-4">
        <div class="form-control">
          <label class="label"><span class="label-text">Backend</span></label>
          <select
            class="select select-bordered w-full"
            name={@form[:execution_backend].name}
            id={@form[:execution_backend].id}
          >
            <option value="local" selected={@selected_backend == "local"}>
              Local
            </option>
            <option value="sprites" selected={@selected_backend == "sprites"}>
              Sprites
            </option>
          </select>
        </div>

        <%= if @selected_backend == "sprites" do %>
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

      <div class="flex justify-between mt-6">
        <button type="button" phx-click="back" class="btn btn-ghost">Back</button>
        <button type="submit" class="btn btn-primary">Finish Setup</button>
      </div>
    </.form>
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
