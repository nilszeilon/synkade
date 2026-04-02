defmodule SynkadeWeb.Components.Ide.ChangesPanel do
  @moduledoc """
  Right panel for the IDE — PR actions, branch status, and file change list.
  """
  use Phoenix.Component

  import SynkadeWeb.CoreComponents
  import SynkadeWeb.Components.Ide.DiffView, only: [file_list_entry: 1]

  attr :issue, :map, default: nil
  attr :pr_info, :map, default: nil
  attr :pr_checks, :atom, default: :unknown
  attr :running_entry, :any, default: nil
  attr :current_branch, :string, default: nil
  attr :commits_ahead, :integer, default: 0
  attr :changed_files, :list, default: []
  attr :selected_file, :string, default: nil
  attr :turn_filter, :boolean, default: false
  attr :last_turn_files, :list, default: []

  def changes_panel(assigns) do
    files = displayed_files(assigns)
    assigns = assign(assigns, :files, files)

    ~H"""
    <div id="ide-right" class="flex flex-col min-w-0 bg-base-100" style="width: var(--split-right-w, 320px); flex-shrink: 0">
      <%!-- Top bar: PR actions --%>
      <div :if={@issue} class="flex items-center justify-end gap-2 px-3 py-2 border-b border-base-300">
        <%= if @pr_info do %>
          <%!-- PR exists: show checks status + merge button --%>
          <a href={@pr_info.url} target="_blank" class="flex items-center gap-1.5 text-xs mr-auto min-w-0">
            <span class={[
              "size-2 rounded-full flex-shrink-0",
              case @pr_checks do
                :success -> "bg-success"
                :failure -> "bg-error"
                :pending -> "bg-warning"
                _ -> "bg-base-content/20"
              end
            ]}></span>
            <span class="truncate text-base-content/60">#{@pr_info.number}</span>
          </a>
          <button
            :if={@pr_checks == :failure}
            phx-click="fix_checks"
            class="btn btn-xs btn-error btn-outline rounded-full gap-1"
            disabled={@running_entry != nil}
          >
            Fix CI
          </button>
          <button
            phx-click="merge_pr"
            class="btn btn-sm btn-outline rounded-full gap-1.5"
            disabled={@running_entry != nil || @pr_checks == :failure}
          >
            <svg class="size-3.5" viewBox="0 0 16 16" fill="currentColor">
              <path d="M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8-9a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM4.25 4a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z"></path>
            </svg>
            Merge PR
          </button>
        <% else %>
          <%!-- No PR: show create button --%>
          <button
            phx-click="create_pr"
            class="btn btn-sm btn-outline rounded-full gap-1.5"
            disabled={@running_entry != nil}
          >
            <svg class="size-3.5" viewBox="0 0 16 16" fill="currentColor">
              <path d="M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z"></path>
            </svg>
            Create PR
          </button>
        <% end %>
      </div>
      <%!-- Tab bar --%>
      <div class="flex items-center gap-2 px-4 border-b border-base-300">
        <button
          :if={@turn_filter}
          phx-click="toggle_turn_filter"
          class="py-2 text-sm font-medium border-b-2 border-transparent text-base-content/50 hover:text-base-content/80"
        >
          All files
        </button>
        <span class="py-2 text-sm font-medium border-b-2 border-primary text-base-content">
          Changes <span class="text-base-content/40">{length(@files)}</span>
        </span>
        <button
          :if={@turn_filter && @last_turn_files != []}
          phx-click="toggle_turn_filter"
          class="ml-auto flex items-center gap-1 text-xs bg-base-300/70 rounded-full px-2 py-0.5 text-base-content/50 hover:text-base-content/70"
        >
          <.icon name="hero-x-mark" class="size-3" /> Latest turn
        </button>
      </div>
      <%!-- Branch status --%>
      <div :if={@current_branch} class="flex items-center gap-2 px-4 py-1.5 text-xs text-base-content/40 border-b border-base-300">
        <span class="font-mono truncate">{@current_branch}</span>
        <span :if={@commits_ahead > 0} class="flex-shrink-0">
          &middot; {if @commits_ahead == 1, do: "1 commit", else: "#{@commits_ahead} commits"} ahead
        </span>
      </div>
      <%!-- File list --%>
      <div class="flex-1 overflow-y-auto">
        <div :if={@files == []} class="text-sm text-base-content/30 py-8 text-center">
          No changes detected
        </div>
        <.file_list_entry
          :for={entry <- @files}
          entry={entry}
          selected={@selected_file == entry.file}
        />
      </div>
    </div>
    """
  end

  defp displayed_files(%{turn_filter: true, last_turn_files: turn_files}) when turn_files != [] do
    turn_files
  end

  defp displayed_files(%{changed_files: files}), do: files
end
