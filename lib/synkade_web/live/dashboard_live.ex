defmodule SynkadeWeb.DashboardLive do
  use SynkadeWeb, :live_view

  import SynkadeWeb.Components.IssueView
  import SynkadeWeb.Components.TokenChart
  import SynkadeWeb.IssueLiveHelpers

  alias Synkade.{Issues, Jobs, Settings}
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
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Jobs.pubsub_topic(scope))
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic(scope))
      Phoenix.PubSub.subscribe(Synkade.PubSub, Issues.pubsub_topic(scope.user.id))
    end

    state = Jobs.get_state(scope)

    socket =
      socket
      |> assign(:page_title, "Overview")
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
      |> assign(:agents, Settings.list_agents(scope))
      |> assign(:selected_agent_id, nil)
      |> assign(:view_mode, :board)
      |> assign(:selected_issue, nil)
      |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
      |> assign(:session_events, [])
      |> assign(:session_id, nil)
      |> assign(:session_subscribed, nil)
      |> assign(:form, nil)
      |> assign(:form_project_id, nil)
      |> assign(:form_parent_id, nil)
      |> assign(:create_ancestors, [])
      |> assign_chart_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, :current_project, params["project"])

    # Handle view mode from URL params
    socket =
      cond do
        params["issue"] ->
          load_issue_detail(socket, params["issue"], :board)

        params["new"] == "true" ->
          init_create_view(socket, params, fn s ->
            resolve_db_id(resolve_project(s), socket.assigns.current_scope)
          end)

        true ->
          socket = unsubscribe_session(socket)

          socket
          |> assign(:selected_issue, nil)
          |> assign(:view_mode, if(params["project"], do: :board, else: :overview))
      end

    if connected?(socket) && params["project"] && socket.assigns.view_mode not in [:detail, :create] do
      send(self(), :load_board)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:jobs_changed}, socket) do
    state = Jobs.get_state(socket.assigns.current_scope)

    socket =
      socket
      |> assign(:running, state.running)
      |> assign(:retry_attempts, state.retry_attempts)
      |> assign(:awaiting_review, state.awaiting_review)
      |> assign(:agent_totals, state.agent_totals)
      |> assign(:agent_totals_by_project, state.agent_totals_by_project)
      |> assign(:projects, state.projects)
      |> assign(:config_error, state.config_error)

    # Only re-query chart data on overview (chart not shown on project pages)
    socket =
      if socket.assigns.current_project do
        socket
      else
        assign_chart_data(socket)
      end

    # Re-categorize board issues if on a project page
    socket =
      if socket.assigns.current_project && socket.assigns.view_mode == :board do
        project = resolve_project(socket)

        if project do
          dispatch_labels = Config.tracker_labels(project.config) || []
          board_issues = recategorize_from_assigns(socket, project.name, dispatch_labels)
          assign(socket, :board_issues, board_issues)
        else
          socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_changed, snapshot}, socket) do
    socket =
      socket
      |> assign(:running, snapshot.running)
      |> assign(:retry_attempts, snapshot.retry_attempts)
      |> assign(:awaiting_review, Map.get(snapshot, :awaiting_review, %{}))
      |> assign(:agent_totals, Map.get(snapshot, :agent_totals, %{input_tokens: 0, output_tokens: 0, total_tokens: 0, runtime_seconds: 0.0}))
      |> assign(:agent_totals_by_project, Map.get(snapshot, :agent_totals_by_project, %{}))
      |> assign(:projects, snapshot.projects)
      |> assign(:config_error, snapshot.config_error)

    # Update session_id from running entry if viewing detail
    socket = update_session_from_snapshot(socket, snapshot)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:issues_updated}, socket) do
    if socket.assigns.current_project && socket.assigns.view_mode == :board do
      send(self(), :load_board)
    end

    socket = reload_selected_issue(socket, :board)

    socket =
      if !socket.assigns.current_project do
        assign_chart_data(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_board, socket) do
    project = resolve_project(socket)
    state = Jobs.get_state(socket.assigns.current_scope)

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

          db_id = resolve_db_id(project, socket.assigns.current_scope)

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
    {:noreply, assign(socket, :agents, Settings.list_agents(socket.assigns.current_scope))}
  end

  @impl true
  def handle_info({:theme_updated, theme}, socket) do
    {:noreply, push_event(socket, "set-theme", %{theme: theme})}
  end

  @impl true
  def handle_info({:settings_updated, _settings}, socket) do
    {:noreply, socket}
  end

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
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    Jobs.refresh(socket.assigns.current_scope)

    if socket.assigns.current_project do
      send(self(), :load_board)
      {:noreply, assign(socket, :board_loading, true)}
    else
      {:noreply, assign_chart_data(socket)}
    end
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

              socket = move_card_in_assigns(socket, issue_id, from_col, to_col, dispatch_labels)

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

  # --- Issue detail events (used by issue_full_view) ---

  @impl true
  def handle_event("select_issue", %{"id" => issue_id}, socket) do
    project_name = socket.assigns.current_project
    path = dashboard_path(project_name, issue_id)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("close_detail", _params, socket) do
    path = dashboard_path(socket.assigns.current_project)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("dispatch_issue", %{"dispatch" => %{"message" => message}}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, put_flash(socket, :error, "Dispatch message cannot be empty")}
    else
      issue =
        case socket.assigns do
          %{view_mode: :detail, selected_issue: %{issue: issue}} -> issue
          %{modal: %{issue: issue}} -> issue
        end

      {agent_name, instruction, agent_id} = resolve_dispatch(socket.assigns.current_scope, message)

      case Issues.dispatch_issue(issue, instruction, agent_id) do
        {:ok, _} ->
          send(self(), :load_board)

          socket =
            socket
            |> assign(:modal, nil)
            |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
            |> put_flash(
              :info,
              "Issue dispatched" <> if(agent_name, do: " to #{agent_name}", else: "")
            )

          if socket.assigns.view_mode == :detail do
            {:noreply, push_patch(socket, to: dashboard_path(socket.assigns.current_project))}
          else
            {:noreply, socket}
          end

        {:error, :invalid_transition} ->
          {:noreply, put_flash(socket, :error, "Cannot dispatch from current state")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to dispatch issue")}
      end
    end
  end

  @impl true
  def handle_event("cancel_issue", %{"id" => issue_id}, socket) do
    case Issues.get_issue(issue_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Issue not found")}

      issue ->
        case Issues.cancel_issue(issue) do
          {:ok, _} ->
            send(self(), :load_board)
            {:noreply, put_flash(socket, :info, "Issue cancelled")}

          {:error, :invalid_transition} ->
            {:noreply, put_flash(socket, :error, "Cannot cancel from current state")}
        end
    end
  end

  @impl true
  def handle_event("unqueue_issue", %{"id" => issue_id}, socket) do
    case Issues.get_issue(issue_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Issue not found")}

      issue ->
        case Issues.transition_state(issue, "backlog") do
          {:ok, _} ->
            send(self(), :load_board)
            {:noreply, put_flash(socket, :info, "Issue moved to backlog")}

          {:error, :invalid_transition} ->
            {:noreply, put_flash(socket, :error, "Cannot move to backlog from current state")}
        end
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

  @impl true
  def handle_event("new_issue", params, socket) do
    parent_id = params["parent_id"]
    path = new_issue_path(socket.assigns.current_project, parent_id)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply, push_patch(socket, to: dashboard_path(socket.assigns.current_project))}
  end

  @impl true
  def handle_event("validate_issue", %{"issue" => params}, socket) do
    changeset =
      %Issues.Issue{}
      |> Issues.change_issue(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("select_create_agent", %{"id" => agent_id}, socket) do
    {:noreply, assign(socket, :selected_agent_id, agent_id)}
  end

  @impl true
  def handle_event("save_issue", params, socket) do
    issue_params = params["issue"]
    project_id = issue_params["project_id"] || socket.assigns.form_project_id

    issue_params =
      issue_params
      |> Map.put("project_id", project_id)
      |> SynkadeWeb.IssueLiveHelpers.maybe_put_parent(socket.assigns[:form_parent_id])

    case Issues.create_issue(issue_params) do
      {:ok, issue} ->
        if params["dispatch"] == "true" do
          agent_id = params["agent_id"]
          agent_id = if agent_id == "", do: nil, else: agent_id

          case Issues.dispatch_issue(issue, issue.body, agent_id) do
            {:ok, _} ->
              send(self(), :load_board)

              socket =
                socket
                |> put_flash(:info, "Issue created and dispatched")

              {:noreply, push_patch(socket, to: dashboard_path(socket.assigns.current_project))}

            {:error, _} ->
              socket =
                socket
                |> put_flash(:error, "Issue created but dispatch failed")

              {:noreply, push_patch(socket, to: dashboard_path(socket.assigns.current_project, issue.id))}
          end
        else
          path = dashboard_path(socket.assigns.current_project, issue.id)

          socket =
            socket
            |> put_flash(:info, "Issue created")

          {:noreply, push_patch(socket, to: path)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # --- Modal events (new/edit only, view replaced by full-width) ---

  @impl true
  def handle_event("open_new_issue", _params, socket) do
    path = new_issue_path(socket.assigns.current_project)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("open_issue", %{"id" => issue_id}, socket) do
    project_name = socket.assigns.current_project
    path = dashboard_path(project_name, issue_id)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("edit_issue", _params, socket) do
    issue = socket.assigns.selected_issue.issue

    {:noreply,
     assign(socket, :modal, %{
       mode: :edit,
       issue: issue,
       body: issue.body || ""
     })}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :modal, nil)}
  end

  @impl true
  def handle_event("save_edit_issue", %{"body" => body}, socket) do
    issue = socket.assigns.modal.issue
    attrs = %{body: String.trim(body)}

    case Issues.update_issue(issue, attrs) do
      {:ok, updated} ->
        send(self(), :load_board)

        # Update selected_issue if in detail view
        socket =
          if socket.assigns.view_mode == :detail do
            ancestors = Issues.ancestor_chain(updated)

            socket
            |> assign(:selected_issue, %{issue: updated, ancestors: ancestors})
            |> assign(:modal, nil)
            |> put_flash(:info, "Issue updated")
          else
            socket
            |> assign(:modal, nil)
            |> put_flash(:info, "Issue updated")
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update issue")}
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

            socket =
              socket
              |> assign(:modal, nil)
              |> put_flash(:info, "Issue deleted")

            if socket.assigns.view_mode == :detail do
              {:noreply, push_patch(socket, to: dashboard_path(socket.assigns.current_project))}
            else
              {:noreply, socket}
            end

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete issue")}
        end
    end
  end

  # --- Private helpers ---

  defp dashboard_path(project_name, issue_id \\ nil) do
    params = %{}
    params = if project_name, do: Map.put(params, "project", project_name), else: params
    params = if issue_id, do: Map.put(params, "issue", issue_id), else: params

    if params == %{} do
      "/"
    else
      "/?" <> URI.encode_query(params)
    end
  end

  defp new_issue_path(project_name, parent_id \\ nil) do
    params = %{"new" => "true"}
    params = if project_name, do: Map.put(params, "project", project_name), else: params
    params = if parent_id, do: Map.put(params, "parent_id", parent_id), else: params
    "/?" <> URI.encode_query(params)
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

  defp resolve_db_id(nil, _scope), do: nil

  defp resolve_db_id(project, scope) do
    Map.get(project, :db_id) ||
      case Settings.get_project_by_name(scope, project.name) do
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
    alias Synkade.Issues.Issue

    %Synkade.Tracker.Issue{
      project_name: project_name,
      id: db_issue.id,
      identifier: "#{project_name}##{db_issue.id |> String.slice(0..7)}",
      title: Issue.title(db_issue),
      description: db_issue.body,
      state: db_issue.state,
      priority: nil,
      labels: [],
      blocked_by: [],
      created_at: db_issue.inserted_at,
      updated_at: db_issue.updated_at
    }
  end

  defp is_db_issue?(issue_id) do
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
      current_scope={@current_scope}
    >
      <div class="px-6 py-4">
        <%= cond do %>
          <% @view_mode == :detail && @selected_issue -> %>
            <.issue_full_view
              issue={@selected_issue.issue}
              ancestors={@selected_issue.ancestors}
              dispatch_form={@dispatch_form}
              agents={@agents}
              session_events={@session_events}
              session_id={@session_id}
              running_entry={find_running_entry(@running, @selected_issue.issue.id)}
              back_path={dashboard_path(@current_project)}
              back_label={@current_project || "Overview"}
            />

            <!-- Edit modal (overlaid on detail view) -->
            <.issue_modal :if={@modal && @modal.mode == :edit} modal={@modal} />

          <% @view_mode == :create -> %>
            <.issue_create_view
              form={@form}
              db_projects={[]}
              agents={@agents}
              selected_agent_id={@selected_agent_id}
              form_project_id={@form_project_id}
              form_parent_id={@form_parent_id}
              create_ancestors={@create_ancestors}
              back_path={dashboard_path(@current_project)}
            />

          <% true -> %>
          <div class="flex items-center justify-between mb-4">
            <h1 class="text-2xl font-bold">
              {if @current_project, do: @current_project, else: "Overview"}
            </h1>
            <div class="flex items-center gap-3">
              <button phx-click="refresh" class="btn btn-sm btn-primary">
                <span
                  :if={@current_project && @board_loading}
                  class="loading loading-spinner loading-xs"
                >
                </span>
                Refresh
              </button>
            </div>
          </div>

          <%= if @config_error do %>
            <div class="alert alert-error mb-4">
              <span>Config Error: {@config_error}</span>
            </div>
          <% end %>

          <%= if @current_project do %>
            <%!-- Project view: Kanban Board --%>
            <%= if @board_error do %>
              <div class="alert alert-warning mb-4">
                <span>{@board_error}</span>
              </div>
            <% end %>

            <div
              id="kanban-board"
              phx-hook="KanbanDrag"
              class="flex gap-4 overflow-x-auto pb-4"
              style="min-height: 60vh;"
            >
              <%= for col <- @board_columns do %>
                <div
                  class="kanban-column flex-shrink-0 w-72 bg-base-200 border border-base-300 p-3"
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
                          issue_status(
                            issue,
                            @filtered_running,
                            @filtered_retries,
                            @filtered_awaiting
                          )
                        }
                        clickable={is_db_issue?(issue.id)}
                        current_project={@current_project}
                      />
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>

          <% else %>
            <%!-- Overview: Status Cards + Token Usage Chart --%>
            <div class="grid grid-cols-3 gap-4 mb-4">
              <div class="card bg-base-200 border border-base-300 p-3">
                <div class="flex items-center gap-2">
                  <span class="loading loading-spinner loading-sm text-info"></span>
                  <span class="text-sm">{map_size(@filtered_running)} running</span>
                </div>
              </div>
              <div class="card bg-base-200 border border-base-300 p-3">
                <div class="flex items-center gap-2">
                  <span class="badge badge-error badge-xs">retry</span>
                  <span class="text-sm">{map_size(@filtered_retries)} retry</span>
                </div>
              </div>
              <div class="card bg-base-200 border border-base-300 p-3">
                <div class="flex items-center gap-2">
                  <span class="hero-arrow-uturn-down size-4 text-warning"></span>
                  <span class="text-sm">{map_size(@filtered_awaiting)} review</span>
                </div>
              </div>
            </div>

            <div class="card bg-base-200 border border-base-300 p-4">
              <h2 class="text-lg font-semibold mb-3">Token Usage — Last 30 Days</h2>
              <.token_chart
                days={@chart_days}
                models={@chart_models}
                y_max={@chart_y_max}
                dates={@chart_dates}
              />
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # --- Components ---

  attr :modal, :map, required: true

  defp issue_modal(assigns) do
    ~H"""
    <div class="modal modal-open" phx-window-keydown="close_modal" phx-key="Escape">
      <div class="modal-box max-w-lg">
        <%= case @modal.mode do %>
          <% :edit -> %>
            <h3 class="font-bold text-lg mb-4">Edit Issue</h3>
            <form phx-submit="save_edit_issue">
              <div class="form-control mb-4">
                <textarea
                  name="body"
                  class="textarea textarea-bordered w-full font-mono"
                  rows="6"
                  autofocus
                >{@modal.body}</textarea>
              </div>
              <div class="modal-action">
                <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
                <button type="submit" class="btn btn-primary">Save</button>
              </div>
            </form>
          <% _ -> %>
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
  attr :current_project, :string, default: nil

  defp issue_card(assigns) do
    ~H"""
    <div
      class={[
        "kanban-card card card-compact bg-base-100 border border-base-300",
        if(@draggable, do: "cursor-grab active:cursor-grabbing", else: "cursor-default"),
        @clickable && "hover:ring-1 hover:ring-primary/30"
      ]}
      draggable={to_string(@draggable)}
      data-issue-id={@issue.id}
      data-column={@column}
    >
      <div class="card-body p-3">
        <div class="flex items-start justify-between gap-2">
          <div class="flex-1 min-w-0">
            <p class="text-xs text-base-content/50 font-mono">{@issue.identifier}</p>
            <%= if @clickable do %>
              <.link
                patch={dashboard_path(@current_project, @issue.id)}
                class="text-sm font-medium leading-tight truncate block hover:underline"
                onclick="event.stopPropagation()"
              >
                {@issue.title}
              </.link>
            <% else %>
              <p class="text-sm font-medium leading-tight truncate">{@issue.title}</p>
            <% end %>
          </div>
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

end
