defmodule SynkadeWeb.IssueLiveHelpers do
  @moduledoc """
  Shared helpers for IssuesLive and DashboardLive.

  Extracts duplicated logic for issue detail loading, session management,
  dispatch parsing, and common UI helpers.
  """

  import Phoenix.Component, only: [assign: 3]
  alias Synkade.{Issues, Settings}
  alias Synkade.Issues.DispatchParser

  # --- Session management ---

  @doc """
  Subscribe to agent events for an in-progress issue and load past events.
  Unsubscribes from any previous session first.
  """
  def load_issue_detail(socket, issue_id, fallback_view_mode) do
    case Issues.get_issue(issue_id) do
      nil ->
        socket
        |> assign(:selected_issue, nil)
        |> assign(:view_mode, fallback_view_mode)

      issue ->
        ancestors = Issues.ancestor_chain(issue)

        # Unsubscribe from previous session
        socket = unsubscribe_session(socket)

        # Subscribe to agent events if issue is in_progress
        socket =
          if issue.state == "in_progress" do
            running_entry = find_running_entry(socket.assigns.running, issue_id)

            if running_entry do
              topic = "agent_events:#{issue_id}"
              Phoenix.PubSub.subscribe(Synkade.PubSub, topic)
              past_events = []

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

        # Check PR status on load for awaiting_review issues
        # PR status is now checked by ReconcileWorker cron job
        :ok

        socket
        |> assign(:selected_issue, %{issue: issue, ancestors: ancestors})
        |> assign(:view_mode, :detail)
        |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
    end
  end

  @doc """
  Initialize the create issue view with parent chain and default agent.
  `resolve_project_id` is a function that returns the project_id given the socket.
  """
  def init_create_view(socket, params, resolve_project_id) do
    parent_id = params["parent_id"]
    project_id = resolve_project_id.(socket)

    changeset = Issues.change_issue(%Issues.Issue{}, %{parent_id: parent_id})

    create_ancestors =
      case parent_id do
        nil ->
          []

        id ->
          case Issues.get_issue(id) do
            nil -> []
            parent -> Issues.ancestor_chain(parent) ++ [parent]
          end
      end

    socket = unsubscribe_session(socket)

    default_agent_id =
      case socket.assigns.agents do
        [first | _] -> first.id
        [] -> nil
      end

    socket
    |> assign(:view_mode, :create)
    |> assign(:selected_issue, nil)
    |> assign(:form, to_form(changeset))
    |> assign(:form_parent_id, parent_id)
    |> assign(:form_project_id, project_id)
    |> assign(:create_ancestors, create_ancestors)
    |> assign(:selected_agent_id, default_agent_id)
  end

  @doc "Unsubscribe from current agent events session and clear assigns."
  def unsubscribe_session(socket) do
    case socket.assigns.session_subscribed do
      nil ->
        socket

      issue_id ->
        topic = "agent_events:#{issue_id}"
        Phoenix.PubSub.unsubscribe(Synkade.PubSub, topic)

        socket
        |> assign(:session_events, [])
        |> assign(:session_id, nil)
        |> assign(:session_subscribed, nil)
    end
  end

  @doc "Find a running entry by issue_id across all running entries."
  def find_running_entry(running, issue_id) do
    Enum.find_value(running, fn {_key, entry} ->
      if entry.issue_id == issue_id, do: entry
    end)
  end

  @doc """
  Update session tracking when orchestrator state changes.
  If the issue is still running, update session_id. Otherwise unsubscribe.
  """
  def update_session_from_snapshot(socket, snapshot) do
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
  end

  # --- Dispatch helpers ---

  @doc """
  Parse a dispatch message for @agent targeting and resolve the agent_id.
  Returns {agent_name, instruction, agent_id}.
  """
  def resolve_dispatch(%Synkade.Accounts.Scope{} = scope, message) do
    {agent_name, instruction} = DispatchParser.parse(message)

    agent_id =
      case agent_name do
        nil ->
          nil

        name ->
          case Settings.get_agent_by_name(scope, name) do
            nil -> nil
            agent -> agent.id
          end
      end

    {agent_name, instruction, agent_id}
  end

  # --- Issue data helpers ---

  @doc "Reload a selected issue from DB, or clear it if deleted."
  def reload_selected_issue(socket, fallback_view_mode) do
    case socket.assigns.selected_issue do
      nil ->
        socket

      %{issue: issue} ->
        case Issues.get_issue(issue.id) do
          nil ->
            socket
            |> assign(:selected_issue, nil)
            |> assign(:view_mode, fallback_view_mode)

          updated ->
            ancestors = Issues.ancestor_chain(updated)
            assign(socket, :selected_issue, %{issue: updated, ancestors: ancestors})
        end
    end
  end

  @doc "Add parent_id to issue params if present."
  def maybe_put_parent(params, nil), do: params
  def maybe_put_parent(params, parent_id), do: Map.put(params, "parent_id", parent_id)

  # --- Formatting helpers ---

  @doc "CSS class for issue state badges."
  def state_badge_class("backlog"), do: "badge-ghost"
  def state_badge_class("queued"), do: "badge-info"
  def state_badge_class("in_progress"), do: "badge-warning"
  def state_badge_class("awaiting_review"), do: "badge-secondary"
  def state_badge_class("done"), do: "badge-success"
  def state_badge_class("cancelled"), do: "badge-error"
  def state_badge_class(_), do: "badge-ghost"

  @doc "Format monotonic timestamp as relative time string."
  def format_relative_time(monotonic_ms) when is_integer(monotonic_ms) do
    elapsed_ms = System.monotonic_time(:millisecond) - monotonic_ms
    elapsed_s = div(elapsed_ms, 1000)

    cond do
      elapsed_s < 5 -> "just now"
      elapsed_s < 60 -> "#{elapsed_s}s ago"
      elapsed_s < 3600 -> "#{div(elapsed_s, 60)}m ago"
      true -> "#{div(elapsed_s, 3600)}h ago"
    end
  end

  def format_relative_time(_), do: nil

  # Private helper for form conversion
  defp to_form(data, opts \\ []) do
    Phoenix.Component.to_form(data, opts)
  end
end
