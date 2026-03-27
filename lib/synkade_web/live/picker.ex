defmodule SynkadeWeb.Picker do
  @moduledoc """
  Global command palette (cmd+k). Searches issues and navigates on select.

  Usage: add `on_mount: [{SynkadeWeb.Picker, :picker}]` to your live_session,
  then render `<SynkadeWeb.Picker.picker picker={@picker} />` in the layout.
  """
  import Phoenix.LiveView
  use Phoenix.Component

  alias Synkade.Issues.Issue

  @default %{open: false, query: "", results: [], loading: false}

  def on_mount(:picker, _params, _session, socket) do
    socket =
      socket
      |> assign(:picker, @default)
      |> attach_hook(:picker_events, :handle_event, &handle_picker_event/3)
      |> attach_hook(:picker_info, :handle_info, &handle_picker_info/2)

    {:cont, socket}
  end

  # --- Event handlers ---

  defp handle_picker_event("open_picker", _params, socket) do
    send(self(), {:picker_search, ""})
    {:halt, assign(socket, :picker, %{@default | open: true, loading: true})}
  end

  defp handle_picker_event("close_picker", _params, socket) do
    {:halt, assign(socket, :picker, @default)}
  end

  defp handle_picker_event("picker_search", %{"query" => query}, socket) do
    send(self(), {:picker_search, query})
    picker = %{socket.assigns.picker | query: query, loading: true}
    {:halt, assign(socket, :picker, picker)}
  end

  defp handle_picker_event("picker_submit", %{"query" => query}, socket) do
    picker = socket.assigns.picker

    case picker.results do
      [first | _] ->
        {:halt,
         socket
         |> assign(:picker, @default)
         |> push_navigate(to: "/issues/#{first.id}")}

      [] when query != "" ->
        {:halt, assign(socket, :picker, @default)}

      _ ->
        {:halt, socket}
    end
  end

  defp handle_picker_event("picker_go", %{"id" => id}, socket) do
    {:halt,
     socket
     |> assign(:picker, @default)
     |> push_navigate(to: "/issues/#{id}")}
  end

  defp handle_picker_event(_event, _params, socket), do: {:cont, socket}

  # --- Info handlers ---

  defp handle_picker_info({:picker_search, query}, socket) do
    results = search_issues(query)
    picker = %{socket.assigns.picker | results: results, loading: false}
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
  end

  # --- Component ---

  attr :picker, :map, required: true

  def picker(assigns) do
    results = assigns.picker.results

    first_highlighted =
      assigns.picker.query != "" && results != []

    assigns =
      assigns
      |> assign(:results, results)
      |> assign(:first_highlighted, first_highlighted)

    ~H"""
    <div
      :if={@picker.open}
      class="fixed inset-0 z-50 flex items-start justify-center pt-[20vh]"
      phx-window-keydown="close_picker"
      phx-key="Escape"
    >
      <div class="fixed inset-0 bg-black/40" phx-click="close_picker"></div>
      <div class="relative w-full max-w-lg mx-4 bg-base-100 rounded-xl shadow-2xl border border-base-300 overflow-hidden">
        <form phx-change="picker_search" phx-submit="picker_submit" class="p-3">
          <input
            id="picker-input"
            type="text"
            name="query"
            placeholder="Search issues..."
            value={@picker.query}
            phx-debounce="150"
            class="input input-bordered w-full"
            phx-hook="AutoFocus"
          />
        </form>

        <div class="max-h-72 overflow-y-auto px-2 pb-2">
          <div :if={@picker.loading} class="flex items-center gap-2 text-base-content/50 py-6 justify-center">
            <span class="loading loading-spinner loading-sm"></span>
            <span class="text-sm">Loading...</span>
          </div>

          <div :if={!@picker.loading} class="space-y-0.5">
            <div
              :for={{issue, idx} <- Enum.with_index(@results)}
              phx-click="picker_go"
              phx-value-id={issue.id}
              class={[
                "flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors",
                if(idx == 0 && @first_highlighted, do: "bg-base-200", else: "hover:bg-base-200")
              ]}
            >
              <span class={[
                "size-2 rounded-full shrink-0",
                state_color(issue.state)
              ]}></span>
              <span class="text-sm flex-1 min-w-0 truncate">{Synkade.Issues.Issue.title(issue)}</span>
              <kbd :if={idx == 0 && @first_highlighted} class="kbd kbd-xs text-base-content/30">↵</kbd>
            </div>

            <div :if={@results == [] && @picker.query != ""} class="py-6 text-center">
              <p class="text-base-content/50 text-sm">No matching issues</p>
            </div>

            <div :if={@results == [] && @picker.query == ""} class="py-6 text-center">
              <p class="text-base-content/50 text-sm">No issues yet</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp state_color("worked_on"), do: "bg-info"
  defp state_color(_), do: "bg-base-content/20"
end
