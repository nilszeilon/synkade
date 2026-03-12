defmodule SynkadeWeb.LogsLive do
  use SynkadeWeb, :live_view

  alias Synkade.{LogBroadcaster, Orchestrator}

  @max_entries 1000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, LogBroadcaster.topic())
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())
    end

    entries = LogBroadcaster.recent_entries(500)
    orc_state = Orchestrator.get_state()

    {:ok,
     socket
     |> assign(:page_title, "Logs")
     |> assign(:active_tab, :logs)
     |> assign(:current_project, nil)
     |> assign(:projects, orc_state.projects)
     |> assign(:running, orc_state.running)
     |> assign(:entries, entries)
     |> assign(:level_filter, :all)
     |> assign(:paused, false)
     |> assign(:search, "")}
  end

  @impl true
  def handle_info({:log_entry, entry}, socket) do
    if socket.assigns.paused do
      {:noreply, socket}
    else
      entries =
        (socket.assigns.entries ++ [entry])
        |> Enum.take(-@max_entries)

      {:noreply, assign(socket, :entries, entries)}
    end
  end

  @impl true
  def handle_info({:state_changed, snapshot}, socket) do
    {:noreply,
     socket
     |> assign(:projects, snapshot.projects)
     |> assign(:running, snapshot.running)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter_level", %{"level" => level}, socket) do
    level_atom =
      case level do
        "all" -> :all
        "info" -> :info
        "warning" -> :warning
        "error" -> :error
        _ -> :all
      end

    {:noreply, assign(socket, :level_filter, level_atom)}
  end

  @impl true
  def handle_event("toggle_pause", _params, socket) do
    {:noreply, assign(socket, :paused, !socket.assigns.paused)}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, :entries, [])}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    {:noreply, assign(socket, :search, query)}
  end

  defp filtered_entries(entries, level_filter, search) do
    entries
    |> filter_by_level(level_filter)
    |> filter_by_search(search)
  end

  defp filter_by_level(entries, :all), do: entries
  defp filter_by_level(entries, level), do: Enum.filter(entries, &(&1.level == level))

  defp filter_by_search(entries, ""), do: entries

  defp filter_by_search(entries, search) do
    downcased = String.downcase(search)

    Enum.filter(entries, fn entry ->
      String.contains?(String.downcase(entry.message), downcased) ||
        (entry.module && String.contains?(String.downcase(entry.module), downcased))
    end)
  end

  defp level_badge_class(:error), do: "badge badge-error badge-xs"
  defp level_badge_class(:warning), do: "badge badge-warning badge-xs"
  defp level_badge_class(:info), do: "badge badge-info badge-xs"
  defp level_badge_class(:debug), do: "badge badge-ghost badge-xs"
  defp level_badge_class(_), do: "badge badge-ghost badge-xs"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S.") <> pad_ms(dt.microsecond)
  end

  defp format_time(_), do: "--:--:--"

  defp pad_ms({us, _precision}),
    do: us |> div(1000) |> Integer.to_string() |> String.pad_leading(3, "0")

  @impl true
  def render(assigns) do
    filtered = filtered_entries(assigns.entries, assigns.level_filter, assigns.search)
    assigns = assign(assigns, :filtered, filtered)

    ~H"""
    <div class="flex flex-col h-screen">
      <%!-- Header --%>
      <div class="flex items-center justify-between border-b border-base-300 px-6 py-3 bg-base-100">
        <div class="flex items-center gap-3">
          <h1 class="text-lg font-semibold">System Logs</h1>
          <span class="badge badge-ghost badge-sm">{length(@filtered)} entries</span>
        </div>

        <div class="flex items-center gap-2">
          <%!-- Search --%>
          <form phx-change="search" class="join">
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="Filter logs..."
              phx-debounce="300"
              class="input input-bordered input-sm join-item w-48"
            />
          </form>

          <%!-- Level filter --%>
          <div class="join">
            <button
              :for={level <- [:all, :info, :warning, :error]}
              phx-click="filter_level"
              phx-value-level={level}
              class={[
                "btn btn-xs join-item",
                @level_filter == level && "btn-active"
              ]}
            >
              {level |> to_string() |> String.capitalize()}
            </button>
          </div>

          <%!-- Pause/Clear --%>
          <button phx-click="toggle_pause" class={["btn btn-xs", @paused && "btn-warning"]}>
            <.icon name={if @paused, do: "hero-play", else: "hero-pause"} class="size-3" />
            {if @paused, do: "Resume", else: "Pause"}
          </button>

          <button phx-click="clear" class="btn btn-xs btn-ghost">
            <.icon name="hero-trash" class="size-3" /> Clear
          </button>
        </div>
      </div>

      <%!-- Log entries --%>
      <div
        id="log-container"
        phx-hook="AutoScroll"
        class="flex-1 overflow-y-auto font-mono text-xs bg-base-200 p-2"
      >
        <div :if={@filtered == []} class="text-center text-base-content/40 py-8">
          No log entries{if @level_filter != :all, do: " matching filter", else: ""}
        </div>

        <div
          :for={entry <- @filtered}
          id={"log-#{entry.id}"}
          class="flex gap-2 py-0.5 px-1 hover:bg-base-300 rounded"
        >
          <span class="text-base-content/40 whitespace-nowrap">{format_time(entry.timestamp)}</span>
          <span class={level_badge_class(entry.level)}>{entry.level}</span>
          <span :if={entry.module} class="text-primary/60 whitespace-nowrap truncate max-w-48">
            {entry.module}
          </span>
          <span class="text-base-content break-all">{entry.message}</span>
        </div>
      </div>
    </div>
    """
  end
end
