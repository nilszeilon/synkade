defmodule SynkadeWeb.IssuesLive do
  use SynkadeWeb, :live_view

  alias Synkade.{Issues, Orchestrator, Settings}
  alias Synkade.Issues.{Issue, DispatchParser}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Issues.pubsub_topic())
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic())
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
      |> assign(:state_filter, nil)
      |> assign(:project_names, Map.new(projects, &{&1.id, &1.name}))
      |> assign(:issues, [])
      |> assign(:selected_issue, nil)
      |> assign(:show_form, false)
      |> assign(:form, nil)
      |> assign(:form_project_id, nil)
      |> assign(:collapsed, MapSet.new())
      |> assign(:agents, Settings.list_agents())
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

    {:noreply, socket}
  end

  @impl true
  def handle_info({:issues_updated}, socket) do
    {:noreply, load_issues(socket)}
  end

  @impl true
  def handle_info({:state_changed, snapshot}, socket) do
    socket = assign(socket, :running, snapshot.running)

    # Update session_id from running entry, or unsubscribe if no longer running
    socket =
      case socket.assigns.session_subscribed do
        nil ->
          socket

        issue_id ->
          running_entry = find_running_entry(snapshot.running, issue_id)

          if running_entry do
            assign(socket, :session_id, running_entry.session_id)
          else
            unsubscribe_session(socket)
          end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:theme_updated, theme}, socket) do
    {:noreply, push_event(socket, "set-theme", %{theme: theme})}
  end

  @impl true
  def handle_info({:agents_updated}, socket) do
    {:noreply, assign(socket, :agents, Settings.list_agents())}
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
    issue = Issues.get_issue!(issue_id)
    ancestors = Issues.ancestor_chain(issue)

    # Unsubscribe from previous session
    socket = unsubscribe_session(socket)

    # Subscribe to agent events if issue is in_progress
    socket =
      if issue.state == "in_progress" do
        running_entry = find_running_entry(socket.assigns.running, issue_id)

        if running_entry do
          topic = Orchestrator.agent_events_topic(issue_id)
          Phoenix.PubSub.subscribe(Synkade.PubSub, topic)
          past_events = Orchestrator.get_issue_events(issue_id)

          socket
          |> assign(:session_events, past_events)
          |> assign(:session_id, running_entry.session_id)
          |> assign(:session_subscribed, issue_id)
        else
          socket
          |> assign(:session_events, [])
          |> assign(:session_id, nil)
        end
      else
        socket
        |> assign(:session_events, [])
        |> assign(:session_id, nil)
      end

    socket =
      socket
      |> assign(:selected_issue, %{issue: issue, ancestors: ancestors})
      |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_detail", _params, socket) do
    socket = unsubscribe_session(socket)
    {:noreply, assign(socket, :selected_issue, nil)}
  end

  @impl true
  def handle_event("new_issue", params, socket) do
    parent_id = params["parent_id"]

    project_id =
      params["project_id"] ||
        case socket.assigns.db_projects do
          [first | _] -> first.id
          [] -> nil
        end

    changeset = Issues.change_issue(%Issue{}, %{parent_id: parent_id})

    socket =
      socket
      |> assign(:show_form, true)
      |> assign(:form, to_form(changeset))
      |> assign(:form_parent_id, parent_id)
      |> assign(:form_project_id, project_id)

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
    project_id = params["project_id"] || socket.assigns.form_project_id

    params =
      params
      |> Map.put("project_id", project_id)
      |> maybe_put_parent(socket.assigns[:form_parent_id])

    case Issues.create_issue(params) do
      {:ok, _issue} ->
        socket =
          socket
          |> assign(:show_form, false)
          |> assign(:form, nil)
          |> load_issues()
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
      {agent_name, instruction} = DispatchParser.parse(message)

      agent_id =
        case agent_name do
          nil ->
            nil

          name ->
            case Settings.get_agent_by_name(name) do
              nil -> nil
              agent -> agent.id
            end
        end

      case Issues.dispatch_issue(issue, instruction, agent_id) do
        {:ok, _} ->
          socket =
            socket
            |> assign(:selected_issue, nil)
            |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
            |> load_issues()
            |> put_flash(
              :info,
              "Issue dispatched" <> if(agent_name, do: " to #{agent_name}", else: "")
            )

          {:noreply, socket}

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
          |> assign(:selected_issue, nil)
          |> load_issues()
          |> put_flash(:info, "Issue deleted")

        {:noreply, socket}

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

  defp issues_path(filter) do
    if filter, do: "/issues?" <> URI.encode_query(%{"filter" => filter}), else: "/issues"
  end

  defp maybe_put_parent(params, nil), do: params
  defp maybe_put_parent(params, parent_id), do: Map.put(params, "parent_id", parent_id)

  defp unsubscribe_session(socket) do
    case socket.assigns.session_subscribed do
      nil ->
        socket

      issue_id ->
        topic = Orchestrator.agent_events_topic(issue_id)
        Phoenix.PubSub.unsubscribe(Synkade.PubSub, topic)

        socket
        |> assign(:session_events, [])
        |> assign(:session_id, nil)
        |> assign(:session_subscribed, nil)
    end
  end

  defp find_running_entry(running, issue_id) do
    Enum.find_value(running, fn {_key, entry} ->
      if entry.issue_id == issue_id, do: entry
    end)
  end

  defp format_relative_time(monotonic_ms) when is_integer(monotonic_ms) do
    elapsed_ms = System.monotonic_time(:millisecond) - monotonic_ms
    elapsed_s = div(elapsed_ms, 1000)

    cond do
      elapsed_s < 5 -> "just now"
      elapsed_s < 60 -> "#{elapsed_s}s ago"
      elapsed_s < 3600 -> "#{div(elapsed_s, 60)}m ago"
      true -> "#{div(elapsed_s, 3600)}h ago"
    end
  end

  defp format_relative_time(_), do: nil

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
                class={["btn btn-xs", if(@state_filter == value, do: "btn-primary", else: "btn-ghost")]}
              >
                {label}
              </button>
            </div>
            <button phx-click="new_issue" class="btn btn-sm btn-primary">
              New Issue
            </button>
          </div>
        </div>

        <!-- New issue form -->
        <div :if={@show_form} class="card bg-base-200 p-4 mb-4">
          <.form for={@form} phx-change="validate_issue" phx-submit="save_issue">
            <div class="flex flex-col gap-3">
              <div :if={length(@db_projects) > 1} class="form-control">
                <select name="issue[project_id]" class="select select-bordered select-sm">
                  <option
                    :for={p <- @db_projects}
                    value={p.id}
                    selected={p.id == @form_project_id}
                  >
                    {p.name}
                  </option>
                </select>
              </div>
              <div class="form-control">
                <textarea
                  name="issue[body]"
                  placeholder={"# Issue title\n\nDescribe the issue..."}
                  class="textarea textarea-bordered textarea-sm w-full font-mono"
                  rows="5"
                  phx-debounce="300"
                >{@form[:body].value}</textarea>
              </div>
              <div class="flex gap-2">
                <button type="submit" class="btn btn-sm btn-primary">Create</button>
                <button type="button" phx-click="cancel_form" class="btn btn-sm btn-ghost">
                  Cancel
                </button>
              </div>
            </div>
          </.form>
        </div>

        <div class="flex gap-4">
          <!-- Issue list -->
          <div class={["flex-1 min-w-0", @selected_issue && "max-w-[60%]"]}>
            <div :if={@issues == []} class="text-base-content/50 text-sm py-8 text-center">
              No issues
            </div>

            <div :for={issue <- @issues} class="mb-1">
              <.issue_flat_row
                issue={issue}
                project_name={Map.get(@project_names, issue.project_id)}
                selected_id={@selected_issue && @selected_issue.issue.id}
              />
            </div>
          </div>

          <!-- Detail panel -->
          <div :if={@selected_issue} class="w-[40%] flex-shrink-0">
            <.issue_detail
              issue={@selected_issue.issue}
              ancestors={@selected_issue.ancestors}
              dispatch_form={@dispatch_form}
              agents={@agents}
              session_events={@session_events}
              session_id={@session_id}
              running_entry={find_running_entry(@running, @selected_issue.issue.id)}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :issue, :map, required: true
  attr :project_name, :string, default: nil
  attr :selected_id, :string, default: nil

  defp issue_flat_row(assigns) do
    ~H"""
    <div
      class={[
        "flex items-center gap-2 py-1.5 px-2 rounded cursor-pointer hover:bg-base-200 group",
        @issue.id == @selected_id && "bg-base-200"
      ]}
      phx-click="select_issue"
      phx-value-id={@issue.id}
    >
      <span :if={@project_name} class="text-xs text-base-content/50 w-24 truncate flex-shrink-0">
        {@project_name}
      </span>
      <span class="text-sm truncate flex-1 min-w-0">{Issue.title(@issue)}</span>
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

  attr :issue, :map, required: true
  attr :ancestors, :list, required: true
  attr :dispatch_form, :any, required: true
  attr :agents, :list, required: true
  attr :session_events, :list, default: []
  attr :session_id, :string, default: nil
  attr :running_entry, :any, default: nil

  defp issue_detail(assigns) do
    ~H"""
    <div class="card bg-base-200 flex flex-col sticky top-4 max-h-[calc(100vh-6rem)]">
      <!-- Header -->
      <div class="flex items-start justify-between p-4 pb-2 flex-shrink-0">
        <div>
          <div class="flex items-center gap-2 mb-1">
            <span class={"badge badge-sm #{state_badge_class(@issue.state)}"}>{@issue.state}</span>
          </div>
          <h2 class="text-lg font-bold">{Issue.title(@issue)}</h2>
        </div>
        <button phx-click="close_detail" class="btn btn-ghost btn-sm btn-circle">x</button>
      </div>
      <!-- Agent status bar -->
      <div
        :if={@running_entry}
        class="mx-4 mb-1 px-3 py-2 bg-info/10 rounded-lg flex items-center gap-2"
      >
        <span class="loading loading-spinner loading-xs text-info"></span>
        <div class="flex-1 min-w-0">
          <p
            :if={@running_entry.last_agent_message && @running_entry.last_agent_message != ""}
            class="text-xs text-base-content/70 truncate"
            title={@running_entry.last_agent_message}
          >
            {@running_entry.last_agent_message}
          </p>
          <p
            :if={!@running_entry.last_agent_message || @running_entry.last_agent_message == ""}
            class="text-xs text-base-content/50"
          >
            Agent running...
          </p>
        </div>
        <span
          :if={@running_entry.last_agent_timestamp}
          class="text-xs text-base-content/40 flex-shrink-0"
        >
          {format_relative_time(@running_entry.last_agent_timestamp)}
        </span>
      </div>

      <!-- Scrollable thread -->
      <div class="overflow-y-auto flex-1 px-4 py-2">
        <!-- Ancestor thread entries -->
        <div :for={ancestor <- @ancestors} class="border-l-2 border-base-300 pl-3 mb-3">
          <p class="text-sm font-semibold text-base-content/70">{Issue.title(ancestor)}</p>
          <p :if={ancestor.body} class="text-xs text-base-content/60 whitespace-pre-wrap mt-1">
            {ancestor.body}
          </p>
          <div :if={ancestor.agent_output} class="mt-1">
            <pre class="text-xs bg-base-300 p-2 rounded overflow-auto max-h-40">{ancestor.agent_output}</pre>
          </div>
        </div>

        <!-- Current issue -->
        <div class="border-l-2 border-primary pl-3 mb-3">
          <p class="text-sm font-semibold">{Issue.title(@issue)}</p>
          <p :if={@issue.body} class="text-xs whitespace-pre-wrap mt-1">
            {@issue.body}
          </p>
          <div :if={@issue.dispatch_message} class="mt-2">
            <p class="text-xs text-base-content/50 mb-1">Dispatch message</p>
            <p class="text-xs italic whitespace-pre-wrap">{@issue.dispatch_message}</p>
          </div>
          <div :if={@issue.agent_output} class="mt-2">
            <pre class="text-xs bg-base-300 p-2 rounded overflow-auto max-h-40">{@issue.agent_output}</pre>
          </div>
        </div>

        <!-- Live session panel (when issue is in_progress and has events) -->
        <div
          :if={@issue.state == "in_progress" && (@session_events != [] || @session_id)}
          class="mb-3"
        >
          <div class="flex items-center justify-between mb-2">
            <p class="text-xs text-base-content/50 font-semibold">Agent Session</p>
            <div :if={@session_id} class="flex items-center gap-1">
              <code class="text-xs text-base-content/40 font-mono">
                {String.slice(@session_id, 0..11)}...
              </code>
              <button
                phx-click="copy_resume"
                class="btn btn-ghost btn-xs"
                title={"claude --resume #{@session_id}"}
              >
                Copy
              </button>
            </div>
          </div>
          <div
            id="session-event-log"
            class="bg-base-300 rounded p-2 max-h-60 overflow-y-auto font-mono text-xs space-y-1"
            phx-hook="AutoScroll"
          >
            <.session_event :for={event <- @session_events} event={event} />
          </div>
          <p :if={@session_events == []} class="text-xs text-base-content/40 text-center py-2">
            Waiting for agent events...
          </p>
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
              {Issue.title(child)}
            </span>
            <span class={"badge badge-xs #{state_badge_class(child.state)} ml-auto"}>
              {child.state}
            </span>
          </div>
        </div>

        <!-- GitHub links -->
        <div :if={@issue.github_issue_url || @issue.github_pr_url} class="mb-3 flex gap-2">
          <a
            :if={@issue.github_issue_url}
            href={@issue.github_issue_url}
            target="_blank"
            class="link link-primary text-xs"
          >
            GitHub Issue
          </a>
          <a
            :if={@issue.github_pr_url}
            href={@issue.github_pr_url}
            target="_blank"
            class="link link-primary text-xs"
          >
            Pull Request
          </a>
        </div>
      </div>

      <!-- Dispatch input + actions -->
      <div class="p-4 pt-2 border-t border-base-300 flex-shrink-0">
        <div :if={@issue.state == "backlog"} class="mb-3">
          <.form for={@dispatch_form} phx-submit="dispatch_issue">
            <div class="flex gap-2">
              <input
                type="text"
                name="dispatch[message]"
                value={@dispatch_form[:message].value}
                placeholder="@agent instructions..."
                class="input input-bordered input-sm flex-1"
                list="agent-names"
                autocomplete="off"
              />
              <button type="submit" class="btn btn-sm btn-primary">Go</button>
            </div>
            <datalist id="agent-names">
              <option :for={agent <- @agents} value={"@#{agent.name} "} />
            </datalist>
          </.form>
        </div>

        <div :if={@issue.state == "awaiting_review" && @issue.github_pr_url} class="mb-3">
          <.form for={@dispatch_form} phx-submit="dispatch_issue">
            <div class="flex gap-2">
              <input
                type="text"
                name="dispatch[message]"
                value={@dispatch_form[:message].value}
                placeholder="@agent merge PR to main..."
                class="input input-bordered input-sm flex-1"
                list="agent-names-merge"
                autocomplete="off"
              />
              <button type="submit" class="btn btn-sm btn-primary">Merge</button>
            </div>
            <datalist id="agent-names-merge">
              <option :for={agent <- @agents} value={"@#{agent.name} "} />
            </datalist>
          </.form>
        </div>

        <div class="flex gap-2">
          <button
            :if={@issue.state == "queued"}
            phx-click="unqueue_issue"
            phx-value-id={@issue.id}
            class="btn btn-sm btn-ghost"
          >
            Backlog
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
    </div>
    """
  end

  attr :event, :map, required: true

  defp session_event(assigns) do
    badge_class =
      case assigns.event.type do
        "assistant" -> "badge-primary"
        "tool_use" -> "badge-info"
        "tool_result" -> "badge-info"
        "result" -> "badge-success"
        "error" -> "badge-error"
        "stderr" -> "badge-warning"
        _ -> "badge-ghost"
      end

    message =
      case assigns.event.message do
        nil -> ""
        msg when byte_size(msg) > 200 -> String.slice(msg, 0..197) <> "..."
        msg -> msg
      end

    assigns =
      assigns
      |> assign(:badge_class, badge_class)
      |> assign(:display_message, message)

    ~H"""
    <div class="flex items-start gap-1.5 leading-tight">
      <span class={"badge badge-xs #{@badge_class} flex-shrink-0 mt-0.5"}>{@event.type}</span>
      <span :if={@display_message != ""} class="text-base-content/70 break-all">
        {@display_message}
      </span>
    </div>
    """
  end
end
