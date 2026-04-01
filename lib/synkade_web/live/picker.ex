defmodule SynkadeWeb.Picker do
  @moduledoc """
  Global command palette (cmd+k). Searches issues and navigates on select.
  Also supports an agent picker mode for choosing which agent to hand off to.

  Uses the generic `SearchPicker` component under the hood.

  Usage: add `on_mount: [{SynkadeWeb.Picker, :picker}]` to your live_session,
  then render `<SynkadeWeb.Picker.picker picker={@picker} />` in the layout.
  """
  import Phoenix.LiveView
  use Phoenix.Component

  import SynkadeWeb.Components.SearchPicker

  alias Synkade.Issues.Issue
  alias SynkadeWeb.Components.SearchPicker

  @default_state %{open: false, query: "", items: [], loading: false, mode: :issues, context: nil}

  def on_mount(:picker, _params, _session, socket) do
    socket =
      socket
      |> assign(:picker, SearchPicker.default())
      |> attach_hook(:picker_events, :handle_event, &handle_picker_event/3)
      |> attach_hook(:picker_info, :handle_info, &handle_picker_info/2)

    {:cont, socket}
  end

  # --- Event handlers ---

  defp handle_picker_event("open_picker", _params, socket) do
    send(self(), {:picker_search, ""})
    {:halt, assign(socket, :picker, %{SearchPicker.default() | open: true, loading: true})}
  end

  defp handle_picker_event("open_agent_picker", %{"project" => project_name}, socket) do
    agents = load_agents(socket)

    case agents do
      [single] ->
        # Only one agent — skip picker, go straight to chat
        {:halt,
         socket
         |> push_navigate(to: "/chat/#{project_name}?agent=#{single.id}")}

      _ ->
        picker = %{
          @default_state
          | open: true,
            loading: false,
            mode: :agents,
            items: agents,
            context: %{project: project_name}
        }
        picker = Map.put(picker, :all_items, agents)

        {:halt, assign(socket, :picker, picker)}
    end
  end

  defp handle_picker_event("picker_close", _params, socket) do
    {:halt, assign(socket, :picker, SearchPicker.default())}
  end

  defp handle_picker_event("picker_search", %{"query" => query}, socket) do
    picker = socket.assigns.picker

    case Map.get(picker, :mode, :issues) do
      :agents ->
        # Client-side filter for agents (small list, no async needed)
        all_items = Map.get(picker, :all_items, picker.items)
        filtered = SearchPicker.filter_items(all_items, query)
        {:halt, assign(socket, :picker, %{picker | query: query, items: filtered})}

      _ ->
        send(self(), {:picker_search, query})
        {:halt, assign(socket, :picker, %{picker | query: query, loading: true})}
    end
  end

  defp handle_picker_event("picker_submit", %{"query" => _query}, socket) do
    picker = socket.assigns.picker

    case picker.items do
      [first | _] ->
        {:halt, socket |> assign(:picker, SearchPicker.default()) |> navigate_picker(picker, first.id)}

      _ ->
        {:halt, assign(socket, :picker, SearchPicker.default())}
    end
  end

  defp handle_picker_event("picker_select", %{"id" => id}, socket) do
    picker = socket.assigns.picker
    {:halt, socket |> assign(:picker, SearchPicker.default()) |> navigate_picker(picker, id)}
  end

  defp handle_picker_event(_event, _params, socket), do: {:cont, socket}

  # --- Navigation ---

  defp navigate_picker(socket, picker, id) do
    case Map.get(picker, :mode, :issues) do
      :agents ->
        project = get_in(picker, [:context, :project])
        push_navigate(socket, to: "/chat/#{project}?agent=#{id}")

      _ ->
        push_navigate(socket, to: "/issues/#{id}")
    end
  end

  # --- Info handlers ---

  defp handle_picker_info({:picker_search, query}, socket) do
    items = search_issues(query)
    picker = %{socket.assigns.picker | items: items, loading: false}
    {:halt, assign(socket, :picker, picker)}
  end

  defp handle_picker_info(_msg, socket), do: {:cont, socket}

  # --- Search ---

  defp search_issues(query) do
    issues =
      Issue
      |> Synkade.Repo.all()
      |> Enum.reject(&(&1.state == "done"))
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    issues =
      if query == "" do
        Enum.take(issues, 20)
      else
        q = String.downcase(query)

        issues
        |> Enum.filter(fn issue ->
          title = String.downcase(Issue.title(issue))
          body = String.downcase(issue.body || "")
          String.contains?(title, q) || String.contains?(body, q)
        end)
        |> Enum.take(20)
      end

    Enum.map(issues, fn issue ->
      %{
        id: issue.id,
        label: Issue.title(issue),
        dot_color: state_color(issue.state)
      }
    end)
  end

  defp load_agents(socket) do
    scope = socket.assigns[:current_scope]

    agents =
      if scope do
        Synkade.Settings.list_agents(scope)
      else
        []
      end

    Enum.map(agents, fn agent ->
      %{
        id: agent.id,
        label: agent.name,
        description: agent.kind
      }
    end)
  end

  # --- Component ---

  attr :picker, :map, required: true

  def picker(assigns) do
    mode = Map.get(assigns.picker, :mode, :issues)

    {placeholder, empty_message} =
      case mode do
        :agents -> {"Which agent?", "No agents configured"}
        _ -> {"Search issues...", "No issues found"}
      end

    assigns =
      assigns
      |> assign(:placeholder, placeholder)
      |> assign(:empty_message, empty_message)

    ~H"""
    <.search_picker
      name="picker"
      state={@picker}
      placeholder={@placeholder}
      empty_message={@empty_message}
    />
    """
  end

  defp state_color("worked_on"), do: "bg-info"
  defp state_color(_), do: "bg-base-content/20"
end
