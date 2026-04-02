defmodule SynkadeWeb.IdeDispatchHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3, push_event: 3, consume_uploaded_entries: 3]
  import SynkadeWeb.IssueLiveHelpers, only: [resolved_agent_kind: 4]

  alias Synkade.{Issues, Settings}

  def handle_draft_dispatch(socket, full_message) do
    project = socket.assigns.project

    # Derive title: first line or first 60 chars
    title =
      full_message
      |> String.split("\n", parts: 2)
      |> hd()
      |> String.slice(0..59)

    body = "# #{title}"

    case Issues.create_issue(%{project_id: project.id, body: body}) do
      {:ok, issue} ->
        {agent_name, instruction, agent_id} =
          resolve_dispatch_with_picker(socket, full_message)

        case Issues.dispatch_issue(issue, instruction, agent_id, model: socket.assigns.selected_model) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Created and dispatched" <> if(agent_name, do: " to #{agent_name}", else: ""))
             |> push_navigate(to: "/issues/#{issue.id}")}

          {:error, _} ->
            # Issue created but dispatch failed — still navigate to it
            {:noreply,
             socket
             |> put_flash(:info, "Issue created")
             |> push_navigate(to: "/issues/#{issue.id}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create issue")}
    end
  end

  def handle_existing_dispatch(socket, full_message) do
    issue = socket.assigns.issue

    # Reactivate archived issues: done → backlog so dispatch can transition to worked_on
    issue =
      if issue.state == "done" do
        case Issues.transition_state(issue, "backlog") do
          {:ok, reactivated} -> reactivated
          _ -> issue
        end
      else
        issue
      end

    {agent_name, instruction, agent_id} =
      resolve_dispatch_with_picker(socket, full_message)

    case Issues.dispatch_issue(issue, instruction, agent_id, model: socket.assigns.selected_model) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:dispatch_form, to_form(%{"message" => ""}, as: :dispatch))
          |> assign(:attachments, [])
          |> push_event("clear_input", %{})
          |> put_flash(
            :info,
            "Dispatched" <> if(agent_name, do: " to #{agent_name}", else: "")
          )

        {:noreply, socket}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot dispatch from current state")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to dispatch")}
    end
  end

  def consume_uploaded_images(socket) do
    consume_uploaded_entries(socket, :images, fn %{path: path}, entry ->
      # Copy uploaded file to workspace so the agent can access it
      workspace_path = socket.assigns.workspace_path
      filename = Path.basename(entry.client_name)

      if workspace_path && File.dir?(workspace_path) do
        dest_dir = Path.join(workspace_path, ".synkade/uploads")
        File.mkdir_p!(dest_dir)
        dest = Path.join(dest_dir, filename)
        File.cp!(path, dest)
        {:ok, %{filename: filename, path: ".synkade/uploads/#{filename}"}}
      else
        {:ok, %{filename: filename, path: nil}}
      end
    end)
  end

  def build_dispatch_message(message, attachments, uploads) do
    parts = []

    # Add code comment attachments
    comment_parts =
      attachments
      |> Enum.filter(&(&1.type == :comment))
      |> Enum.map(fn att -> "[#{att.file}:#{att.line}] #{att.text}" end)

    # Add image references
    image_parts =
      uploads
      |> Enum.filter(& &1.path)
      |> Enum.map(fn upload -> "[image: #{upload.path}]" end)

    all_parts = parts ++ comment_parts ++ image_parts
    context = Enum.join(all_parts, "\n")

    case {String.trim(context), String.trim(message)} do
      {"", msg} -> msg
      {ctx, ""} -> ctx
      {ctx, msg} -> ctx <> "\n\n" <> msg
    end
  end

  # Resolve dispatch agent: @agent syntax wins, then picker, then nil
  def resolve_dispatch_with_picker(socket, message) do
    {agent_name, instruction, agent_id} =
      SynkadeWeb.IssueLiveHelpers.resolve_dispatch(socket.assigns.current_scope, message)

    if agent_id do
      {agent_name, instruction, agent_id}
    else
      picker_id = socket.assigns.selected_dispatch_agent_id

      case picker_id do
        nil -> {nil, instruction, nil}
        id ->
          agent = Enum.find(socket.assigns.agents, &(&1.id == id))
          {agent && agent.name, instruction, id}
      end
    end
  end

  def ide_resolved_agent_kind(assigns) do
    # If user explicitly picked an agent in the dispatch form, use that
    if assigns.selected_dispatch_agent_id do
      agent = Enum.find(assigns.agents, &(&1.id == assigns.selected_dispatch_agent_id))
      agent && agent.kind
    else
      cond do
        assigns.running_entry && assigns.running_entry[:agent_kind] ->
          assigns.running_entry[:agent_kind]

        assigns.issue ->
          setting = Settings.get_settings_for_user(assigns.current_scope.user.id)
          resolved_agent_kind(assigns.issue, assigns.agents, setting, [assigns.project])

        true ->
          # New chat — resolve from project/user defaults
          setting = Settings.get_settings_for_user(assigns.current_scope.user.id)
          agent = Settings.resolve_agent(assigns.agents,
            project_agent_id: assigns.project && assigns.project.default_agent_id,
            user_default_id: setting && setting.default_agent_id
          )
          agent && agent.kind
      end
    end
  end
end
