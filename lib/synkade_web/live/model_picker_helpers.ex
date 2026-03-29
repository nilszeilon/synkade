defmodule SynkadeWeb.ModelPickerHelpers do
  @moduledoc """
  Shared model picker logic for LiveViews. Call `handle_model_picker_event/3`
  from your `handle_event`, and `handle_model_picker_info/2` from your
  `handle_info` to wire up the search picker for models.

  Requires assigns: `:selected_model`, `:model_picker`, `:model_picker_items`.
  """
  import Phoenix.Component, only: [assign: 3]

  alias Synkade.Agent.ModelCache
  alias Synkade.Settings
  alias SynkadeWeb.Components.SearchPicker

  @doc "Initial assigns for model picker. Pass a project to load its persisted default model."
  def model_picker_assigns(project \\ nil) do
    selected = if project, do: project.default_model, else: nil
    [selected_model: selected, model_picker: SearchPicker.default(), model_picker_items: []]
  end

  @doc """
  Handles model picker events. Returns `{:halt, socket}` if handled,
  `:cont` if the event is not a model picker event.
  """
  def handle_model_picker_event("model_picker_open", %{"kind" => kind}, socket) do
    # Fetch in a Task to avoid blocking the LiveView process
    lv = self()

    Task.start(fn ->
      api_key = resolve_api_key(socket, kind)
      items = fetch_and_build_items(kind, api_key)
      send(lv, {:models_fetched, items})
    end)

    socket =
      socket
      |> assign(:model_picker, %{SearchPicker.default() | open: true, loading: true})
      |> assign(:model_picker_items, [])

    {:halt, socket}
  end

  def handle_model_picker_event("model_picker_close", _params, socket) do
    {:halt, assign(socket, :model_picker, SearchPicker.default())}
  end

  def handle_model_picker_event("model_picker_search", %{"query" => query}, socket) do
    all_items = socket.assigns.model_picker_items
    filtered = SearchPicker.filter_items(all_items, query)

    {:halt,
     assign(socket, :model_picker, %{SearchPicker.default() | open: true, query: query, items: filtered})}
  end

  def handle_model_picker_event("model_picker_select", %{"id" => model_id}, socket) do
    socket = persist_selected_model(socket, model_id)

    {:halt,
     socket
     |> assign(:selected_model, model_id)
     |> assign(:model_picker, SearchPicker.default())}
  end

  def handle_model_picker_event("model_picker_submit", %{"query" => _query}, socket) do
    picker = socket.assigns.model_picker

    case picker.items do
      [first | _] ->
        socket = persist_selected_model(socket, first.id)

        {:halt,
         socket
         |> assign(:selected_model, first.id)
         |> assign(:model_picker, SearchPicker.default())}

      _ ->
        {:halt, assign(socket, :model_picker, SearchPicker.default())}
    end
  end

  def handle_model_picker_event(_event, _params, _socket), do: :cont

  @doc """
  Handles async model fetch results. Call from `handle_info`.
  Returns `{:halt, socket}` if handled, `:cont` if not a model picker message.
  """
  def handle_model_picker_info({:models_fetched, items}, socket) do
    socket =
      socket
      |> assign(:model_picker_items, items)
      |> assign(:model_picker, SearchPicker.open(items))

    {:halt, socket}
  end

  def handle_model_picker_info(_msg, _socket), do: :cont

  defp persist_selected_model(socket, model_id) do
    case socket.assigns do
      %{project: %{id: _} = project, current_scope: scope} ->
        Settings.update_project(scope, project, %{default_model: model_id})
        assign(socket, :project, %{project | default_model: model_id})

      _ ->
        socket
    end
  end

  defp resolve_api_key(socket, kind) do
    agents = socket.assigns[:agents] || []
    agent = Enum.find(agents, &(&1.kind == kind))
    if agent, do: agent.api_key
  end

  defp fetch_and_build_items(_kind, nil), do: []

  defp fetch_and_build_items(kind, api_key) do
    case ModelCache.get_or_fetch(kind, api_key) do
      {:ok, models} ->
        Enum.map(models, fn {label, model_id} ->
          %{id: model_id, label: label, description: model_id}
        end)

      {:error, _} ->
        []
    end
  end
end
