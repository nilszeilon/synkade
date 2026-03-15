defmodule SynkadeWeb.Api.AgentIssuesController do
  use SynkadeWeb, :controller

  alias Synkade.Issues
  alias Synkade.Settings

  def index(conn, %{"project_id" => project_id} = params) do
    agent = conn.assigns.current_agent

    if has_project_access?(agent, project_id) do
      issues = Issues.list_issues(project_id)

      # Filter by state if requested
      issues =
        case params["state"] do
          nil -> issues
          state -> Enum.filter(issues, fn i -> i.state == state end)
        end

      # Filter to issues assigned to the calling agent
      issues =
        case params["assigned_to"] do
          "me" -> Enum.filter(issues, fn i -> i.assigned_agent_id == agent.id end)
          _ -> issues
        end

      json(conn, SynkadeWeb.Api.AgentIssuesJSON.issues(issues))
    else
      conn |> put_status(403) |> json(%{error: "forbidden"})
    end
  end

  def index(conn, params) do
    agent = conn.assigns.current_agent

    opts =
      []
      |> then(fn opts ->
        case params["state"] do
          nil -> opts
          state -> [{:state, state} | opts]
        end
      end)
      |> then(fn opts ->
        case params["assigned_to"] do
          "me" -> [{:assigned_to, agent.id} | opts]
          _ -> opts
        end
      end)

    issues = Issues.list_agent_inbox(agent.id, opts)
    json(conn, SynkadeWeb.Api.AgentIssuesJSON.issues(issues))
  end

  def create(conn, %{"project_id" => project_id} = params) do
    agent = conn.assigns.current_agent

    if has_project_access?(agent, project_id) do
      body = params["body"] || assemble_body(params["title"], params["description"])

      attrs = %{
        project_id: project_id,
        body: body,
        parent_id: params["parent_id"],
        state: params["state"] || "backlog"
      }

      case Issues.create_issue(attrs) do
        {:ok, issue} ->
          issue = Issues.get_issue!(issue.id)
          conn |> put_status(201) |> json(SynkadeWeb.Api.AgentIssuesJSON.issue(issue))

        {:error, changeset} ->
          conn |> put_status(422) |> json(%{error: format_errors(changeset)})
      end
    else
      conn |> put_status(403) |> json(%{error: "forbidden"})
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "project_id is required"})
  end

  def show(conn, %{"id" => id}) do
    agent = conn.assigns.current_agent

    case Issues.get_issue(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      issue ->
        if has_project_access?(agent, issue.project_id) do
          issue = Issues.get_issue!(id)
          json(conn, SynkadeWeb.Api.AgentIssuesJSON.issue(issue))
        else
          conn |> put_status(403) |> json(%{error: "forbidden"})
        end
    end
  end

  def update(conn, %{"id" => id} = params) do
    agent = conn.assigns.current_agent

    case Issues.get_issue(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      issue ->
        if has_project_access?(agent, issue.project_id) do
          # Support body directly, or assemble from title+description for backwards compat
          body =
            cond do
              params["body"] -> params["body"]
              params["title"] || params["description"] -> assemble_body(params["title"], params["description"])
              true -> nil
            end

          update_attrs =
            %{}
            |> maybe_put(:body, body)
            |> maybe_put(:agent_output, params["agent_output"])

          # Handle state transition separately
          result =
            case params["state"] do
              nil ->
                Issues.update_issue(issue, update_attrs)

              new_state when new_state in ~w(queued cancelled) ->
                {:error, :forbidden_transition}

              new_state ->
                with {:ok, updated} <- Issues.update_issue(issue, update_attrs) do
                  Issues.transition_state(updated, new_state)
                end
            end

          case result do
            {:ok, updated} ->
              updated = Issues.get_issue!(updated.id)
              json(conn, SynkadeWeb.Api.AgentIssuesJSON.issue(updated))

            {:error, :forbidden_transition} ->
              conn
              |> put_status(403)
              |> json(%{error: "agents cannot transition to this state"})

            {:error, :invalid_transition} ->
              conn |> put_status(422) |> json(%{error: "invalid state transition"})

            {:error, changeset} ->
              conn |> put_status(422) |> json(%{error: format_errors(changeset)})
          end
        else
          conn |> put_status(403) |> json(%{error: "forbidden"})
        end
    end
  end

  def checkout(conn, %{"id" => id}) do
    agent = conn.assigns.current_agent

    case Issues.get_issue(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      issue ->
        if has_project_access?(agent, issue.project_id) do
          case Issues.checkout_issue(issue, agent.id) do
            {:ok, updated} ->
              updated = Issues.get_issue!(updated.id)
              json(conn, SynkadeWeb.Api.AgentIssuesJSON.issue(updated))

            {:error, :already_claimed} ->
              conn |> put_status(409) |> json(%{error: "issue is not in queued state"})
          end
        else
          conn |> put_status(403) |> json(%{error: "forbidden"})
        end
    end
  end

  def create_children(conn, %{"id" => id} = params) do
    agent = conn.assigns.current_agent
    children_attrs = params["children"] || []

    case Issues.get_issue(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      parent ->
        if has_project_access?(agent, parent.project_id) do
          children_maps =
            Enum.map(children_attrs, fn child ->
              body = child["body"] || assemble_body(child["title"], child["description"])
              %{body: body}
            end)

          results = Issues.create_children_from_agent(parent, children_maps)

          created =
            results
            |> Enum.filter(&match?({:ok, _}, &1))
            |> Enum.map(fn {:ok, issue} -> issue end)

          conn |> put_status(201) |> json(SynkadeWeb.Api.AgentIssuesJSON.issues(created))
        else
          conn |> put_status(403) |> json(%{error: "forbidden"})
        end
    end
  end

  # --- Private ---

  defp assemble_body(nil, nil), do: nil
  defp assemble_body(title, nil), do: "# #{title}"
  defp assemble_body(nil, desc), do: desc
  defp assemble_body(title, desc), do: "# #{title}\n\n#{desc}"

  defp has_project_access?(agent, project_id) do
    case Settings.get_project!(project_id) do
      %{default_agent_id: agent_id} when agent_id == agent.id -> true
      _ -> project_has_agent_issues?(agent, project_id)
    end
  rescue
    Ecto.NoResultsError -> false
  end

  defp project_has_agent_issues?(agent, project_id) do
    import Ecto.Query

    Synkade.Repo.exists?(
      from(i in Synkade.Issues.Issue,
        where: i.project_id == ^project_id and i.assigned_agent_id == ^agent.id
      )
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
