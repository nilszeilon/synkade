defmodule SynkadeWeb.AgentPickerHelpers do
  @moduledoc """
  Shared agent picker logic for LiveViews. Works like the model picker —
  a trigger button that opens a SearchPicker overlay.

  Requires assigns: `:agents`, `:selected_dispatch_agent_id`, `:agent_picker`.
  """
  import Phoenix.Component, only: [assign: 3]

  alias SynkadeWeb.Components.SearchPicker

  @doc "Initial assigns for agent picker."
  def agent_picker_assigns do
    [agent_picker: SearchPicker.default()]
  end

  @doc """
  Handles agent picker events. Returns `{:halt, socket}` if handled,
  `:cont` if the event is not an agent picker event.
  """
  def handle_agent_picker_event("agent_picker_open", _params, socket) do
    agents = socket.assigns[:agents] || []

    items =
      Enum.map(agents, fn agent ->
        %{id: agent.id, label: agent.name, description: agent.kind}
      end)

    {:halt, assign(socket, :agent_picker, SearchPicker.open(items))}
  end

  def handle_agent_picker_event("agent_picker_close", _params, socket) do
    {:halt, assign(socket, :agent_picker, SearchPicker.default())}
  end

  def handle_agent_picker_event("agent_picker_search", %{"query" => query}, socket) do
    agents = socket.assigns[:agents] || []

    all_items =
      Enum.map(agents, fn agent ->
        %{id: agent.id, label: agent.name, description: agent.kind}
      end)

    filtered = SearchPicker.filter_items(all_items, query)

    {:halt,
     assign(socket, :agent_picker, %{SearchPicker.default() | open: true, query: query, items: filtered})}
  end

  def handle_agent_picker_event("agent_picker_select", %{"id" => agent_id}, socket) do
    {:halt,
     socket
     |> assign(:selected_dispatch_agent_id, agent_id)
     |> assign(:selected_model, nil)
     |> assign(:agent_picker, SearchPicker.default())}
  end

  def handle_agent_picker_event("agent_picker_submit", %{"query" => _query}, socket) do
    picker = socket.assigns.agent_picker

    case picker.items do
      [first | _] ->
        {:halt,
         socket
         |> assign(:selected_dispatch_agent_id, first.id)
         |> assign(:selected_model, nil)
         |> assign(:agent_picker, SearchPicker.default())}

      _ ->
        {:halt, assign(socket, :agent_picker, SearchPicker.default())}
    end
  end

  def handle_agent_picker_event(_event, _params, _socket), do: :cont
end
