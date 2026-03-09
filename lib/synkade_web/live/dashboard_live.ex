defmodule SynkadeWeb.DashboardLive do
  use SynkadeWeb, :live_view

  alias Synkade.Orchestrator
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
      |> assign(:workflow_error, state.workflow_error)
      |> assign(:board_columns, @board_columns)
      |> assign(:board_issues, %{"backlog" => [], "queue" => [], "in_progress" => [], "human_review" => []})
      |> assign(:board_loading, true)
      |> assign(:board_error, nil)

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
      |> assign(:workflow_error, snapshot.workflow_error)

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
          |> assign(:board_issues, %{"backlog" => [], "queue" => [], "in_progress" => [], "human_review" => []})
          |> assign(:board_loading, false)
          |> assign(:board_error, "No project configured")

        project ->
          dispatch_labels = Config.tracker_labels(project.config) || []

          case TrackerClient.fetch_all_issues(project.config, project.name, states: ["open"]) do
            {:ok, issues} ->
              board_issues =
                categorize_by_state(
                  issues,
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

            {:error, reason} ->
              socket
              |> assign(:board_loading, false)
              |> assign(:board_error, "Failed to load issues: #{inspect(reason)}")
          end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    Orchestrator.refresh()
    send(self(), :load_board)
    {:noreply, assign(socket, :board_loading, true)}
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
      project = resolve_project(socket)
      dispatch_labels = if project, do: Config.tracker_labels(project.config) || [], else: []

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
    else
      {:noreply, socket}
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

  defp categorize_by_state(issues, project_name, dispatch_labels, running, retry_attempts, awaiting_review) do
    base = %{"backlog" => [], "queue" => [], "in_progress" => [], "human_review" => []}

    Enum.reduce(issues, base, fn issue, acc ->
      key = "#{project_name}:#{issue.id}"

      column =
        cond do
          Map.has_key?(running, key) or Map.has_key?(retry_attempts, key) ->
            "in_progress"

          Map.has_key?(awaiting_review, key) ->
            "human_review"

          dispatch_labels != [] and Enum.any?(dispatch_labels, &(&1 in issue.labels)) ->
            "queue"

          true ->
            "backlog"
        end

      Map.update!(acc, column, fn existing -> existing ++ [issue] end)
    end)
  end

  defp recategorize_from_assigns(socket, project_name, dispatch_labels) do
    # Collect all issues from all columns
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
      # Update card labels for optimistic UI
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

  defp draggable?(col_id), do: col_id in ["backlog", "queue"]

  # --- Render ---

  @impl true
  def render(assigns) do
    filtered_running =
      if assigns.current_project,
        do: Map.filter(assigns.running, fn {_k, e} -> e.project_name == assigns.current_project end),
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
              <span :if={@board_loading} class="loading loading-spinner loading-xs"></span>
              Refresh
            </button>
          </div>
        </div>

        <%= if @workflow_error do %>
          <div class="alert alert-error mb-4">
            <span>Workflow Error: {@workflow_error}</span>
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
                <span class="badge badge-ghost badge-sm">
                  {length(Map.get(@board_issues, col["id"], []))}
                </span>
              </div>
              <div class="kanban-drop-zone flex flex-col gap-2 min-h-[100px]">
                <%= for issue <- Map.get(@board_issues, col["id"], []) do %>
                  <.issue_card
                    issue={issue}
                    column={col["id"]}
                    draggable={draggable?(col["id"])}
                    status={issue_status(issue, @filtered_running, @filtered_retries, @filtered_awaiting)}
                  />
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :issue, :map, required: true
  attr :column, :string, required: true
  attr :draggable, :boolean, default: true
  attr :status, :any, default: nil

  defp issue_card(assigns) do
    ~H"""
    <div
      class={[
        "kanban-card card card-compact bg-base-100 shadow-sm",
        if(@draggable, do: "cursor-grab active:cursor-grabbing", else: "cursor-default")
      ]}
      draggable={to_string(@draggable)}
      data-issue-id={@issue.id}
      data-column={@column}
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
            <div class="flex items-center gap-1 mt-1">
              <span class="loading loading-spinner loading-xs text-info"></span>
              <span class="text-xs text-info">Running (turn {entry.turn_count || 0})</span>
            </div>
          <% {:retry, entry} -> %>
            <div class="mt-1">
              <span class="badge badge-error badge-xs">Retry #{entry.attempt || 0}</span>
            </div>
          <% {:review, entry} -> %>
            <div class="mt-1">
              <a href={entry.pr_url} target="_blank" class="link link-primary text-xs">
                PR #{entry.pr_number}
              </a>
            </div>
          <% _ -> %>
        <% end %>

        <%= if @issue.url do %>
          <div class="mt-1">
            <a href={@issue.url} target="_blank" class="text-xs text-base-content/40 hover:text-base-content/60">
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
end
