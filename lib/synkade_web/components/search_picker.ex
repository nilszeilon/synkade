defmodule SynkadeWeb.Components.SearchPicker do
  @moduledoc """
  Generic searchable picker modal. Renders a cmd+k style overlay with a
  search input and filterable item list.

  ## State

  The parent manages picker state as a map:

      %{open: false, query: "", items: [], loading: false}

  Use `new/0` or `new/1` for defaults, and `filter_items/2` for client-side
  filtering of static item lists.

  ## Items

  Each item is a map with at least `:id` and `:label`. Optional keys:

  - `:description` — shown as secondary text
  - `:dot_color` — CSS class for a leading dot (e.g. "bg-info")
  - `:icon` — slot-compatible assign forwarded to the `:item` slot

  ## Events

  The component fires these events (prefixed with `name`):

  - `"\#{name}_search"` — `%{"query" => query}` on input change
  - `"\#{name}_select"` — `%{"id" => id}` on item click
  - `"\#{name}_submit"` — `%{"query" => query}` on enter (selects first highlighted)
  - `"\#{name}_close"` — close the picker

  ## Usage

      <.search_picker name="model_picker" state={@model_picker} placeholder="Search models..." />
  """
  use Phoenix.Component

  @default %{open: false, query: "", items: [], loading: false}

  @doc "Returns default picker state."
  def new(items \\ []), do: %{@default | items: items}

  @doc "Returns default (closed) state."
  def default, do: @default

  @doc "Opens a picker with items."
  def open(items), do: %{@default | open: true, items: items}

  @doc "Filters items by query matching label or description (case-insensitive)."
  def filter_items(items, ""), do: items

  def filter_items(items, query) do
    q = String.downcase(query)

    Enum.filter(items, fn item ->
      String.contains?(String.downcase(item.label), q) ||
        (item[:description] && String.contains?(String.downcase(item.description), q))
    end)
  end

  # --- Component ---

  attr :name, :string, required: true
  attr :state, :map, required: true
  attr :placeholder, :string, default: "Search..."
  attr :empty_message, :string, default: "No results"

  def search_picker(assigns) do
    items = assigns.state.items
    query = assigns.state.query

    first_highlighted = query != "" && items != []

    assigns =
      assigns
      |> assign(:items, items)
      |> assign(:first_highlighted, first_highlighted)
      |> assign(:open, assigns.state.open)
      |> assign(:query, query)
      |> assign(:loading, assigns.state[:loading] || false)
      |> assign(:close_event, "#{assigns.name}_close")
      |> assign(:search_event, "#{assigns.name}_search")
      |> assign(:submit_event, "#{assigns.name}_submit")
      |> assign(:select_event, "#{assigns.name}_select")
      |> assign(:input_id, "#{assigns.name}-input")

    ~H"""
    <div
      :if={@open}
      class="fixed inset-0 z-50 flex items-start justify-center pt-[20vh]"
      phx-window-keydown={@close_event}
      phx-key="Escape"
    >
      <div class="fixed inset-0 bg-black/40" phx-click={@close_event}></div>
      <div class="relative w-full max-w-lg mx-4 bg-base-100 rounded-xl shadow-2xl border border-base-300 overflow-hidden">
        <form phx-change={@search_event} phx-submit={@submit_event} class="p-3">
          <input
            id={@input_id}
            type="text"
            name="query"
            placeholder={@placeholder}
            value={@query}
            phx-debounce="150"
            class="input input-bordered w-full"
            phx-hook="AutoFocus"
            autocapitalize="off"
            autocomplete="off"
            spellcheck="false"
          />
        </form>

        <div class="max-h-72 overflow-y-auto px-2 pb-2">
          <div
            :if={@loading}
            class="flex items-center gap-2 text-base-content/50 py-6 justify-center"
          >
            <span class="loading loading-spinner loading-sm"></span>
            <span class="text-sm">Loading...</span>
          </div>

          <div :if={!@loading} class="space-y-0.5">
            <div
              :for={{item, idx} <- Enum.with_index(@items)}
              phx-click={@select_event}
              phx-value-id={item.id}
              class={[
                "flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors",
                if(idx == 0 && @first_highlighted, do: "bg-base-200", else: "hover:bg-base-200")
              ]}
            >
              <span
                :if={item[:dot_color]}
                class={["size-2 rounded-full shrink-0", item.dot_color]}
              >
              </span>
              <div class="flex-1 min-w-0">
                <span class="text-sm truncate block">{item.label}</span>
                <span :if={item[:description]} class="text-xs text-base-content/40 truncate block">
                  {item.description}
                </span>
              </div>
              <kbd
                :if={idx == 0 && @first_highlighted}
                class="kbd kbd-xs text-base-content/30"
              >
                ↵
              </kbd>
            </div>

            <div :if={@items == [] && @query != ""} class="py-6 text-center">
              <p class="text-base-content/50 text-sm">{@empty_message}</p>
            </div>

            <div :if={@items == [] && @query == ""} class="py-6 text-center">
              <p class="text-base-content/50 text-sm">{@empty_message}</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
