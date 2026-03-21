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
    "awaiting_review" => ~w(queued backlog done cancelled),
    "done" => ~w(backlog cancelled),
    "cancelled" => ~w(backlog)
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

  @doc "Lists issues across all projects accessible to the given agent."
  def list_agent_inbox(agent_id, opts \\ []) do
    # Find project IDs where agent is default
    default_project_ids =
      from(p in Synkade.Settings.Project,
        where: p.default_agent_id == ^agent_id,
        select: p.id
      )
      |> Repo.all()

    # Find project IDs where agent has assigned issues
    assigned_project_ids =
      from(i in Issue,
        where: i.assigned_agent_id == ^agent_id,
        distinct: true,
        select: i.project_id
      )
      |> Repo.all()

    accessible_project_ids = Enum.uniq(default_project_ids ++ assigned_project_ids)

    query =
      from(i in Issue,
        where: i.project_id in ^accessible_project_ids,
        order_by: [asc: i.inserted_at]
      )

    query =
      Enum.reduce(opts, query, fn
        {:state, state}, q -> where(q, [i], i.state == ^state)
        {:assigned_to, agent_id}, q -> where(q, [i], i.assigned_agent_id == ^agent_id)
        _, q -> q
      end)

    Repo.all(query)
  end

  def list_issues_filtered(project_id, states) when is_list(states) do
    from(i in Issue,
      where: i.project_id == ^project_id and i.state in ^states,
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

  @doc """
  Atomically checks out a queued issue for the given agent.
  Returns {:ok, issue} on success, {:error, :already_claimed} if not in queued state.
  """
  def checkout_issue(%Issue{} = issue, agent_id) do
    import Ecto.Query

    {count, _} =
      from(i in Issue,
        where: i.id == ^issue.id and i.state == "queued"
      )
      |> Repo.update_all(
        set: [state: "in_progress", assigned_agent_id: agent_id, updated_at: DateTime.utc_now()]
      )

    if count == 1 do
      updated = get_issue!(issue.id)
      broadcast_update()
      {:ok, updated}
    else
      {:error, :already_claimed}
    end
  end

  def queue_issue(%Issue{} = issue), do: transition_state(issue, "queued")
  def complete_issue(%Issue{} = issue), do: transition_state(issue, "done")
  def cancel_issue(%Issue{} = issue), do: transition_state(issue, "cancelled")

  @doc "Update heartbeat timestamp and message for an in-progress issue."
  def update_issue_heartbeat(issue_id, message \\ nil) do
    from(i in Issue,
      where: i.id == ^issue_id
    )
    |> Repo.update_all(
      set: [
        last_heartbeat_at: DateTime.utc_now(),
        last_heartbeat_message: message
      ]
    )
  end

  @doc "List all issues in awaiting_review state."
  def list_awaiting_review_issues do
    from(i in Issue,
      where: i.state == "awaiting_review",
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  def dispatch_issue(%Issue{} = issue, dispatch_message, assigned_agent_id \\ nil) do
    {agent_name, agent_kind} =
      case assigned_agent_id do
        nil -> {nil, nil}
        id ->
          try do
            agent = Synkade.Settings.get_agent!(id)
            {agent.name, agent.kind}
          rescue
            _ -> {nil, nil}
          end
      end

    messages = (issue.metadata["messages"] || [])
    new_entry = %{
      "type" => "dispatch",
      "agent_name" => agent_name,
      "agent_kind" => agent_kind,
      "text" => dispatch_message,
      "at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    with {:ok, updated} <-
           update_issue(issue, %{
             dispatch_message: dispatch_message,
             assigned_agent_id: assigned_agent_id,
             metadata: Map.put(issue.metadata || %{}, "messages", messages ++ [new_entry])
           }),
         {:ok, ready} <- ensure_backlog(updated),
         {:ok, queued} <- transition_state(ready, "queued") do
      # Enqueue Oban job for non-pull-based agents
      unless pull_based_agent?(assigned_agent_id) do
        %{issue_id: queued.id, project_id: queued.project_id}
        |> Synkade.Workers.AgentWorker.new()
        |> Oban.insert()
      end

      {:ok, queued}
    end
  end

  defp ensure_backlog(%Issue{state: "backlog"} = issue), do: {:ok, issue}
  defp ensure_backlog(%Issue{} = issue), do: transition_state(issue, "backlog")

  defp pull_based_agent?(nil), do: false

  defp pull_based_agent?(agent_id) do
    case Synkade.Settings.get_agent!(agent_id) do
      %{kind: kind} -> Synkade.Settings.Agent.pull_kind?(kind)
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc "Appends an agent output entry to the issue message history."
  def append_agent_output(%Issue{} = issue, agent_output, agent_name \\ nil, agent_kind \\ nil) do
    messages = (issue.metadata["messages"] || [])
    new_entry = %{
      "type" => "agent",
      "agent_name" => agent_name,
      "agent_kind" => agent_kind,
      "text" => agent_output,
      "at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    update_issue(issue, %{
      agent_output: agent_output,
      metadata: Map.put(issue.metadata || %{}, "messages", messages ++ [new_entry])
    })
  end

  # --- Tree Operations ---

  def ancestor_chain(%Issue{parent_id: nil}), do: []

  def ancestor_chain(%Issue{parent_id: parent_id}) do
    parent = get_issue!(parent_id)
    ancestor_chain(parent) ++ [parent]
  end

  def list_queued_issues(project_id) do
    from(i in Issue,
      where: i.project_id == ^project_id and i.state == "queued",
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  # --- Recurring Issues ---

  @doc "Returns recurring issues in `done` state whose interval has elapsed."
  def list_due_recurring_issues do
    now = DateTime.utc_now()

    from(i in Issue,
      where: i.recurring == true and i.state == "done"
    )
    |> Repo.all()
    |> Enum.filter(fn issue ->
      seconds = interval_to_seconds(issue.recurrence_interval, issue.recurrence_unit)
      deadline = DateTime.add(issue.updated_at, seconds, :second)
      DateTime.compare(deadline, now) != :gt
    end)
  end

  @doc "Cycles a recurring issue from done back to queued, appending a system message."
  def cycle_recurring_issue(%Issue{state: "done", recurring: true} = issue) do
    messages = (issue.metadata["messages"] || [])

    new_entry = %{
      "type" => "system",
      "text" => "Recurring issue cycled automatically",
      "at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    metadata = Map.put(issue.metadata || %{}, "messages", messages ++ [new_entry])

    with {:ok, backlog} <- update_issue(issue, %{state: "backlog", metadata: metadata}),
         {:ok, queued} <- transition_state(backlog, "queued") do
      {:ok, queued}
    end
  end

  # --- Agent Child Creation ---

  def create_children_from_agent(%Issue{} = parent, children_attrs_list)
      when is_list(children_attrs_list) do
    children_attrs_list
    |> Enum.with_index()
    |> Enum.map(fn {attrs, index} ->
      attrs = stringify_keys(attrs)

      attrs =
        attrs
        |> Map.put("project_id", parent.project_id)
        |> Map.put("parent_id", parent.id)
        |> Map.put("depth", parent.depth + 1)
        |> Map.put("state", "backlog")
        |> Map.put_new("position", index)

      create_issue(attrs)
    end)
  end

  # --- Private ---

  defp compute_depth(attrs) do
    attrs = stringify_keys(attrs)
    parent_id = attrs["parent_id"]

    if parent_id do
      case Repo.get(Issue, parent_id) do
        %Issue{depth: parent_depth} ->
          Map.put(attrs, "depth", parent_depth + 1)

        nil ->
          attrs
      end
    else
      Map.put_new(attrs, "depth", 0)
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp interval_to_seconds(amount, "hours"), do: amount * 3600
  defp interval_to_seconds(amount, "days"), do: amount * 86400
  defp interval_to_seconds(amount, "weeks"), do: amount * 604_800
  defp interval_to_seconds(amount, _), do: amount * 3600

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
