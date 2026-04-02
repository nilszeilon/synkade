defmodule SynkadeWeb.DashboardLive.BoardHelpers do
  @moduledoc "Pure data functions for dashboard board categorization and navigation."

  import Phoenix.Component, only: [assign: 3]

  alias Synkade.Settings

  # --- Path helpers ---

  def dashboard_path(project_name, issue_id \\ nil) do
    cond do
      project_name && issue_id ->
        "/projects/#{project_name}?" <> URI.encode_query(%{"issue" => issue_id})

      project_name ->
        "/projects/#{project_name}"

      true ->
        "/"
    end
  end

  def new_issue_path(project_name, opts \\ []) do
    base = if project_name, do: "/projects/#{project_name}", else: "/"
    params = %{"new" => "true"}
    params = if opts[:body], do: Map.put(params, "body", opts[:body]), else: params
    base <> "?" <> URI.encode_query(params)
  end

  # --- Resolve helpers ---

  def resolve_project(socket) do
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

  def resolve_db_id(nil, _scope), do: nil

  def resolve_db_id(project, scope) do
    Map.get(project, :db_id) ||
      case Settings.get_project_by_name(scope, project.name) do
        %{id: id} -> id
        _ -> nil
      end
  end

  # --- Project filtering ---

  def filter_by_project(map, nil), do: map

  def filter_by_project(map, project_name) do
    Map.filter(map, fn {_k, e} -> e.project_name == project_name end)
  end

  # --- Board categorization ---

  def categorize_by_state(issues, project_name, dispatch_labels, running, retry_attempts, awaiting_review) do
    base = %{"backlog" => [], "worked_on" => []}

    Enum.reduce(issues, base, fn issue, acc ->
      key = "#{project_name}:#{issue.id}"

      column =
        cond do
          Map.has_key?(running, key) or Map.has_key?(retry_attempts, key) ->
            "worked_on"

          Map.has_key?(awaiting_review, key) ->
            "worked_on"

          issue.state == "worked_on" ->
            "worked_on"

          dispatch_labels != [] and Enum.any?(dispatch_labels, &(&1 in issue.labels)) ->
            "worked_on"

          true ->
            "backlog"
        end

      Map.update!(acc, column, fn existing -> existing ++ [issue] end)
    end)
  end

  def recategorize_from_assigns(socket, project_name, dispatch_labels) do
    all_issues =
      (Map.get(socket.assigns.board_issues, "backlog", []) ++
         Map.get(socket.assigns.board_issues, "worked_on", []))

    categorize_by_state(
      all_issues,
      project_name,
      dispatch_labels,
      socket.assigns.running,
      socket.assigns.retry_attempts,
      socket.assigns.awaiting_review
    )
  end

  def move_card_in_assigns(socket, issue_id, from_col, to_col, _dispatch_labels) do
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
end
