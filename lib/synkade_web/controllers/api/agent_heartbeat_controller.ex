defmodule SynkadeWeb.Api.AgentHeartbeatController do
  use SynkadeWeb, :controller

  alias Synkade.Issues

  import SynkadeWeb.Api.AgentAccess, only: [has_project_access?: 2]

  @valid_statuses ~w(working error blocked)

  def create(conn, %{"issue_id" => issue_id, "status" => status} = params)
      when status in @valid_statuses do
    agent = conn.assigns.current_agent

    case Issues.get_issue(issue_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      issue ->
        if has_project_access?(agent, issue.project_id) do
          Issues.update_issue_heartbeat(issue_id, "[#{status}] #{params["message"] || ""}")
          json(conn, %{ok: true})
        else
          conn |> put_status(403) |> json(%{error: "forbidden"})
        end
    end
  end

  def create(conn, %{"issue_id" => _issue_id, "status" => _status}) do
    conn
    |> put_status(400)
    |> json(%{error: "status must be one of: #{Enum.join(@valid_statuses, ", ")}"})
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "issue_id and status are required"})
  end

end
