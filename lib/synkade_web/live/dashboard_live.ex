defmodule SynkadeWeb.DashboardLive do
  use SynkadeWeb, :live_view

  alias Synkade.Orchestrator
  alias Synkade.Tracker.Client, as: TrackerClient
  alias Synkade.Workflow.Config

  @board_poll_interval 30_000

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
      |> assign(:activity_log, state.activity_log)
      |> assign(:board_columns, [])
      |> assign(:board_issues, %{})
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
    {:noreply,
     socket
     |> assign(:running, snapshot.running)
     |> assign(:retry_attempts, snapshot.retry_attempts)
     |> assign(:awaiting_review, snapshot.awaiting_review)
     |> assign(:agent_totals, snapshot.agent_totals)
     |> assign(:agent_totals_by_project, snapshot.agent_totals_by_project)
     |> assign(:projects, snapshot.projects)
     |> assign(:workflow_error, snapshot.workflow_error)
     |> assign(:activity_log, snapshot.activity_log)}
  end

  @impl true
  def handle_info(:load_board, socket) do
    project = resolve_project(socket)

    socket =
      case project do
        nil ->
          socket
          |> assign(:board_columns, [])
          |> assign(:board_issues, %{})
          |> assign(:board_loading, false)
          |> assign(:board_error, "No project configured")

        project ->
          columns = Config.kanban_columns(project.config)
          uncategorized = Config.kanban_uncategorized_column(project.config)

          case TrackerClient.fetch_all_issues(project.config, project.name, states: ["open"]) do
            {:ok, issues} ->
              board_issues = categorize_issues(issues, columns, uncategorized)

              socket
              |> assign(:board_columns, columns)
              |> assign(:board_issues, board_issues)
              |> assign(:board_loading, false)
              |> assign(:board_error, nil)

            {:error, reason} ->
              socket
              |> assign(:board_columns, columns)
              |> assign(:board_loading, false)
              |> assign(:board_error, "Failed to load issues: #{inspect(reason)}")
          end
      end

    Process.send_after(self(), :load_board, @board_poll_interval)
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
      "from_column" => from_label,
      "to_column" => to_label
    } = params

    if from_label == to_label do
      {:noreply, socket}
    else
      # Optimistic update
      socket = move_card_in_assigns(socket, issue_id, from_label, to_label)

      # Async label update on tracker
      project = resolve_project(socket)

      if project do
        config = project.config
        project_name = project.name

        Task.start(fn ->
          TrackerClient.remove_issue_label(config, project_name, issue_id, from_label)
          TrackerClient.add_issue_label(config, project_name, issue_id, to_label)
        end)
      end

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

  defp categorize_issues(issues, columns, uncategorized) do
    column_labels = Enum.map(columns, & &1["label"])

    # Initialize empty lists for each column
    base = Map.new(column_labels, fn label -> {label, []} end)

    # Find uncategorized column label
    uncategorized_label =
      case Enum.find(columns, fn col -> col["name"] == uncategorized end) do
        %{"label" => label} -> label
        _ -> List.first(column_labels)
      end

    Enum.reduce(issues, base, fn issue, acc ->
      matched_label =
        Enum.find(column_labels, fn col_label ->
          col_label in issue.labels
        end)

      target = matched_label || uncategorized_label

      Map.update(acc, target, [issue], fn existing -> existing ++ [issue] end)
    end)
  end

  defp move_card_in_assigns(socket, issue_id, from_label, to_label) do
    board_issues = socket.assigns.board_issues

    {card, from_list} =
      case Map.get(board_issues, from_label, []) do
        issues ->
          case Enum.split_with(issues, fn i -> i.id == issue_id end) do
            {[card], rest} -> {card, rest}
            _ -> {nil, issues}
          end
      end

    if card do
      # Update card labels
      updated_labels =
        card.labels
        |> List.delete(from_label)
        |> then(fn labels -> [to_label | labels] end)

      card = %{card | labels: updated_labels}

      to_list = Map.get(board_issues, to_label, []) ++ [card]

      board_issues =
        board_issues
        |> Map.put(from_label, from_list)
        |> Map.put(to_label, to_list)

      assign(socket, :board_issues, board_issues)
    else
      socket
    end
  end

  defp issue_status(issue, running, retry_attempts, awaiting_review) do
    # Check if this issue has orchestrator status
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

        <.activity_graph activity_log={@activity_log} current_project={@current_project} />

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
              data-column={col["label"]}
            >
              <div class="flex items-center justify-between mb-3">
                <h3 class="font-semibold text-sm">{col["name"]}</h3>
                <span class="badge badge-ghost badge-sm">
                  {length(Map.get(@board_issues, col["label"], []))}
                </span>
              </div>
              <div class="kanban-drop-zone flex flex-col gap-2 min-h-[100px]">
                <%= for issue <- Map.get(@board_issues, col["label"], []) do %>
                  <.issue_card
                    issue={issue}
                    column={col["label"]}
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
  attr :status, :any, default: nil

  defp issue_card(assigns) do
    ~H"""
    <div
      class="kanban-card card card-compact bg-base-100 shadow-sm cursor-grab active:cursor-grabbing"
      draggable="true"
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

  attr :activity_log, :list, required: true
  attr :current_project, :string, default: nil

  defp activity_graph(assigns) do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)
    this_monday = Date.add(today, -(day_of_week - 1))
    start_date = Date.add(this_monday, -51 * 7)

    log =
      if assigns.current_project,
        do: Enum.filter(assigns.activity_log, &(&1.project_name == assigns.current_project)),
        else: assigns.activity_log

    counts =
      log
      |> Enum.map(&DateTime.to_date(&1.timestamp))
      |> Enum.frequencies()

    cells =
      for week <- 0..51, day <- 0..6 do
        date = Date.add(start_date, week * 7 + day)

        if Date.compare(date, today) != :gt do
          count = Map.get(counts, date, 0)
          {week, day, date, count}
        end
      end
      |> Enum.reject(&is_nil/1)

    assigns = assign(assigns, :cells, cells)

    ~H"""
    <div class="mb-4 overflow-x-auto">
      <svg viewBox="0 0 732 100" class="w-full max-w-3xl" role="img" aria-label="Activity graph">
        <%= for {week, day, date, count} <- @cells do %>
          <rect
            x={week * 14}
            y={day * 14}
            width="12"
            height="12"
            rx="2"
            style={cell_fill(count)}
          >
            <title>{Calendar.strftime(date, "%b %-d")}: {count} {if count == 1, do: "trigger", else: "triggers"}</title>
          </rect>
        <% end %>
      </svg>
    </div>
    """
  end

  defp cell_fill(0), do: "fill: oklch(var(--b3))"
  defp cell_fill(n) when n <= 2, do: "fill: oklch(var(--p) / 0.2)"
  defp cell_fill(n) when n <= 5, do: "fill: oklch(var(--p) / 0.5)"
  defp cell_fill(_), do: "fill: oklch(var(--p))"

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
