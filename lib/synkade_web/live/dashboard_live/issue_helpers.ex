defmodule SynkadeWeb.DashboardLive.IssueHelpers do
  @moduledoc "Issue CRUD event handling for DashboardLive."

  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [put_flash: 3, push_patch: 2]
  import SynkadeWeb.DashboardLive.BoardHelpers,
    only: [dashboard_path: 1, dashboard_path: 2, new_issue_path: 1]

  alias Synkade.Issues

  @doc "Handle issue CRUD events. Returns `{:halt, socket}` or `:cont`."
  def handle_issue_event("cancel_form", _params, socket) do
    {:halt, push_patch(socket, to: dashboard_path(socket.assigns.current_project))}
  end

  def handle_issue_event("validate_issue", %{"issue" => params}, socket) do
    changeset =
      %Issues.Issue{}
      |> Issues.change_issue(params)
      |> Map.put(:action, :validate)

    {:halt, assign(socket, :form, to_form(changeset))}
  end

  def handle_issue_event("select_create_agent", %{"id" => agent_id}, socket) do
    {:halt, assign(socket, :selected_agent_id, agent_id)}
  end

  def handle_issue_event("save_issue", params, socket) do
    issue_params = params["issue"]
    project_id = issue_params["project_id"] || socket.assigns.form_project_id

    issue_params =
      issue_params
      |> Map.put("project_id", project_id)

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

              {:halt, push_patch(socket, to: dashboard_path(socket.assigns.current_project))}

            {:error, _} ->
              socket =
                socket
                |> put_flash(:error, "Issue created but dispatch failed")

              {:halt, push_patch(socket, to: dashboard_path(socket.assigns.current_project, issue.id))}
          end
        else
          path = dashboard_path(socket.assigns.current_project, issue.id)

          socket =
            socket
            |> put_flash(:info, "Issue created")

          {:halt, push_patch(socket, to: path)}
        end

      {:error, changeset} ->
        {:halt, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_issue_event("open_new_issue", _params, socket) do
    path = new_issue_path(socket.assigns.current_project)
    {:halt, push_patch(socket, to: path)}
  end

  def handle_issue_event("open_issue", %{"id" => issue_id}, socket) do
    project_name = socket.assigns.current_project
    path = dashboard_path(project_name, issue_id)
    {:halt, push_patch(socket, to: path)}
  end

  def handle_issue_event("edit_issue", _params, socket) do
    issue = socket.assigns.selected_issue.issue

    {:halt,
     assign(socket, :modal, %{
       mode: :edit,
       issue: issue,
       body: issue.body || ""
     })}
  end

  def handle_issue_event("close_modal", _params, socket) do
    {:halt, assign(socket, :modal, nil)}
  end

  def handle_issue_event("save_edit_issue", %{"body" => body}, socket) do
    issue = socket.assigns.modal.issue
    attrs = %{body: String.trim(body)}

    case Issues.update_issue(issue, attrs) do
      {:ok, updated} ->
        send(self(), :load_board)

        socket =
          if socket.assigns.view_mode == :detail do
            socket
            |> assign(:selected_issue, %{issue: updated})
            |> assign(:modal, nil)
            |> put_flash(:info, "Issue updated")
          else
            socket
            |> assign(:modal, nil)
            |> put_flash(:info, "Issue updated")
          end

        {:halt, socket}

      {:error, _} ->
        {:halt, put_flash(socket, :error, "Failed to update issue")}
    end
  end

  def handle_issue_event("delete_issue", %{"id" => issue_id}, socket) do
    case Issues.get_issue(issue_id) do
      nil ->
        {:halt, put_flash(socket, :error, "Issue not found")}

      issue ->
        case Issues.delete_issue(issue) do
          {:ok, _} ->
            send(self(), :load_board)

            socket =
              socket
              |> assign(:modal, nil)
              |> put_flash(:info, "Issue deleted")

            if socket.assigns.view_mode == :detail do
              {:halt, push_patch(socket, to: dashboard_path(socket.assigns.current_project))}
            else
              {:halt, socket}
            end

          {:error, _} ->
            {:halt, put_flash(socket, :error, "Failed to delete issue")}
        end
    end
  end

  def handle_issue_event(_event, _params, _socket), do: :cont
end
