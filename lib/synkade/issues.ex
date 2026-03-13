defmodule Synkade.Issues do
  @moduledoc false

  import Ecto.Query
  alias Synkade.Repo
  alias Synkade.Issues.Issue

  @pubsub_topic "issues:updates"

  def pubsub_topic, do: @pubsub_topic

  # --- Valid transitions ---

  @transitions %{
    "backlog" => ~w(queued cancelled),
    "queued" => ~w(in_progress backlog cancelled),
    "in_progress" => ~w(awaiting_review done cancelled),
    "awaiting_review" => ~w(queued done cancelled),
    "done" => ~w(cancelled),
    "cancelled" => []
  }

  # --- CRUD ---

  def list_issues(project_id, opts \\ []) do
    query =
      from(i in Issue,
        where: i.project_id == ^project_id,
        order_by: [asc: i.position, asc: i.inserted_at]
      )

    query =
      Enum.reduce(opts, query, fn
        {:state, state}, q -> where(q, [i], i.state == ^state)
        {:parent_id, nil}, q -> where(q, [i], is_nil(i.parent_id))
        {:parent_id, pid}, q -> where(q, [i], i.parent_id == ^pid)
        _, q -> q
      end)

    Repo.all(query)
  end

  def list_root_issues(project_id) do
    from(i in Issue,
      where: i.project_id == ^project_id and is_nil(i.parent_id),
      order_by: [asc: i.position, asc: i.inserted_at],
      preload: [children: ^children_preload_query()]
    )
    |> Repo.all()
  end

  def list_issues_filtered(project_id, states) when is_list(states) do
    from(i in Issue,
      where: i.project_id == ^project_id and i.state in ^states,
      order_by: [asc: i.position, asc: i.inserted_at]
    )
    |> Repo.all()
  end

  def list_children(issue_id) do
    from(i in Issue,
      where: i.parent_id == ^issue_id,
      order_by: [asc: i.position, asc: i.inserted_at]
    )
    |> Repo.all()
  end

  def get_issue!(id) do
    Issue
    |> Repo.get!(id)
    |> Repo.preload(children: children_preload_query())
  end

  def get_issue(id) do
    Repo.get(Issue, id)
  end

  def create_issue(attrs) do
    attrs = compute_depth(attrs)

    result =
      %Issue{}
      |> Issue.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, issue} ->
        broadcast_update()
        {:ok, issue}

      error ->
        error
    end
  end

  def update_issue(%Issue{} = issue, attrs) do
    result =
      issue
      |> Issue.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, issue} ->
        broadcast_update()
        {:ok, issue}

      error ->
        error
    end
  end

  def delete_issue(%Issue{} = issue) do
    result = Repo.delete(issue)

    case result do
      {:ok, issue} ->
        broadcast_update()
        {:ok, issue}

      error ->
        error
    end
  end

  def change_issue(%Issue{} = issue, attrs \\ %{}) do
    Issue.changeset(issue, attrs)
  end

  # --- State Machine ---

  def transition_state(%Issue{} = issue, new_state) do
    allowed = Map.get(@transitions, issue.state, [])

    if new_state in allowed do
      update_issue(issue, %{state: new_state})
    else
      {:error, :invalid_transition}
    end
  end

  def queue_issue(%Issue{} = issue), do: transition_state(issue, "queued")
  def complete_issue(%Issue{} = issue), do: transition_state(issue, "done")
  def cancel_issue(%Issue{} = issue), do: transition_state(issue, "cancelled")

  def dispatch_issue(%Issue{} = issue, dispatch_message, assigned_agent_id \\ nil) do
    with {:ok, updated} <-
           update_issue(issue, %{
             dispatch_message: dispatch_message,
             assigned_agent_id: assigned_agent_id
           }),
         {:ok, queued} <- transition_state(updated, "queued") do
      {:ok, queued}
    end
  end

  # --- Tree Operations ---

  def ancestor_chain(%Issue{parent_id: nil}), do: []

  def ancestor_chain(%Issue{parent_id: parent_id}) do
    parent = get_issue!(parent_id)
    ancestor_chain(parent) ++ [parent]
  end

  def issue_tree(issue_id) do
    get_issue!(issue_id)
  end

  def list_queued_issues(project_id) do
    from(i in Issue,
      where: i.project_id == ^project_id and i.state == "queued",
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  # --- Agent Child Creation ---

  def create_children_from_agent(%Issue{} = parent, children_attrs_list)
      when is_list(children_attrs_list) do
    children_attrs_list
    |> Enum.with_index()
    |> Enum.map(fn {attrs, index} ->
      attrs =
        attrs
        |> Map.put(:project_id, parent.project_id)
        |> Map.put(:parent_id, parent.id)
        |> Map.put(:depth, parent.depth + 1)
        |> Map.put(:state, "backlog")
        |> Map.put_new(:position, index)

      create_issue(attrs)
    end)
  end

  # --- Private ---

  defp compute_depth(attrs) do
    parent_id = attrs[:parent_id] || attrs["parent_id"]

    if parent_id do
      case Repo.get(Issue, parent_id) do
        %Issue{depth: parent_depth} ->
          Map.put(attrs, :depth, parent_depth + 1)

        nil ->
          attrs
      end
    else
      Map.put_new(attrs, :depth, 0)
    end
  end

  defp children_preload_query do
    from(i in Issue, order_by: [asc: i.position, asc: i.inserted_at])
  end

  defp broadcast_update do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      @pubsub_topic,
      {:issues_updated}
    )
  end
end
