defmodule SynkadeWeb.IdeLive do
  use SynkadeWeb, :live_view

  # session_event no longer used — IDE has its own grouped rendering
  import SynkadeWeb.Components.AgentBrand
  import SynkadeWeb.IssueLiveHelpers, only: [state_badge_class: 1]

  alias Synkade.{Issues, Jobs, Settings}
  alias Synkade.Issues.Issue
  alias Synkade.Settings.ConfigAdapter
  alias Synkade.Workspace.{Git, Safety}
  alias Synkade.Workflow.Config

  @impl true
  def mount(%{"project_name" => project_name}, _session, socket) do
    scope = socket.assigns.current_scope

    case Settings.get_project_by_name(scope, project_name) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}

      project ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Synkade.PubSub, Issues.pubsub_topic(scope.user.id))
          Phoenix.PubSub.subscribe(Synkade.PubSub, Jobs.pubsub_topic(scope))
        end

        orc_state = Jobs.get_state(scope)

        socket =
          socket
          |> assign(:page_title, "New chat — #{project.name}")
          |> assign(:active_tab, :issues)
          |> assign(:current_project, project.name)
          |> assign(:issue, nil)
          |> assign(:ancestors, [])
          |> assign(:project, project)
          |> assign(:projects, orc_state.projects)
          |> assign(:running, orc_state.running)
          |> SynkadeWeb.Sidebar.assign_sidebar(scope)
          |> assign(:running_entry, nil)
          |> assign(:workspace_path, nil)
          |> assign(:base_branch, "HEAD")
          |> assign(:current_branch, nil)
          |> assign(:changed_files, [])
          |> assign(:selected_file, nil)
          |> assign(:file_diff, [])
          |> assign(:left_tab, :chat)
          |> assign(:agents, Settings.list_agents(scope))
          |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
          |> assign(:attachments, [])
          |> assign(:session_events, [])
          |> assign(:session_id, nil)
          |> assign(:session_subscribed, nil)
          |> allow_upload(:images,
            accept: ~w(.png .jpg .jpeg .gif .webp),
            max_entries: 5,
            max_file_size: 10_000_000
          )

        {:ok, socket}
    end
  end

  def mount(%{"id" => issue_id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Issues.get_issue(issue_id) do
      nil ->
        {:ok, push_navigate(socket, to: "/issues")}

      issue ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Synkade.PubSub, Issues.pubsub_topic(scope.user.id))
          Phoenix.PubSub.subscribe(Synkade.PubSub, Jobs.pubsub_topic(scope))
        end

        orc_state = Jobs.get_state(scope)
        ancestors = Issues.ancestor_chain(issue)
        project = Settings.get_project!(issue.project_id)
        workspace_path = resolve_workspace_path(scope, project, issue)

        # Subscribe to agent events if in_progress
        running_entry = find_running_entry(orc_state.running, issue.id)

        {session_events, session_id, session_subscribed} =
          if issue.state == "in_progress" && running_entry do
            if connected?(socket) do
              Phoenix.PubSub.subscribe(Synkade.PubSub, "agent_events:#{issue.id}")
            end

            {[], running_entry.session_id, issue.id}
          else
            {[], nil, nil}
          end

        # Detect base branch and current branch for PR-style diff
        {base_branch, current_branch} = detect_branches(workspace_path)

        # Load initial changed files against base branch
        changed_files = load_changed_files(workspace_path, base_branch)

        # Start diff polling if agent is running
        if session_subscribed, do: schedule_diff_refresh()

        socket =
          socket
          |> assign(:page_title, Issue.title(issue))
          |> assign(:active_tab, :issues)
          |> assign(:current_project, project.name)
          |> assign(:issue, issue)
          |> assign(:ancestors, ancestors)
          |> assign(:project, project)
          |> assign(:projects, orc_state.projects)
          |> assign(:running, orc_state.running)
          |> SynkadeWeb.Sidebar.assign_sidebar(scope)
          |> assign(:running_entry, running_entry)
          |> assign(:workspace_path, workspace_path)
          |> assign(:base_branch, base_branch)
          |> assign(:current_branch, current_branch)
          |> assign(:changed_files, changed_files)
          |> assign(:selected_file, nil)
          |> assign(:file_diff, [])
          |> assign(:left_tab, :chat)
          |> assign(:agents, Settings.list_agents(scope))
          |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
          |> assign(:attachments, [])
          |> assign(:session_events, session_events)
          |> assign(:session_id, session_id)
          |> assign(:session_subscribed, session_subscribed)
          |> allow_upload(:images,
            accept: ~w(.png .jpg .jpeg .gif .webp),
            max_entries: 5,
            max_file_size: 10_000_000
          )

        {:ok, socket}
    end
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

    # If agent just started, subscribe to events
    socket =
      if running_entry && is_nil(socket.assigns.session_subscribed) do
        Phoenix.PubSub.subscribe(Synkade.PubSub, "agent_events:#{socket.assigns.issue.id}")
        schedule_diff_refresh()

        socket
        |> assign(:session_subscribed, socket.assigns.issue.id)
        |> assign(:session_id, running_entry.session_id)
      else
        socket
      end

    # If agent stopped, unsubscribe and do final diff refresh
    socket =
      if is_nil(running_entry) && socket.assigns.session_subscribed do
        Phoenix.PubSub.unsubscribe(
          Synkade.PubSub,
          "agent_events:#{socket.assigns.session_subscribed}"
        )

        changed_files = load_changed_files(socket.assigns.workspace_path, socket.assigns.base_branch)

        socket
        |> assign(:session_subscribed, nil)
        |> assign(:changed_files, changed_files)
        |> maybe_refresh_selected_diff()
      else
        socket
      end

    socket =
      socket
      |> assign(:running, state.running)
      |> assign(:projects, state.projects)
      |> assign(:running_entry, running_entry)

    {:noreply, socket}
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
        ancestors = Issues.ancestor_chain(updated)

        {:noreply,
         socket
         |> assign(:issue, updated)
         |> assign(:ancestors, ancestors)
         |> SynkadeWeb.Sidebar.assign_sidebar(socket.assigns.current_scope)}
    end
  end

  @impl true
  def handle_info(:refresh_diff, socket) do
    changed_files = load_changed_files(socket.assigns.workspace_path, socket.assigns.base_branch)

    socket =
      socket
      |> assign(:changed_files, changed_files)
      |> maybe_refresh_selected_diff()

    # Continue polling if still subscribed
    if socket.assigns.session_subscribed, do: schedule_diff_refresh()

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

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
  def handle_event("dispatch_issue", %{"dispatch" => %{"message" => message}}, socket) do
    message = String.trim(message)
    attachments = socket.assigns.attachments
    uploads = consume_uploaded_images(socket)

    full_message = build_dispatch_message(message, attachments, uploads)

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

  # --- Render ---

  @impl true
  def render(assigns) do
    messages =
      if assigns.issue,
        do: (assigns.issue.metadata || %{})["messages"] || [],
        else: []

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
    >
      <div class="flex flex-col h-screen">
        <%!-- Top bar --%>
        <div class="flex items-center gap-3 px-4 py-2 border-b border-base-300 flex-shrink-0">
          <.link navigate="/issues" class="btn btn-ghost btn-xs gap-1">
            <.icon name="hero-arrow-left" class="size-3" />
          </.link>
          <%= if @issue do %>
            <span class={"badge badge-xs #{state_badge_class(@issue.state)}"}>{@issue.state}</span>
            <h1 class="text-sm font-semibold truncate flex-1">{Issue.title(@issue)}</h1>
          <% else %>
            <span class="badge badge-xs badge-ghost">draft</span>
            <h1 class="text-sm font-semibold truncate flex-1">New chat — {@project.name}</h1>
          <% end %>
          <span :if={@current_branch} class="text-xs font-mono text-base-content/40 flex-shrink-0">
            {@base_branch} ← {@current_branch}
          </span>
          <div :if={@running_entry} class="flex items-center gap-1.5">
            <span class="loading loading-spinner loading-xs text-info"></span>
            <span class="text-xs text-base-content/50">Agent running</span>
          </div>
        </div>

        <%!-- Main content: Left (tabs) | Right (changes list) --%>
        <div id="ide-split" class="flex flex-1 min-h-0" phx-hook="ResizableSplit" phx-update="ignore">
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
                <div
                  id="chat-scroll"
                  class="flex-1 overflow-y-auto px-4 py-4 space-y-4"
                  phx-hook="AutoScroll"
                >
                  <%!-- Draft mode hint --%>
                  <div :if={is_nil(@issue) && @messages == []} class="flex flex-col items-center justify-center h-full text-base-content/30">
                    <.icon name="hero-chat-bubble-left-right" class="size-8 mb-2" />
                    <span class="text-sm">Send a message to start working on {@project.name}</span>
                  </div>

                  <%!-- Issue context --%>
                  <div :if={@issue && (body_without_title(@issue.body) || @ancestors != [])} class="space-y-2 mb-2">
                    <div :for={ancestor <- Enum.reverse(@ancestors)} class="text-xs text-base-content/40">
                      {Issue.title(ancestor)}
                    </div>
                    <div :if={body_without_title(@issue.body)} class="flex justify-end">
                      <div class="max-w-[85%] rounded-2xl rounded-br-sm bg-primary/10 px-4 py-2.5 text-sm prose-chat">
                        {md(body_without_title(@issue.body))}
                      </div>
                    </div>
                  </div>

                  <%!-- Message history --%>
                  <div :for={msg <- @messages} class="space-y-1">
                    <%= cond do %>
                      <% msg["type"] == "dispatch" -> %>
                        <%!-- User message: right-aligned bubble --%>
                        <div class="flex justify-end">
                          <div class="max-w-[85%] rounded-2xl rounded-br-sm bg-primary/10 px-4 py-2.5 text-sm prose-chat">
                            {md(msg["text"])}
                          </div>
                        </div>
                      <% msg["type"] == "system" -> %>
                        <%!-- System message: centered, subtle --%>
                        <div class="flex justify-center">
                          <span class="text-xs text-base-content/40 italic">{msg["text"]}</span>
                        </div>
                      <% true -> %>
                        <%!-- Agent response: left-aligned --%>
                        <div class="max-w-[90%]">
                          <div class="flex items-center gap-1.5 mb-1">
                            <span :if={msg["agent_kind"]} class={brand_color(msg["agent_kind"])}>
                              <.agent_icon kind={msg["agent_kind"]} class="size-3.5" />
                            </span>
                            <span class="text-xs text-base-content/40 font-medium">
                              {msg["agent_name"] || "agent"}
                            </span>
                          </div>
                          <div class="text-sm prose-chat">{md(msg["text"])}</div>
                        </div>
                    <% end %>
                  </div>

                  <%!-- Live agent session --%>
                  <div
                    :if={@issue && @issue.state == "in_progress" && (@session_events != [] || @session_id)}
                    class="space-y-3"
                  >
                    <.chat_event_group
                      :for={group <- group_session_events(@session_events)}
                      group={group}
                      running_entry={@running_entry}
                      session_id={@session_id}
                    />
                    <div
                      :if={@session_events == []}
                      class="flex items-center gap-2 text-base-content/30 text-sm"
                    >
                      <span class="loading loading-dots loading-xs"></span>
                      Thinking...
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Diff tab --%>
              <div
                :if={@selected_file}
                class={[
                  "absolute inset-0 overflow-y-auto",
                  if(@left_tab == :diff, do: "z-10", else: "z-0 pointer-events-none hidden")
                ]}
              >
                <div
                  id="diff-viewer"
                  class="font-mono text-xs"
                  phx-hook="DiffComment"
                  phx-update="ignore"
                >
                  <div
                    :for={{line, idx} <- Enum.with_index(@file_diff)}
                    id={"diff-line-#{idx}"}
                    class={["flex group", diff_line_class(line.type)]}
                  >
                    <%= if line.type == :header do %>
                      <div class="px-3 py-1 text-base-content/40 bg-info/10 w-full">
                        {line.text}
                      </div>
                    <% else %>
                      <button
                        class="w-8 text-right pr-1 text-base-content/20 hover:text-primary cursor-pointer select-none flex-shrink-0 diff-line-btn"
                        data-file={@selected_file}
                        data-line={line.new_line || line.old_line}
                      >
                        {line.new_line || line.old_line}
                      </button>
                      <span class="w-5 text-center text-base-content/30 flex-shrink-0">
                        {diff_line_prefix(line.type)}
                      </span>
                      <pre class="flex-1 whitespace-pre-wrap break-all px-1">{line.text}</pre>
                    <% end %>
                  </div>

                  <div :if={@file_diff == []} class="px-3 py-4 text-base-content/30 text-center">
                    No diff available
                  </div>
                </div>
              </div>
            </div>

            <%!-- Input (always visible) --%>
            <div class="p-3 flex-shrink-0">
              <.form for={@dispatch_form} phx-submit="dispatch_issue" phx-change="validate_upload" multipart>
                <div
                  id="ide-input-box"
                  class="rounded-xl border border-base-300 bg-base-300 relative overflow-hidden"
                  phx-hook="DropZone"
                  phx-drop-target={@uploads.images.ref}
                >
                  <%!-- Drop overlay --%>
                  <div
                    data-drop-overlay
                    class="hidden absolute inset-0 z-30 bg-primary/10 border-2 border-dashed border-primary/40 rounded-xl flex flex-col items-center justify-center backdrop-blur-sm"
                  >
                    <.icon name="hero-arrow-up-tray" class="size-8 text-primary/60 mb-1" />
                    <span class="text-sm font-medium text-base-content/70">Drop files here</span>
                    <span class="text-xs text-base-content/40">Any file type</span>
                  </div>

                  <%!-- Attachment cards --%>
                  <div
                    :if={@attachments != [] or @uploads.images.entries != []}
                    class="flex flex-wrap gap-2 px-3 pt-3"
                  >
                    <div
                      :for={att <- @attachments}
                      class="flex items-center gap-2 bg-base-300/60 rounded-lg px-2.5 py-1.5 text-xs"
                    >
                      <.icon name="hero-chat-bubble-left" class="size-3.5 text-base-content/40" />
                      <span class="font-mono font-semibold">{Path.basename(att.file)}:{att.line}</span>
                      <span class="text-base-content/50 truncate max-w-32">{att.text}</span>
                      <button
                        type="button"
                        phx-click="remove_attachment"
                        phx-value-id={att.id}
                        class="text-base-content/30 hover:text-error"
                      >
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </div>

                    <div
                      :for={entry <- @uploads.images.entries}
                      class="flex items-center gap-2 bg-base-300/60 rounded-lg px-2.5 py-1.5 text-xs"
                    >
                      <.live_img_preview entry={entry} class="size-8 rounded object-cover" />
                      <span class="font-mono truncate max-w-24">{entry.client_name}</span>
                      <button
                        type="button"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                        class="text-base-content/30 hover:text-error"
                      >
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </div>
                  </div>

                  <%!-- Textarea --%>
                  <textarea
                    id="ide-message-input"
                    name="dispatch[message]"
                    placeholder="Message..."
                    class="w-full bg-transparent border-0 focus:ring-0 focus:outline-none resize-none px-3 pt-3 pb-2 text-sm min-h-[60px] max-h-[200px]"
                    rows="2"
                    phx-debounce="300"
                    phx-hook="SubmitOnEnter"
                  ><%= @dispatch_form[:message].value %></textarea>

                  <%!-- Bottom toolbar --%>
                  <div class="flex items-center justify-between px-3 pb-2.5">
                    <div class="flex items-center gap-1">
                    </div>
                    <div class="flex items-center gap-1.5">
                      <label class="btn btn-ghost btn-sm btn-square cursor-pointer" title="Attach files">
                        <.icon name="hero-plus" class="size-4" />
                        <.live_file_input upload={@uploads.images} class="hidden" />
                      </label>
                      <button
                        type="submit"
                        class="btn btn-ghost btn-sm btn-square"
                        title="Send"
                      >
                        <.icon name="hero-arrow-up-circle-solid" class="size-6" />
                      </button>
                    </div>
                  </div>
                </div>
              </.form>
            </div>
          </div>

          <%!-- Drag handle --%>
          <div id="ide-drag" class="w-1 flex-shrink-0 bg-base-300 cursor-col-resize hover:bg-primary/40 active:bg-primary/60 transition-colors"></div>

          <%!-- Right panel: Changes list --%>
          <div id="ide-right" class="flex flex-col overflow-y-auto min-w-0 bg-base-300" style="width: 320px; flex-shrink: 0">
            <div class="flex items-center gap-2 px-4 py-2 sticky top-0 bg-base-300 border-b border-base-300 z-10">
              <span class="text-sm font-semibold">Changes</span>
              <span class="badge badge-sm badge-ghost">{length(@changed_files)}</span>
            </div>
            <div :if={@changed_files == []} class="text-sm text-base-content/30 py-6 text-center">
              No changes detected
            </div>
            <div
              :for={entry <- @changed_files}
              phx-click="select_file"
              phx-value-file={entry.file}
              class={[
                "flex items-center gap-2 px-4 py-2 cursor-pointer transition-colors",
                if(@selected_file == entry.file,
                  do: "bg-base-200",
                  else: "hover:bg-base-200/50"
                )
              ]}
            >
              <span class="flex-1 min-w-0 text-sm font-mono truncate">
                <span class="text-base-content/40">{file_dir(entry.file)}</span><span class="font-semibold text-base-content">{Path.basename(entry.file)}</span>
              </span>
              <span class={["text-xs font-mono flex-shrink-0", file_status_color(entry.status)]}>
                {entry.status}
              </span>
              <span :if={entry.additions > 0} class="text-xs font-mono text-success flex-shrink-0">
                +{entry.additions}
              </span>
              <span :if={entry.deletions > 0} class="text-xs font-mono text-error flex-shrink-0">
                -{entry.deletions}
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp md(text) when is_binary(text) do
    case MDEx.to_html(text, sanitize: MDEx.Document.default_sanitize_options()) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end

  defp md(_), do: ""

  # --- Chat Components ---

  defp chat_event_group(assigns) do
    ~H"""
    <%= case @group.type do %>
      <% :tools -> %>
        <%!-- Collapsed tool calls --%>
        <div class="flex items-center gap-1.5 text-xs text-base-content/40">
          <.icon name="hero-wrench-screwdriver" class="size-3" />
          <span>{length(@group.events)} tool call{if length(@group.events) != 1, do: "s"}</span>
        </div>
      <% :text -> %>
        <%!-- Agent text message --%>
        <div class="max-w-[90%]">
          <div :if={@group.first_in_turn} class="flex items-center gap-1.5 mb-1">
            <span :if={@running_entry && @running_entry[:agent_kind]} class={brand_color(@running_entry[:agent_kind])}>
              <.agent_icon kind={@running_entry[:agent_kind]} class="size-3.5" />
            </span>
            <span class="text-xs text-base-content/40 font-medium">
              {if @running_entry, do: @running_entry[:agent_name] || "agent", else: "agent"}
            </span>
            <code :if={@session_id} class="text-[10px] text-base-content/20 font-mono ml-auto">
              {String.slice(@session_id, 0..7)}
            </code>
          </div>
          <div class="text-sm prose-chat">{md(@group.text)}</div>
        </div>
      <% :result -> %>
        <%!-- Final result --%>
        <div class="max-w-[90%]">
          <div class="text-sm prose-chat">{md(@group.text)}</div>
        </div>
      <% :error -> %>
        <div class="text-sm text-error">{@group.text}</div>
      <% :thinking -> %>
        <div class="flex items-center gap-2 text-base-content/30 text-sm">
          <span class="loading loading-dots loading-xs"></span>
          Thinking...
        </div>
      <% _ -> %>
        <div class="text-xs text-base-content/30">{@group.type}</div>
    <% end %>
    """
  end

  @doc false
  defp group_session_events(events) do
    events
    |> Enum.reduce([], fn event, acc ->
      case event.type do
        type when type in ~w(tool_use tool_result) ->
          case acc do
            [%{type: :tools, events: tool_events} = group | rest] ->
              [%{group | events: tool_events ++ [event]} | rest]

            _ ->
              [%{type: :tools, events: [event]} | acc]
          end

        "assistant" ->
          msg = event.message || ""

          if msg != "" do
            [%{type: :text, text: msg, first_in_turn: !has_preceding_text?(acc)} | acc]
          else
            acc
          end

        "result" ->
          msg = event.message || ""
          if msg != "", do: [%{type: :result, text: msg} | acc], else: acc

        "error" ->
          [%{type: :error, text: event.message || "Unknown error"} | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp has_preceding_text?(groups) do
    Enum.any?(groups, fn
      %{type: :text} -> true
      _ -> false
    end)
  end

  # --- Dispatch Helpers ---

  defp handle_draft_dispatch(socket, full_message) do
    project = socket.assigns.project

    # Derive title: first line or first 60 chars
    title =
      full_message
      |> String.split("\n", parts: 2)
      |> hd()
      |> String.slice(0..59)

    body = "# #{title}\n\n#{full_message}"

    case Issues.create_issue(%{project_id: project.id, body: body}) do
      {:ok, issue} ->
        {agent_name, instruction, agent_id} =
          SynkadeWeb.IssueLiveHelpers.resolve_dispatch(socket.assigns.current_scope, full_message)

        case Issues.dispatch_issue(issue, instruction, agent_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Created and dispatched" <> if(agent_name, do: " to #{agent_name}", else: ""))
             |> push_navigate(to: "/issues/#{issue.id}")}

          {:error, _} ->
            # Issue created but dispatch failed — still navigate to it
            {:noreply,
             socket
             |> put_flash(:info, "Issue created")
             |> push_navigate(to: "/issues/#{issue.id}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create issue")}
    end
  end

  defp handle_existing_dispatch(socket, full_message) do
    issue = socket.assigns.issue

    {agent_name, instruction, agent_id} =
      SynkadeWeb.IssueLiveHelpers.resolve_dispatch(socket.assigns.current_scope, full_message)

    case Issues.dispatch_issue(issue, instruction, agent_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
          |> assign(:attachments, [])
          |> push_event("clear_input", %{})
          |> put_flash(
            :info,
            "Dispatched" <> if(agent_name, do: " to #{agent_name}", else: "")
          )

        {:noreply, socket}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot dispatch from current state")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to dispatch")}
    end
  end

  # --- Private Helpers ---

  defp resolve_workspace_path(scope, project, issue) do
    setting = Settings.get_settings_for_user(scope.user.id)

    if setting do
      config = ConfigAdapter.to_config(setting)
      root = Config.workspace_root(config)
      # Matches identifier from agent_worker.ex line 176
      identifier = "#{project.name}##{issue.id |> String.slice(0..7)}"
      key = Safety.sanitize_key("#{project.name}/#{identifier}")
      Path.join(root, key)
    else
      nil
    end
  end

  defp detect_branches(nil), do: {"HEAD", nil}

  defp detect_branches(path) do
    if File.dir?(path) and File.dir?(Path.join(path, ".git")) do
      {Git.detect_base_branch(path), Git.current_branch(path)}
    else
      {"HEAD", nil}
    end
  end

  defp load_changed_files(nil, _base_ref), do: []

  defp load_changed_files(path, base_ref) do
    if File.dir?(path) do
      case Git.changed_files(path, base_ref) do
        {:ok, files} -> files
        {:error, _} -> []
      end
    else
      []
    end
  end

  defp load_file_diff(nil, _filename, _base_ref), do: []

  defp load_file_diff(path, filename, base_ref) do
    case Git.file_diff(path, filename, base_ref) do
      {:ok, raw} -> Git.parse_diff(raw)
      {:error, _} -> []
    end
  end

  defp maybe_refresh_selected_diff(socket) do
    if socket.assigns.selected_file do
      diff_lines =
        load_file_diff(
          socket.assigns.workspace_path,
          socket.assigns.selected_file,
          socket.assigns.base_branch
        )

      assign(socket, :file_diff, diff_lines)
    else
      socket
    end
  end

  defp schedule_diff_refresh do
    Process.send_after(self(), :refresh_diff, 5_000)
  end

  defp consume_uploaded_images(socket) do
    consume_uploaded_entries(socket, :images, fn %{path: path}, entry ->
      # Copy uploaded file to workspace so the agent can access it
      workspace_path = socket.assigns.workspace_path
      filename = Path.basename(entry.client_name)

      if workspace_path && File.dir?(workspace_path) do
        dest_dir = Path.join(workspace_path, ".synkade/uploads")
        File.mkdir_p!(dest_dir)
        dest = Path.join(dest_dir, filename)
        File.cp!(path, dest)
        {:ok, %{filename: filename, path: ".synkade/uploads/#{filename}"}}
      else
        {:ok, %{filename: filename, path: nil}}
      end
    end)
  end

  defp build_dispatch_message(message, attachments, uploads) do
    parts = []

    # Add code comment attachments
    comment_parts =
      attachments
      |> Enum.filter(&(&1.type == :comment))
      |> Enum.map(fn att -> "[#{att.file}:#{att.line}] #{att.text}" end)

    # Add image references
    image_parts =
      uploads
      |> Enum.filter(& &1.path)
      |> Enum.map(fn upload -> "[image: #{upload.path}]" end)

    all_parts = parts ++ comment_parts ++ image_parts
    context = Enum.join(all_parts, "\n")

    case {String.trim(context), String.trim(message)} do
      {"", msg} -> msg
      {ctx, ""} -> ctx
      {ctx, msg} -> ctx <> "\n\n" <> msg
    end
  end

  defp find_running_entry(running, issue_id) do
    Enum.find_value(running, fn {_key, entry} ->
      if entry.issue_id == issue_id, do: entry
    end)
  end

  defp body_without_title(nil), do: nil
  defp body_without_title(""), do: nil

  defp body_without_title(body) do
    result =
      String.replace(body, ~r/^#\s+.+\n*/, "", global: false)
      |> String.trim_leading("\n")
      |> String.trim()

    if result == "", do: nil, else: result
  end

  defp diff_line_class(:add), do: "bg-success/10"
  defp diff_line_class(:remove), do: "bg-error/10"
  defp diff_line_class(:header), do: ""
  defp diff_line_class(_), do: ""

  defp diff_line_prefix(:add), do: "+"
  defp diff_line_prefix(:remove), do: "-"
  defp diff_line_prefix(_), do: " "

  defp file_status_color("M"), do: "text-warning"
  defp file_status_color("A"), do: "text-success"
  defp file_status_color("D"), do: "text-error"
  defp file_status_color("U"), do: "text-info"
  defp file_status_color("?"), do: "text-info"
  defp file_status_color(_), do: "text-base-content/50"

  defp file_dir(path) do
    dir = Path.dirname(path)
    if dir == ".", do: "", else: dir <> "/"
  end

end
