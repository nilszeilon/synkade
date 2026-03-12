defmodule SynkadeWeb.DashboardLive do
  use SynkadeWeb, :live_view

  alias Synkade.{Issues, Orchestrator, Settings}
  alias Synkade.Issues.DispatchParser
  alias Synkade.Tracker.Client, as: TrackerClient
  alias Synkade.Workflow.Config

  @board_columns [
    %{"id" => "backlog", "name" => "Backlog"},
    %{"id" => "queue", "name" => "Queue"},
    %{"id" => "in_progress", "name" => "In Progress"},
    %{"id" => "human_review", "name" => "Human Review"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic())
    end

    state = Orchestrator.get_state()

    socket =
      socket
      |> assign(:page_title, "Board")
      |> assign(:active_tab, :dashboard)
      |> assign(:current_project, nil)
      |> assign(:running, state.running)
      |> assign(:retry_attempts, state.retry_attempts)
      |> assign(:awaiting_review, state.awaiting_review)
      |> assign(:agent_totals, state.agent_totals)
      |> assign(:agent_totals_by_project, state.agent_totals_by_project)
      |> assign(:projects, state.projects)
      |> assign(:config_error, state.config_error)
      |> assign(:board_columns, @board_columns)
      |> assign(:board_issues, %{
        "backlog" => [],
        "queue" => [],
        "in_progress" => [],
        "human_review" => []
      })
      |> assign(:board_loading, true)
      |> assign(:board_error, nil)
      |> assign(:modal, nil)
      |> assign(:agents, Settings.list_agents())

    if connected?(socket) do
      send(self(), :load_board)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, :current_project, params["project"])

    if connected?(socket) do
      send(self(), :load_board)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_changed, snapshot}, socket) do
    socket =
      socket
      |> assign(:running, snapshot.running)
      |> assign(:retry_attempts, snapshot.retry_attempts)
      |> assign(:awaiting_review, snapshot.awaiting_review)
      |> assign(:agent_totals, snapshot.agent_totals)
      |> assign(:agent_totals_by_project, snapshot.agent_totals_by_project)
      |> assign(:projects, snapshot.projects)
      |> assign(:config_error, snapshot.config_error)

    # Re-categorize issues with updated orchestrator state
    project = resolve_project(socket)

    socket =
      if project do
        dispatch_labels = Config.tracker_labels(project.config) || []
        board_issues = recategorize_from_assigns(socket, project.name, dispatch_labels)
        assign(socket, :board_issues, board_issues)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_board, socket) do
    project = resolve_project(socket)
    state = Orchestrator.get_state()

    socket =
      socket
      |> assign(:running, state.running)
      |> assign(:retry_attempts, state.retry_attempts)
      |> assign(:awaiting_review, state.awaiting_review)

    socket =
      case project do
        nil ->
          socket
          |> assign(:board_issues, %{
            "backlog" => [],
            "queue" => [],
            "in_progress" => [],
            "human_review" => []
          })
          |> assign(:board_loading, false)
          |> assign(:board_error, "No project configured")

        project ->
          dispatch_labels = Config.tracker_labels(project.config) || []

          tracker_issues =
            case TrackerClient.fetch_all_issues(project.config, project.name, states: ["open"]) do
              {:ok, issues} -> issues
              {:error, _} -> []
            end

          db_id = resolve_db_id(project)

          db_issues =
            if db_id do
              try do
                Issues.list_issues(db_id)
                |> Enum.reject(fn i -> i.state in ["done", "cancelled"] end)
                |> Enum.map(&db_issue_to_tracker_issue(&1, project.name))
              catch
                _, _ -> []
              end
            else
              []
            end

          # Merge, deduplicating by id
          tracker_ids = MapSet.new(tracker_issues, & &1.id)

          merged =
            tracker_issues ++
              Enum.reject(db_issues, fn i -> MapSet.member?(tracker_ids, i.id) end)

          board_issues =
            categorize_by_state(
              merged,
              project.name,
              dispatch_labels,
              socket.assigns.running,
              socket.assigns.retry_attempts,
              socket.assigns.awaiting_review
            )

          socket
          |> assign(:board_issues, board_issues)
          |> assign(:board_loading, false)
          |> assign(:board_error, nil)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agents_updated}, socket) do
    {:noreply, assign(socket, :agents, Settings.list_agents())}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    Orchestrator.refresh()
    send(self(), :load_board)
    {:noreply, assign(socket, :board_loading, true)}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    Orchestrator.reset_state()
    {:noreply, socket}
  end

  @impl true
  def handle_event("move_card", params, socket) do
    %{
      "issue_id" => issue_id,
      "from_column" => from_col,
      "to_column" => to_col
    } = params

    allowed_transitions = [{"backlog", "queue"}, {"queue", "backlog"}]

    if {from_col, to_col} in allowed_transitions do
      # Persist state transition to DB
      new_state = if to_col == "queue", do: "queued", else: "backlog"

      case Issues.get_issue(issue_id) do
        nil ->
          {:noreply, socket}

        db_issue ->
          case Issues.transition_state(db_issue, new_state) do
            {:ok, _} ->
              project = resolve_project(socket)

              dispatch_labels =
                if project, do: Config.tracker_labels(project.config) || [], else: []

              # Optimistic update
              socket = move_card_in_assigns(socket, issue_id, from_col, to_col, dispatch_labels)

              # Async label update on tracker
              if project do
                config = project.config
                project_name = project.name

                Task.start(fn ->
                  case {from_col, to_col} do
                    {"backlog", "queue"} ->
                      Enum.each(dispatch_labels, fn label ->
                        TrackerClient.add_issue_label(config, project_name, issue_id, label)
                      end)

                    {"queue", "backlog"} ->
                      Enum.each(dispatch_labels, fn label ->
                        TrackerClient.remove_issue_label(config, project_name, issue_id, label)
                      end)
                  end
                end)
              end

              {:noreply, socket}

            {:error, :invalid_transition} ->
              {:noreply, put_flash(socket, :error, "Cannot move issue — state has changed")}
          end
      end
    else
      {:noreply, socket}
    end
  end

  # --- Modal events ---

  @impl true
  def handle_event("open_new_issue", _params, socket) do
    {:noreply, assign(socket, :modal, %{mode: :new, title: "", description: ""})}
  end

  @impl true
  def handle_event("open_issue", %{"id" => issue_id}, socket) do
    case Issues.get_issue(issue_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Issue not found")}

      issue ->
        {:noreply, assign(socket, :modal, %{mode: :view, issue: issue, dispatch_message: ""})}
    end
  end

  @impl true
  def handle_event("edit_issue", _params, socket) do
    issue = socket.assigns.modal.issue

    {:noreply,
     assign(socket, :modal, %{
       mode: :edit,
       issue: issue,
       title: issue.title,
       description: issue.description || ""
     })}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :modal, nil)}
  end

  @impl true
  def handle_event("save_new_issue", %{"title" => title, "description" => description}, socket) do
    title = String.trim(title)

    if title == "" do
      {:noreply, put_flash(socket, :error, "Title cannot be empty")}
    else
      db_id = resolve_db_id(resolve_project(socket))

      case db_id do
        nil ->
          {:noreply, put_flash(socket, :error, "No project selected")}

        db_id ->
          attrs = %{title: title, project_id: db_id}

          attrs =
            if String.trim(description) != "",
              do: Map.put(attrs, :description, String.trim(description)),
              else: attrs

          case Issues.create_issue(attrs) do
            {:ok, _issue} ->
              send(self(), :load_board)
              {:noreply, socket |> assign(:modal, nil) |> put_flash(:info, "Issue created")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to create issue")}
          end
      end
    end
  end

  @impl true
  def handle_event("save_edit_issue", %{"title" => title, "description" => description}, socket) do
    title = String.trim(title)
    issue = socket.assigns.modal.issue

    if title == "" do
      {:noreply, put_flash(socket, :error, "Title cannot be empty")}
    else
      attrs = %{title: title, description: String.trim(description)}

      case Issues.update_issue(issue, attrs) do
        {:ok, updated} ->
          send(self(), :load_board)

          {:noreply,
           socket
           |> assign(:modal, %{mode: :view, issue: updated, dispatch_message: ""})
           |> put_flash(:info, "Issue updated")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update issue")}
      end
    end
  end

  @impl true
  def handle_event("dispatch_issue", %{"dispatch" => %{"message" => message}}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, put_flash(socket, :error, "Dispatch message cannot be empty")}
    else
      issue = socket.assigns.modal.issue
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
          send(self(), :load_board)

          {:noreply,
           socket
           |> assign(:modal, nil)
           |> put_flash(
             :info,
             "Issue dispatched" <> if(agent_name, do: " to #{agent_name}", else: "")
           )}

        {:error, :invalid_transition} ->
          {:noreply, put_flash(socket, :error, "Cannot dispatch from current state")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to dispatch issue")}
      end
    end
  end

  @impl true
  def handle_event("delete_issue", %{"id" => issue_id}, socket) do
    case Issues.get_issue(issue_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Issue not found")}

      issue ->
        case Issues.delete_issue(issue) do
          {:ok, _} ->
            send(self(), :load_board)
            {:noreply, socket |> assign(:modal, nil) |> put_flash(:info, "Issue deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete issue")}
        end
    end
  end

  # --- Board helpers ---

  defp resolve_project(socket) do
    projects = socket.assigns.projects
    current = socket.assigns.current_project

    cond do
      current && Map.has_key?(projects, current) ->
        Map.get(projects, current)

      map_size(projects) > 0 ->
        projects |> Map.values() |> List.first()

      true ->
        nil
    end
  end

  defp resolve_db_id(nil), do: nil

  defp resolve_db_id(project) do
    Map.get(project, :db_id) ||
      case Settings.get_project_by_name(project.name) do
        %{id: id} -> id
        _ -> nil
      end
  end

  defp categorize_by_state(
         issues,
         project_name,
         dispatch_labels,
         running,
         retry_attempts,
         awaiting_review
       ) do
    base = %{"backlog" => [], "queue" => [], "in_progress" => [], "human_review" => []}

    Enum.reduce(issues, base, fn issue, acc ->
      key = "#{project_name}:#{issue.id}"

      column =
        cond do
          Map.has_key?(running, key) or Map.has_key?(retry_attempts, key) ->
            "in_progress"

          Map.has_key?(awaiting_review, key) ->
            "human_review"

          issue.state in ["in_progress"] ->
            "in_progress"

          issue.state in ["awaiting_review"] ->
            "human_review"

          issue.state in ["queued"] ->
            "queue"

          dispatch_labels != [] and Enum.any?(dispatch_labels, &(&1 in issue.labels)) ->
            "queue"

          true ->
            "backlog"
        end

      Map.update!(acc, column, fn existing -> existing ++ [issue] end)
    end)
  end

  defp recategorize_from_assigns(socket, project_name, dispatch_labels) do
    all_issues =
      socket.assigns.board_issues
      |> Map.values()
      |> List.flatten()

    categorize_by_state(
      all_issues,
      project_name,
      dispatch_labels,
      socket.assigns.running,
      socket.assigns.retry_attempts,
      socket.assigns.awaiting_review
    )
  end

  defp move_card_in_assigns(socket, issue_id, from_col, to_col, dispatch_labels) do
    board_issues = socket.assigns.board_issues

    {card, from_list} =
      case Map.get(board_issues, from_col, []) do
        issues ->
          case Enum.split_with(issues, fn i -> i.id == issue_id end) do
            {[card], rest} -> {card, rest}
            _ -> {nil, issues}
          end
      end

    if card do
      updated_labels =
        case {from_col, to_col} do
          {"backlog", "queue"} ->
            Enum.uniq(card.labels ++ dispatch_labels)

          {"queue", "backlog"} ->
            Enum.reject(card.labels, &(&1 in dispatch_labels))

          _ ->
            card.labels
        end

      card = %{card | labels: updated_labels}
      to_list = Map.get(board_issues, to_col, []) ++ [card]

      board_issues =
        board_issues
        |> Map.put(from_col, from_list)
        |> Map.put(to_col, to_list)

      assign(socket, :board_issues, board_issues)
    else
      socket
    end
  end

  defp issue_status(issue, running, retry_attempts, awaiting_review) do
    Enum.find_value(running, fn {_key, entry} ->
      if entry.issue_id == issue.id, do: {:running, entry}
    end) ||
      Enum.find_value(retry_attempts, fn {_key, entry} ->
        if entry.issue_id == issue.id, do: {:retry, entry}
      end) ||
      Enum.find_value(awaiting_review, fn {_key, entry} ->
        if entry.issue_id == issue.id, do: {:review, entry}
      end)
  end

  defp db_issue_to_tracker_issue(db_issue, project_name) do
    %Synkade.Tracker.Issue{
      project_name: project_name,
      id: db_issue.id,
      identifier: "#{project_name}##{db_issue.id |> String.slice(0..7)}",
      title: db_issue.title,
      description: db_issue.description,
      state: db_issue.state,
      priority: db_issue.priority,
      labels: [],
      blocked_by: [],
      created_at: db_issue.inserted_at,
      updated_at: db_issue.updated_at
    }
  end

  defp is_db_issue?(issue_id) do
    # DB issue IDs are UUIDs (36 chars with hyphens)
    String.length(issue_id) == 36 and String.contains?(issue_id, "-")
  end

  defp draggable?(col_id), do: col_id in ["backlog", "queue"]

  # --- Render ---

  @impl true
  def render(assigns) do
    filtered_running =
      if assigns.current_project,
        do:
          Map.filter(assigns.running, fn {_k, e} -> e.project_name == assigns.current_project end),
        else: assigns.running

    filtered_retries =
      if assigns.current_project,
        do:
          Map.filter(assigns.retry_attempts, fn {_k, e} ->
            e.project_name == assigns.current_project
          end),
        else: assigns.retry_attempts

    filtered_awaiting =
      if assigns.current_project,
        do:
          Map.filter(assigns.awaiting_review, fn {_k, e} ->
            e.project_name == assigns.current_project
          end),
        else: assigns.awaiting_review

    display_totals =
      if assigns.current_project do
        case Map.get(assigns.agent_totals_by_project, assigns.current_project) do
          nil -> %{total_tokens: 0, runtime_seconds: 0.0}
          totals -> totals
        end
      else
        assigns.agent_totals
      end

    assigns =
      assigns
      |> assign(:filtered_running, filtered_running)
      |> assign(:filtered_retries, filtered_retries)
      |> assign(:filtered_awaiting, filtered_awaiting)
      |> assign(:display_totals, display_totals)

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
          <h1 class="text-2xl font-bold">
            {if @current_project, do: @current_project, else: "Board"}
          </h1>
          <div class="flex items-center gap-3">
            <div class="flex items-center gap-4 text-sm">
              <span class="badge badge-info badge-sm gap-1">
                {map_size(@filtered_running)} running
              </span>
              <span class="badge badge-warning badge-sm gap-1">
                {map_size(@filtered_awaiting)} review
              </span>
              <span class="badge badge-error badge-sm gap-1">
                {map_size(@filtered_retries)} retries
              </span>
              <span class="text-base-content/60">
                {format_number(@display_totals.total_tokens)} tokens
              </span>
              <span class="text-base-content/60">
                {format_duration(@display_totals.runtime_seconds)}
              </span>
            </div>
            <button phx-click="refresh" class="btn btn-sm btn-primary">
              <span :if={@board_loading} class="loading loading-spinner loading-xs"></span> Refresh
            </button>
            <button phx-click="reset" class="btn btn-sm btn-warning" title="Reset orchestrator state">
              Reset Agent
            </button>
          </div>
        </div>

        <%= if @config_error do %>
          <div class="alert alert-error mb-4">
            <span>Config Error: {@config_error}</span>
          </div>
        <% end %>

        <%= if @board_error do %>
          <div class="alert alert-warning mb-4">
            <span>{@board_error}</span>
          </div>
        <% end %>
        
    <!-- Kanban Board -->
        <div
          id="kanban-board"
          phx-hook="KanbanDrag"
          class="flex gap-4 overflow-x-auto pb-4"
          style="min-height: 60vh;"
        >
          <%= for col <- @board_columns do %>
            <div
              class="kanban-column flex-shrink-0 w-72 bg-base-200 rounded-lg p-3"
              data-column={col["id"]}
              data-droppable={to_string(draggable?(col["id"]))}
            >
              <div class="flex items-center justify-between mb-3">
                <h3 class="font-semibold text-sm">
                  {col["name"]}
                  <span
                    :if={col["id"] in ["in_progress", "human_review"]}
                    class="text-xs text-base-content/40 font-normal ml-1"
                  >
                    auto
                  </span>
                </h3>
                <div class="flex items-center gap-1">
                  <span class="badge badge-ghost badge-sm">
                    {length(Map.get(@board_issues, col["id"], []))}
                  </span>
                  <button
                    :if={col["id"] == "backlog"}
                    phx-click="open_new_issue"
                    class="btn btn-ghost btn-xs btn-circle"
                    title="New issue"
                  >
                    +
                  </button>
                </div>
              </div>
              <div class="kanban-drop-zone flex flex-col gap-2 min-h-[100px]">
                <%= for issue <- Map.get(@board_issues, col["id"], []) do %>
                  <.issue_card
                    issue={issue}
                    column={col["id"]}
                    draggable={draggable?(col["id"])}
                    status={
                      issue_status(issue, @filtered_running, @filtered_retries, @filtered_awaiting)
                    }
                    clickable={col["id"] == "backlog" && is_db_issue?(issue.id)}
                  />
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
    <!-- Modal -->
      <.issue_modal :if={@modal} modal={@modal} agents={@agents} />
    </Layouts.app>
    """
  end

  # --- Components ---

  attr :modal, :map, required: true
  attr :agents, :list, required: true

  defp issue_modal(assigns) do
    ~H"""
    <div class="modal modal-open" phx-window-keydown="close_modal" phx-key="Escape">
      <div class="modal-box max-w-lg">
        <%= case @modal.mode do %>
          <% :new -> %>
            <h3 class="font-bold text-lg mb-4">New Issue</h3>
            <form phx-submit="save_new_issue">
              <div class="form-control mb-3">
                <input
                  type="text"
                  name="title"
                  placeholder="Issue title"
                  class="input input-bordered w-full"
                  autofocus
                />
              </div>
              <div class="form-control mb-4">
                <textarea
                  name="description"
                  placeholder="Description (optional)"
                  class="textarea textarea-bordered w-full"
                  rows="4"
                ></textarea>
              </div>
              <div class="modal-action">
                <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary">Create</button>
              </div>
            </form>
          <% :edit -> %>
            <h3 class="font-bold text-lg mb-4">Edit Issue</h3>
            <form phx-submit="save_edit_issue">
              <div class="form-control mb-3">
                <input
                  type="text"
                  name="title"
                  value={@modal.title}
                  class="input input-bordered w-full"
                  autofocus
                />
              </div>
              <div class="form-control mb-4">
                <textarea
                  name="description"
                  class="textarea textarea-bordered w-full"
                  rows="4"
                >{@modal.description}</textarea>
              </div>
              <div class="modal-action">
                <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary">Save</button>
              </div>
            </form>
          <% :view -> %>
            <div class="flex items-start justify-between mb-2">
              <h3 class="font-bold text-lg">{@modal.issue.title}</h3>
              <button phx-click="close_modal" class="btn btn-ghost btn-sm btn-circle">x</button>
            </div>
            <p
              :if={@modal.issue.description}
              class="text-sm whitespace-pre-wrap mb-4 text-base-content/70"
            >
              {@modal.issue.description}
            </p>
            <p :if={!@modal.issue.description} class="text-sm text-base-content/40 italic mb-4">
              No description
            </p>
            
    <!-- Dispatch input for backlog issues -->
            <div :if={@modal.issue.state == "backlog"} class="mb-4">
              <.form for={to_form(%{"message" => ""}, as: :dispatch)} phx-submit="dispatch_issue">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Dispatch to agent</span>
                  </label>
                  <div class="flex gap-2">
                    <input
                      type="text"
                      name="dispatch[message]"
                      placeholder="@agent instructions..."
                      class="input input-bordered input-sm flex-1"
                      list="modal-agent-names"
                      autocomplete="off"
                    />
                    <button type="submit" class="btn btn-sm btn-primary">Go</button>
                  </div>
                  <datalist id="modal-agent-names">
                    <option :for={agent <- @agents} value={"@#{agent.name} "} />
                  </datalist>
                </div>
              </.form>
            </div>

            <div class="modal-action">
              <button
                phx-click="delete_issue"
                phx-value-id={@modal.issue.id}
                class="btn btn-error btn-ghost btn-sm"
                data-confirm="Delete this issue?"
              >
                Delete
              </button>
              <button phx-click="edit_issue" class="btn btn-ghost btn-sm">Edit</button>
              <button phx-click="close_modal" class="btn btn-sm">Close</button>
            </div>
        <% end %>
      </div>
      <div class="modal-backdrop" phx-click="close_modal"></div>
    </div>
    """
  end

  attr :issue, :map, required: true
  attr :column, :string, required: true
  attr :draggable, :boolean, default: true
  attr :status, :any, default: nil
  attr :clickable, :boolean, default: false

  defp issue_card(assigns) do
    ~H"""
    <div
      class={[
        "kanban-card card card-compact bg-base-100 shadow-sm",
        if(@draggable, do: "cursor-grab active:cursor-grabbing", else: "cursor-default"),
        @clickable && "hover:ring-1 hover:ring-primary/30"
      ]}
      draggable={to_string(@draggable)}
      data-issue-id={@issue.id}
      data-column={@column}
      phx-click={@clickable && "open_issue"}
      phx-value-id={@clickable && @issue.id}
    >
      <div class="card-body p-3">
        <div class="flex items-start justify-between gap-2">
          <div class="flex-1 min-w-0">
            <p class="text-xs text-base-content/50 font-mono">{@issue.identifier}</p>
            <p class="text-sm font-medium leading-tight truncate">{@issue.title}</p>
          </div>
          <%= if @issue.priority do %>
            <span class={[
              "badge badge-xs flex-shrink-0",
              priority_badge_class(@issue.priority)
            ]}>
              P{@issue.priority}
            </span>
          <% end %>
        </div>

        <%= case @status do %>
          <% {:running, entry} -> %>
            <div class="mt-1 space-y-0.5">
              <div class="flex items-center gap-1">
                <span class="loading loading-spinner loading-xs text-info"></span>
                <span class="text-xs text-info">
                  {if entry[:agent_name], do: "#{entry.agent_name} — ", else: ""}Running
                </span>
                <span
                  :if={entry.last_agent_timestamp}
                  class="text-xs text-base-content/40 ml-auto"
                  title={"Last activity: #{format_relative_time(entry.last_agent_timestamp)}"}
                >
                  {format_relative_time(entry.last_agent_timestamp)}
                </span>
              </div>
              <p
                :if={entry.last_agent_message && entry.last_agent_message != ""}
                class="text-xs text-base-content/60 truncate"
                title={entry.last_agent_message}
              >
                {entry.last_agent_message}
              </p>
            </div>
          <% {:retry, entry} -> %>
            <div class="mt-1">
              <span class="badge badge-error badge-xs">Retry #{entry.attempt || 0}</span>
              <span :if={entry.agent_name} class="text-xs text-base-content/50 ml-1">
                {entry.agent_name}
              </span>
            </div>
          <% {:review, entry} -> %>
            <div class="mt-1">
              <a href={entry.pr_url} target="_blank" class="link link-primary text-xs">
                PR #{entry.pr_number}
              </a>
              <span :if={entry.agent_name} class="text-xs text-base-content/50 ml-1">
                {entry.agent_name}
              </span>
            </div>
          <% _ -> %>
        <% end %>

        <%= if @issue.url do %>
          <div class="mt-1">
            <a
              href={@issue.url}
              target="_blank"
              class="text-xs text-base-content/40 hover:text-base-content/60"
            >
              View issue
            </a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp priority_badge_class(1), do: "badge-error"
  defp priority_badge_class(2), do: "badge-warning"
  defp priority_badge_class(3), do: "badge-info"
  defp priority_badge_class(_), do: "badge-ghost"

  defp format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: to_string(n)

  defp format_duration(seconds) when is_float(seconds) do
    cond do
      seconds < 60 -> "#{trunc(seconds)}s"
      seconds < 3600 -> "#{trunc(seconds / 60)}m #{rem(trunc(seconds), 60)}s"
      true -> "#{trunc(seconds / 3600)}h #{rem(trunc(seconds / 60), 60)}m"
    end
  end

  defp format_duration(_), do: "0s"

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
end
