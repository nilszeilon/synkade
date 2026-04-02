defmodule SynkadeWeb.Components.Ide.TopBar do
  use Phoenix.Component

  import SynkadeWeb.CoreComponents
  import SynkadeWeb.IssueLiveHelpers, only: [state_badge_class: 1]

  alias Synkade.Issues.Issue

  attr :issue, :map, default: nil
  attr :project, :map, required: true
  attr :current_branch, :string, default: nil
  attr :base_branch, :string, default: "HEAD"
  attr :running_entry, :any, default: nil

  def top_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-3 px-4 py-2 border-b border-base-300 flex-shrink-0">
      <.link navigate="/issues" class="btn btn-ghost btn-xs gap-1">
        <.icon name="hero-arrow-left" class="size-3" />
      </.link>
      <%= if @issue do %>
        <span class={"badge badge-xs #{state_badge_class(@issue.state)}"}>{@issue.state}</span>
        <h1 class="text-sm font-semibold truncate flex-1">{Issue.title(@issue)}</h1>
      <% else %>
        <span class="badge badge-xs badge-ghost">draft</span>
        <h1 class="text-sm font-semibold truncate flex-1">New chat — {@project.name}</h1>
      <% end %>
      <span :if={@current_branch} class="text-xs font-mono text-base-content/40 flex-shrink-0">
        {@base_branch} ← {@current_branch}
      </span>
      <div :if={@running_entry} class="flex items-center gap-1.5">
        <span class="loading loading-spinner loading-xs text-info"></span>
        <span class="text-xs text-base-content/50">Agent running</span>
      </div>
      <button
        :if={@issue && @issue.state != "done"}
        phx-click="complete_issue"
        class="btn btn-ghost btn-xs text-base-content/40 hover:text-base-content"
        title="Archive issue"
      >
        <.icon name="hero-archive-box-arrow-down" class="size-4" />
      </button>
    </div>
    """
  end
end
