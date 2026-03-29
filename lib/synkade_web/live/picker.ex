defmodule SynkadeWeb.Picker do
  @moduledoc """
  Global command palette (cmd+k). Searches issues and navigates on select.

  Uses the generic `SearchPicker` component under the hood.

  Usage: add `on_mount: [{SynkadeWeb.Picker, :picker}]` to your live_session,
  then render `<SynkadeWeb.Picker.picker picker={@picker} />` in the layout.
  """
  import Phoenix.LiveView
  use Phoenix.Component

  import SynkadeWeb.Components.SearchPicker

  alias Synkade.Issues.Issue
  alias SynkadeWeb.Components.SearchPicker

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

  defp handle_picker_event("picker_close", _params, socket) do
    {:halt, assign(socket, :picker, SearchPicker.default())}
  end

  defp handle_picker_event("picker_search", %{"query" => query}, socket) do
    send(self(), {:picker_search, query})
    picker = %{socket.assigns.picker | query: query, loading: true}
    {:halt, assign(socket, :picker, picker)}
  end

  defp handle_picker_event("picker_submit", %{"query" => query}, socket) do
    picker = socket.assigns.picker

    case picker.items do
      [first | _] ->
        {:halt,
         socket
         |> assign(:picker, SearchPicker.default())
         |> push_navigate(to: "/issues/#{first.id}")}

      [] when query != "" ->
        {:halt, assign(socket, :picker, SearchPicker.default())}

      _ ->
        {:halt, socket}
    end
  end

  defp handle_picker_event("picker_select", %{"id" => id}, socket) do
    {:halt,
     socket
     |> assign(:picker, SearchPicker.default())
     |> push_navigate(to: "/issues/#{id}")}
  end

  defp handle_picker_event(_event, _params, socket), do: {:cont, socket}

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

  # --- Component ---

  attr :picker, :map, required: true

  def picker(assigns) do
    ~H"""
    <.search_picker
      name="picker"
      state={@picker}
      placeholder="Search issues..."
      empty_message="No issues found"
    />
    """
  end

  defp state_color("worked_on"), do: "bg-info"
  defp state_color(_), do: "bg-base-content/20"
end
