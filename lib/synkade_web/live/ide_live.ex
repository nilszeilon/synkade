defmodule SynkadeWeb.IdeLive do
  use SynkadeWeb, :live_view

  import SynkadeWeb.Components.Ide.ChatView
  import SynkadeWeb.Components.Ide.DiffView
  import SynkadeWeb.Components.Ide.ChatInput
  import SynkadeWeb.Components.Ide.ChatMessages
  import SynkadeWeb.Components.Ide.ChangesPanel
  import SynkadeWeb.Components.Ide.TopBar
  import SynkadeWeb.IssueLiveHelpers,
    only: [find_running_entry: 2]
  import SynkadeWeb.IdeWorkspaceHelpers
  import SynkadeWeb.IdeDispatchHelpers
  import SynkadeWeb.ModelPickerHelpers,
    only: [handle_model_picker_event: 3, handle_model_picker_info: 2, model_picker_assigns: 1]
  import SynkadeWeb.AgentPickerHelpers,
    only: [handle_agent_picker_event: 3, agent_picker_assigns: 0]

  alias Synkade.{Issues, Jobs, Settings}
  alias Synkade.Issues.Issue

  @impl true
  def mount(%{"project_name" => project_name}, _session, socket) do
    scope = socket.assigns.current_scope

    case Settings.get_project_by_name(scope, project_name) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}

      project ->
        subscribe_topics(socket, scope)
        orc_state = Jobs.get_state(scope)

        socket =
          socket
          |> assign_common(scope, project, orc_state)
          |> assign(:page_title, "New chat — #{project.name}")
          |> assign(:issue, nil)
          |> assign(:running_entry, nil)
          |> assign(:workspace_path, nil)
          |> assign(:base_branch, "HEAD")
          |> assign(:current_branch, nil)
          |> assign(:commits_ahead, 0)
          |> assign(:changed_files, [])
          |> assign(:session_events, [])
          |> assign(:session_id, nil)
          |> assign(:session_subscribed, nil)
          |> assign(:turn_start_sha, nil)
          |> assign(:turn_started_at, nil)
          |> assign(:agent_kind, nil)

        {:ok, socket}
    end
  end

  def mount(%{"id" => issue_id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Issues.get_issue(issue_id) do
      nil ->
        {:ok, push_navigate(socket, to: "/issues")}

      issue ->
        subscribe_topics(socket, scope)
        orc_state = Jobs.get_state(scope)
        project = Settings.get_project!(issue.project_id)
        workspace_path = resolve_workspace_path(scope, project, issue)
        running_entry = find_running_entry(orc_state.running, issue.id)

        {session_events, session_id, session_subscribed} =
          load_session_events(socket, issue, running_entry, workspace_path)

        {base_branch, current_branch} = detect_branches(workspace_path)
        changed_files = load_changed_files(workspace_path, base_branch)

        if session_subscribed, do: schedule_diff_refresh()

        socket =
          socket
          |> assign_common(scope, project, orc_state)
          |> assign(:page_title, Issue.title(issue))
          |> assign(:issue, issue)
          |> assign(:running_entry, running_entry)
          |> assign(:workspace_path, workspace_path)
          |> assign(:base_branch, base_branch)
          |> assign(:current_branch, current_branch)
          |> assign(:commits_ahead, load_commits_ahead(workspace_path, base_branch))
          |> assign(:changed_files, changed_files)
          |> assign(:session_events, session_events)
          |> assign(:session_id, session_id)
          |> assign(:session_subscribed, session_subscribed)
          |> assign(:turn_start_sha, if(session_subscribed, do: current_head_sha(workspace_path), else: nil))
          |> assign(:turn_started_at, if(session_subscribed, do: System.monotonic_time(:millisecond), else: nil))
          |> assign(:agent_kind, (running_entry && running_entry.agent_kind) || issue.metadata["last_agent_kind"])

        if current_branch, do: send(self(), :load_pr_info)

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Pick up agent query param from agent picker navigation
    socket =
      case params["agent"] do
        nil -> socket
        agent_id -> assign(socket, :selected_dispatch_agent_id, agent_id)
      end

    {:noreply, socket}
  end

  # --- Handle Info ---

  @impl true
  def handle_info({:agent_event, event}, socket) do
    events = socket.assigns.session_events ++ [event]
    events = Enum.take(events, -500)

    socket =
      socket
      |> assign(:session_events, events)
      |> assign(:session_id, event.session_id || socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:jobs_changed}, %{assigns: %{issue: nil}} = socket) do
    state = Jobs.get_state(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:running, state.running)
     |> assign(:projects, state.projects)}
  end

  def handle_info({:jobs_changed}, socket) do
    state = Jobs.get_state(socket.assigns.current_scope)
    running_entry = find_running_entry(state.running, socket.assigns.issue.id)

    socket =
      if running_entry && is_nil(socket.assigns.session_subscribed),
        do: handle_agent_started(socket, running_entry),
        else: socket

    socket =
      if is_nil(running_entry) && socket.assigns.session_subscribed,
        do: handle_agent_stopped(socket),
        else: socket

    socket
    |> assign(:running, state.running)
    |> assign(:projects, state.projects)
    |> assign(:running_entry, running_entry)
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info({:issues_updated}, %{assigns: %{issue: nil}} = socket) do
    {:noreply,
     SynkadeWeb.Sidebar.assign_sidebar(socket, socket.assigns.current_scope)}
  end

  def handle_info({:issues_updated}, socket) do
    case Issues.get_issue(socket.assigns.issue.id) do
      nil ->
        {:noreply, push_navigate(socket, to: "/issues")}

      updated ->
        {:noreply,
         socket
         |> assign(:issue, updated)
         |> SynkadeWeb.Sidebar.assign_sidebar(socket.assigns.current_scope)}
    end
  end

  @impl true
  def handle_info(:refresh_diff, socket) do
    changed_files = load_changed_files(socket.assigns.workspace_path, socket.assigns.base_branch)

    socket =
      socket
      |> assign(:changed_files, changed_files)
      |> assign(:commits_ahead, load_commits_ahead(socket.assigns.workspace_path, socket.assigns.base_branch))
      |> maybe_refresh_selected_diff()

    # Continue polling if still subscribed
    if socket.assigns.session_subscribed, do: schedule_diff_refresh()

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_pr_info, socket) do
    branch = socket.assigns.current_branch

    if branch do
      case load_tracker_config(socket.assigns.current_scope, socket.assigns.project) do
        {:ok, config} ->
          {pr_info, pr_checks} =
            case Synkade.Tracker.GitHub.fetch_pr_for_branch(config, branch) do
              {:ok, %{number: number} = pr} ->
                checks =
                  case Synkade.Tracker.GitHub.fetch_pr_checks(config, number) do
                    {:ok, state} -> state
                    _ -> :unknown
                  end

                {pr, checks}

              _ ->
                {nil, :unknown}
            end

          {:noreply, socket |> assign(:pr_info, pr_info) |> assign(:pr_checks, pr_checks)}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(msg, socket) do
    case handle_model_picker_info(msg, socket) do
      {:halt, socket} -> {:noreply, socket}
      :cont -> {:noreply, socket}
    end
  end

  # --- Handle Events ---

  @impl true
  def handle_event("select_file", %{"file" => filename}, socket) do
    diff_lines = load_file_diff(socket.assigns.workspace_path, filename, socket.assigns.base_branch)

    socket =
      socket
      |> assign(:selected_file, filename)
      |> assign(:file_diff, diff_lines)
      |> assign(:left_tab, :diff)

    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => "chat"}, socket) do
    {:noreply, assign(socket, :left_tab, :chat)}
  end

  def handle_event("switch_tab", %{"tab" => "diff"}, socket) do
    if socket.assigns.selected_file do
      {:noreply, assign(socket, :left_tab, :diff)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("agent_picker_" <> _ = event, params, socket) do
    {:halt, socket} = handle_agent_picker_event(event, params, socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("dispatch_issue", %{"dispatch" => dispatch_params}, socket) do
    message = String.trim(dispatch_params["message"] || "")
    model = dispatch_params["model"]
    model = if model == "", do: nil, else: model
    attachments = socket.assigns.attachments
    uploads = consume_uploaded_images(socket)

    full_message = build_dispatch_message(message, attachments, uploads)

    socket = assign(socket, :selected_model, model)

    if full_message == "" do
      {:noreply, put_flash(socket, :error, "Message cannot be empty")}
    else
      # Draft mode: create issue from first message, then redirect
      if is_nil(socket.assigns.issue) do
        handle_draft_dispatch(socket, full_message)
      else
        handle_existing_dispatch(socket, full_message)
      end
    end
  end

  @impl true
  def handle_event("comment_line", %{"file" => file, "line" => line, "text" => text}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      attachment = %{
        id: System.unique_integer([:positive]),
        type: :comment,
        file: file,
        line: line,
        text: text
      }

      {:noreply, assign(socket, :attachments, socket.assigns.attachments ++ [attachment])}
    end
  end

  @impl true
  def handle_event("remove_attachment", %{"id" => id}, socket) do
    id = String.to_integer(id)
    attachments = Enum.reject(socket.assigns.attachments, &(&1.id == id))
    {:noreply, assign(socket, :attachments, attachments)}
  end

  @impl true
  def handle_event("toggle_turn_filter", _, socket) do
    {:noreply, assign(socket, :turn_filter, !socket.assigns.turn_filter)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("copy_resume", _params, socket) do
    if socket.assigns.session_id do
      {:noreply,
       push_event(socket, "phx:copy", %{text: "claude --resume #{socket.assigns.session_id}"})}
    else
      {:noreply, put_flash(socket, :error, "No session ID available")}
    end
  end

  @impl true
  def handle_event("create_pr", _params, socket) do
    issue = socket.assigns.issue
    if issue do
      pr_instruction = "Push your changes and create a GitHub pull request for this branch. Use the issue title as the PR title and summarize the changes in the description."
      handle_existing_dispatch(socket, pr_instruction)
    else
      {:noreply, put_flash(socket, :error, "No issue to create PR for")}
    end
  end

  @impl true
  def handle_event("merge_pr", _params, socket) do
    pr = socket.assigns.pr_info
    if socket.assigns.issue && pr do
      handle_existing_dispatch(socket, "Merge the pull request ##{pr.number} on GitHub.")
    else
      {:noreply, put_flash(socket, :error, "No PR to merge")}
    end
  end

  @impl true
  def handle_event("complete_issue", _params, socket) do
    issue = socket.assigns.issue

    if issue do
      case Issues.complete_issue(issue) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Issue archived")
           |> push_navigate(to: "/issues")}

        {:error, :invalid_transition} ->
          {:noreply, put_flash(socket, :error, "Cannot archive from current state")}
      end
    else
      {:noreply, put_flash(socket, :error, "No issue to archive")}
    end
  end

  @impl true
  def handle_event("fix_checks", _params, socket) do
    pr = socket.assigns.pr_info
    if socket.assigns.issue && pr do
      handle_existing_dispatch(
        socket,
        "The CI pipeline is failing on PR ##{pr.number}. Fetch the failing check logs from GitHub, diagnose the failures, and push fixes."
      )
    else
      {:noreply, put_flash(socket, :error, "No PR to fix")}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    case handle_model_picker_event(event, params, socket) do
      {:halt, socket} -> {:noreply, socket}
      :cont -> {:noreply, socket}
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    messages =
      if assigns.issue do
        all = (assigns.issue.metadata || %{})["messages"] || []

        # When session events are loaded, the last agent message is redundant
        # (session events show the same content with rich structure)
        if assigns.session_events != [] do
          drop_trailing_agent_messages(all)
        else
          all
        end
      else
        []
      end

    assigns = assign(assigns, :messages, messages)

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
      picker={@picker}
    >
      <div class="flex flex-col h-screen">
        <%!-- Top bar --%>
        <.top_bar issue={@issue} project={@project} current_branch={@current_branch} base_branch={@base_branch} running_entry={@running_entry} />

        <%!-- Main content: Left (tabs) | Right (changes list) --%>
        <div id="ide-split" class="flex flex-1 min-h-0" phx-hook="ResizableSplit">
          <%!-- Left panel: tabbed content + input --%>
          <div id="ide-left" class="flex flex-col min-w-0" style="flex: 1 1 0%">
            <%!-- Tab bar --%>
            <div class="flex items-center border-b border-base-300 flex-shrink-0 bg-base-100">
              <button
                phx-click="switch_tab"
                phx-value-tab="chat"
                class={[
                  "px-4 py-2 text-sm font-medium border-b-2 transition-colors",
                  if(@left_tab == :chat,
                    do: "border-primary text-primary",
                    else: "border-transparent text-base-content/50 hover:text-base-content/80"
                  )
                ]}
              >
                Chat
              </button>
              <button
                :if={@selected_file}
                phx-click="switch_tab"
                phx-value-tab="diff"
                class={[
                  "px-4 py-2 text-sm font-mono border-b-2 transition-colors flex items-center gap-1.5",
                  if(@left_tab == :diff,
                    do: "border-primary text-primary",
                    else: "border-transparent text-base-content/50 hover:text-base-content/80"
                  )
                ]}
              >
                {Path.basename(@selected_file)}
              </button>
            </div>

            <%!-- Tab content --%>
            <div class="flex-1 overflow-hidden relative">
              <%!-- Chat tab --%>
              <div class={[
                "absolute inset-0 flex flex-col transition-opacity",
                if(@left_tab == :chat, do: "opacity-100 z-10", else: "opacity-0 z-0 pointer-events-none")
              ]}>
                <.chat_messages
                  issue={@issue}
                  messages={@messages}
                  session_events={@session_events}
                  session_id={@session_id}
                  running_entry={@running_entry}
                  agent_kind={@agent_kind}
                  project={@project}
                  last_turn_files={@last_turn_files}
                  last_turn_duration={@last_turn_duration}
                />
              </div>

              <%!-- Diff tab --%>
              <div
                :if={@selected_file}
                class={[
                  "absolute inset-0 overflow-y-auto",
                  if(@left_tab == :diff, do: "z-10", else: "z-0 pointer-events-none hidden")
                ]}
              >
                <.diff_viewer file={@selected_file} diff_lines={@file_diff} />
              </div>
            </div>

            <%!-- Input (always visible) --%>
            <.chat_input
              dispatch_form={@dispatch_form}
              uploads={@uploads}
              attachments={@attachments}
              agents={@agents}
              selected_dispatch_agent_id={@selected_dispatch_agent_id}
              selected_model={@selected_model}
              model_picker={@model_picker}
              agent_picker={@agent_picker}
              agent_kind={ide_resolved_agent_kind(assigns)}
            />
          </div>

          <%!-- Drag handle --%>
          <div id="ide-drag" class="w-1 flex-shrink-0 bg-base-300 cursor-col-resize hover:bg-primary/40 active:bg-primary/60 transition-colors"></div>

          <%!-- Right panel: Changes list --%>
          <.changes_panel
            issue={@issue}
            pr_info={@pr_info}
            pr_checks={@pr_checks}
            running_entry={@running_entry}
            current_branch={@current_branch}
            commits_ahead={@commits_ahead}
            changed_files={@changed_files}
            selected_file={@selected_file}
            turn_filter={@turn_filter}
            last_turn_files={@last_turn_files}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Mount Helpers ---

  defp subscribe_topics(socket, scope) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Issues.pubsub_topic(scope.user.id))
      Phoenix.PubSub.subscribe(Synkade.PubSub, Jobs.pubsub_topic(scope))
    end
  end

  defp assign_common(socket, scope, project, orc_state) do
    socket
    |> assign(:active_tab, :issues)
    |> assign(:current_project, project.name)
    |> assign(:project, project)
    |> assign(:projects, orc_state.projects)
    |> assign(:running, orc_state.running)
    |> SynkadeWeb.Sidebar.assign_sidebar(scope)
    |> assign(:selected_file, nil)
    |> assign(:file_diff, [])
    |> assign(:left_tab, :chat)
    |> assign(:agents, Settings.list_agents(scope))
    |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
    |> assign(:attachments, [])
    |> assign(:selected_dispatch_agent_id, nil)
    |> assign(:last_turn_files, [])
    |> assign(:last_turn_duration, 0)
    |> assign(:turn_filter, false)
    |> assign(:pr_info, nil)
    |> assign(:pr_checks, :unknown)
    |> assign(model_picker_assigns(project))
    |> assign(agent_picker_assigns())
    |> allow_upload(:images,
      accept: ~w(.png .jpg .jpeg .gif .webp),
      max_entries: 5,
      max_file_size: 10_000_000
    )
  end

  defp load_session_events(socket, issue, running_entry, workspace_path) do
    if issue.state == "worked_on" && running_entry do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Synkade.PubSub, "agent_events:#{issue.id}")
      end

      cached = Synkade.Execution.SessionEventCache.get(issue.id)
      sid = running_entry.session_id || extract_session_id(cached)
      {cached, sid, issue.id}
    else
      agent_kind = issue.metadata["last_agent_kind"]
      last_sid = issue.metadata["last_session_id"]

      cached =
        Synkade.Execution.SessionEventCache.get_or_load(issue.id, agent_kind,
          session_id: last_sid,
          workspace_path: workspace_path
        )

      if cached != [] do
        {cached, last_sid || extract_session_id(cached), nil}
      else
        {[], nil, nil}
      end
    end
  end

  defp handle_agent_started(socket, running_entry) do
    Phoenix.PubSub.subscribe(Synkade.PubSub, "agent_events:#{socket.assigns.issue.id}")
    schedule_diff_refresh()

    socket
    |> assign(:session_subscribed, socket.assigns.issue.id)
    |> assign(:session_id, running_entry.session_id)
    |> assign(:agent_kind, running_entry.agent_kind)
    |> assign(:turn_start_sha, current_head_sha(socket.assigns.workspace_path))
    |> assign(:turn_started_at, System.monotonic_time(:millisecond))
    |> assign(:last_turn_files, [])
    |> assign(:turn_filter, false)
  end

  defp handle_agent_stopped(socket) do
    Phoenix.PubSub.unsubscribe(Synkade.PubSub, "agent_events:#{socket.assigns.session_subscribed}")

    ws = socket.assigns.workspace_path
    changed_files = load_changed_files(ws, socket.assigns.base_branch)
    turn_files = compute_turn_files(ws, socket.assigns.turn_start_sha)

    turn_duration =
      if socket.assigns.turn_started_at do
        div(System.monotonic_time(:millisecond) - socket.assigns.turn_started_at, 1000)
      else
        0
      end

    send(self(), :load_pr_info)

    socket
    |> assign(:session_subscribed, nil)
    |> assign(:changed_files, changed_files)
    |> assign(:last_turn_files, turn_files)
    |> assign(:last_turn_duration, turn_duration)
    |> assign(:commits_ahead, load_commits_ahead(ws, socket.assigns.base_branch))
    |> maybe_refresh_selected_diff()
  end

end
