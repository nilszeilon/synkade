defmodule SynkadeWeb.DashboardLive do
  use SynkadeWeb, :live_view

  alias Synkade.Orchestrator

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())
    end

    state = Orchestrator.get_state()

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_tab, :dashboard)
     |> assign(:current_project, nil)
     |> assign(:running, state.running)
     |> assign(:retry_attempts, state.retry_attempts)
     |> assign(:agent_totals, state.agent_totals)
     |> assign(:agent_totals_by_project, state.agent_totals_by_project)
     |> assign(:projects, state.projects)
     |> assign(:workflow_error, state.workflow_error)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :current_project, params["project"])}
  end

  @impl true
  def handle_info({:state_changed, snapshot}, socket) do
    {:noreply,
     socket
     |> assign(:running, snapshot.running)
     |> assign(:retry_attempts, snapshot.retry_attempts)
     |> assign(:agent_totals, snapshot.agent_totals)
     |> assign(:agent_totals_by_project, snapshot.agent_totals_by_project)
     |> assign(:projects, snapshot.projects)
     |> assign(:workflow_error, snapshot.workflow_error)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    Orchestrator.refresh()
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    filtered_running =
      if assigns.current_project,
        do: Map.filter(assigns.running, fn {_k, e} -> e.project_name == assigns.current_project end),
        else: assigns.running

    filtered_retries =
      if assigns.current_project,
        do: Map.filter(assigns.retry_attempts, fn {_k, e} -> e.project_name == assigns.current_project end),
        else: assigns.retry_attempts

    filtered_totals_by_project =
      if assigns.current_project,
        do: Map.take(assigns.agent_totals_by_project, [assigns.current_project]),
        else: assigns.agent_totals_by_project

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
      |> assign(:filtered_totals_by_project, filtered_totals_by_project)
      |> assign(:display_totals, display_totals)

    ~H"""
    <Layouts.app
      flash={@flash}
      projects={@projects}
      running={@running}
      active_tab={@active_tab}
      current_project={@current_project}
    >
      <div class="px-6 py-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold">
            {if @current_project, do: @current_project, else: "Overview"}
          </h1>
          <button phx-click="refresh" class="btn btn-sm btn-primary">Refresh</button>
        </div>

        <%= if @workflow_error do %>
          <div class="alert alert-error mb-4">
            <span>Workflow Error: {@workflow_error}</span>
          </div>
        <% end %>

        <!-- Agent Totals -->
        <div class="grid grid-cols-4 gap-4 mb-6">
          <div class="stats shadow">
            <div class="stat">
              <div class="stat-title">Running</div>
              <div class="stat-value">{map_size(@filtered_running)}</div>
            </div>
          </div>
          <div class="stats shadow">
            <div class="stat">
              <div class="stat-title">Retry Queue</div>
              <div class="stat-value">{map_size(@filtered_retries)}</div>
            </div>
          </div>
          <div class="stats shadow">
            <div class="stat">
              <div class="stat-title">Total Tokens</div>
              <div class="stat-value text-lg">{format_number(@display_totals.total_tokens)}</div>
            </div>
          </div>
          <div class="stats shadow">
            <div class="stat">
              <div class="stat-title">Runtime</div>
              <div class="stat-value text-lg">{format_duration(@display_totals.runtime_seconds)}</div>
            </div>
          </div>
        </div>

        <!-- Running Sessions -->
        <div class="mb-6">
          <h2 class="text-xl font-semibold mb-3">Running Sessions</h2>
          <%= if map_size(@filtered_running) == 0 do %>
            <p class="text-base-content/60">No active sessions.</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Project</th>
                    <th>Issue</th>
                    <th>Session</th>
                    <th>Turns</th>
                    <th>Tokens</th>
                    <th>Last Event</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {_key, entry} <- @filtered_running do %>
                    <tr>
                      <td>{entry.project_name}</td>
                      <td>{entry.identifier}</td>
                      <td class="font-mono text-xs">{entry.session_id || "-"}</td>
                      <td>{entry.turn_count}</td>
                      <td>{format_number(entry.agent_total_tokens)}</td>
                      <td>{entry.last_agent_event || "-"}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <!-- Retry Queue -->
        <div class="mb-6">
          <h2 class="text-xl font-semibold mb-3">Retry Queue</h2>
          <%= if map_size(@filtered_retries) == 0 do %>
            <p class="text-base-content/60">No pending retries.</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Project</th>
                    <th>Issue</th>
                    <th>Attempt</th>
                    <th>Error</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {_key, entry} <- @filtered_retries do %>
                    <tr>
                      <td>{entry.project_name}</td>
                      <td>{entry.identifier}</td>
                      <td>{entry.attempt}</td>
                      <td class="text-xs">{entry.error || "-"}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <!-- Per-Project Stats -->
        <div :if={!@current_project} class="mb-6">
          <h2 class="text-xl font-semibold mb-3">Projects</h2>
          <%= if map_size(@filtered_totals_by_project) == 0 do %>
            <p class="text-base-content/60">No project data yet.</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Project</th>
                    <th>Total Tokens</th>
                    <th>Runtime</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {name, totals} <- @filtered_totals_by_project do %>
                    <tr>
                      <td>{name}</td>
                      <td>{format_number(totals.total_tokens)}</td>
                      <td>{format_duration(totals.runtime_seconds)}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

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
