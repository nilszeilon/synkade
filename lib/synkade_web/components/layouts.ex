defmodule SynkadeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SynkadeWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout with a fixed left sidebar.

  ## Examples

      <Layouts.app flash={@flash} projects={@projects} running={@running}
        active_tab={@active_tab} current_project={@current_project}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :projects, :map, default: %{}, doc: "project map from orchestrator"
  attr :running, :map, default: %{}, doc: "running entries for count badges"
  attr :sidebar_issues, :map, default: %{}, doc: "issues grouped by project_id"
  attr :sidebar_diff_stats, :map, default: %{}, doc: "issue_id => {adds, dels}"
  attr :active_tab, :atom, default: :dashboard, doc: ":dashboard or :settings"
  attr :current_project, :string, default: nil, doc: "selected project name"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :picker, :map, default: %{open: false, query: "", results: [], loading: false}

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div id="app-cmdk" phx-hook="CmdK"></div>
    <div id="app-layout" class="flex min-h-screen" phx-hook="ResizableSidebar">
      <aside id="sidebar" class="h-screen fixed bg-base-300 flex flex-col border-r border-base-300" style="width: var(--sidebar-w, 14rem); min-width: 180px; max-width: 400px;">
        <%!-- Navigation --%>
        <nav class="flex-1 overflow-y-auto px-2 pt-3">
          <ul class="menu menu-sm">
            <li>
              <.link
                navigate="/"
                class={[
                  "ops-label",
                  @active_tab == :dashboard && !@current_project && "active"
                ]}
              >
                <.icon name="hero-squares-2x2" class="size-4" /> Overview
              </.link>
            </li>
            <li>
              <.link
                navigate="/issues"
                class={["ops-label", @active_tab == :issues && "active"]}
              >
                <.icon name="hero-clipboard-document-list" class="size-4" /> Issues
              </.link>
            </li>
          </ul>

          <div class="divider my-1 px-2 before:bg-base-300 after:bg-base-300"></div>

          <div class="px-3 mb-1 flex items-center justify-between">
            <span class="ops-label text-primary/70">Projects</span>
            <.link navigate="/projects" title="Add project" class="text-primary/50 hover:text-primary transition-colors">
              <.icon name="hero-plus" class="size-3.5" />
            </.link>
          </div>
          <div :if={map_size(@projects) == 0} class="px-3 text-base-content/30 text-xs">
            No projects loaded
          </div>
          <div :for={{name, project} <- @projects} class="group/proj space-y-0.5 mt-0.5">
            <%!-- Project header --%>
            <div class={[
              "flex items-center gap-1 px-3 h-8 cursor-pointer rounded-lg mx-1 hover:bg-base-200/50",
              @current_project == name && "bg-base-200"
            ]}
              phx-click={JS.toggle_class("hidden", to: "#project-issues-#{project.db_id}")}
            >
              <.icon
                name="hero-chevron-right"
                class="size-3 shrink-0 opacity-0 group-hover/proj:opacity-100 transition-transform"
              />
              <.link patch={"/projects/#{name}"} class="flex-1 min-w-0 truncate text-xs font-medium">
                {name}
              </.link>
              <span
                :if={running_count(@running, name) > 0}
                class="badge badge-xs badge-primary shrink-0"
              >
                {running_count(@running, name)}
              </span>
              <span class="hidden group-hover/proj:inline-flex items-center gap-0.5 shrink-0">
                <.link
                  navigate="/projects"
                  class="hover:text-primary"
                  title="Project settings"
                >
                  <.icon name="hero-cog-6-tooth" class="size-3" />
                </.link>
                <.link
                  patch={"/projects/#{name}?new=true&from_tracker=true"}
                  class="hover:text-primary"
                  title="Pick from tracker"
                >
                  <.icon name="hero-link" class="size-3" />
                </.link>
                <.link
                  navigate={"/chat/#{name}"}
                  class="hover:text-primary"
                  title="New chat"
                >
                  <.icon name="hero-plus" class="size-3" />
                </.link>
              </span>
            </div>
            <%!-- Issues list --%>
            <div id={"project-issues-#{project.db_id}"} class={["space-y-0.5", @current_project != name && "hidden"]}>
              <.link
                :for={issue <- Map.get(@sidebar_issues, project.db_id, [])}
                navigate={"/issues/#{issue.id}"}
                class="flex items-center gap-1.5 px-3 h-8 mx-1 rounded-lg hover:bg-base-200/50 min-w-0"
              >
                <span class={"w-1.5 h-1.5 rounded-full shrink-0 #{sidebar_state_color(issue.state)}"}>
                </span>
                <span class="truncate text-xs flex-1">
                  {Synkade.Issues.Issue.title(issue)}
                </span>
                <% {adds, dels} = Map.get(@sidebar_diff_stats, issue.id, {0, 0}) %>
                <span
                  :if={adds > 0 || dels > 0}
                  class="shrink-0 flex items-center gap-0.5 text-[10px] font-mono"
                >
                  <span :if={adds > 0} class="text-success">+{adds}</span>
                  <span :if={dels > 0} class="text-error">-{dels}</span>
                </span>
              </.link>
              <div
                :if={Map.get(@sidebar_issues, project.db_id, []) == []}
                class="px-3 py-1.5 text-base-content/30 text-xs"
              >
                No active issues
              </div>
            </div>
          </div>
        </nav>

        <%!-- Bottom section --%>
        <div class="mt-auto border-t border-base-300 p-2">
          <ul class="menu menu-sm">
            <li>
              <.link
                navigate="/projects"
                class={["ops-label", @active_tab == :projects && "active"]}
              >
                <.icon name="hero-folder" class="size-4" /> Projects
              </.link>
            </li>
            <li>
              <.link
                navigate="/settings"
                class={["ops-label", @active_tab == :settings && "active"]}
              >
                <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
              </.link>
            </li>
          </ul>
        </div>
      </aside>

      <div id="sidebar-drag" class="fixed top-0 bottom-0 w-1 cursor-col-resize hover:bg-primary/40 active:bg-primary/60 transition-colors z-50 before:content-[''] before:absolute before:inset-y-0 before:-left-1 before:w-3" style="left: var(--sidebar-w, 14rem);"></div>

      <main id="main-content" class="flex-1 overflow-y-auto min-h-screen" style="margin-left: var(--sidebar-w, 14rem);">
        <.flash_group flash={@flash} />
        {render_slot(@inner_block)}
      </main>

      <SynkadeWeb.Picker.picker picker={@picker} />
    </div>
    """
  end

  defp running_count(running, project_name) do
    Enum.count(running, fn {_key, entry} -> entry.project_name == project_name end)
  end

  defp sidebar_state_color("in_progress"), do: "bg-info"
  defp sidebar_state_color("queued"), do: "bg-warning"
  defp sidebar_state_color("awaiting_review"), do: "bg-accent"
  defp sidebar_state_color("backlog"), do: "bg-base-content/30"
  defp sidebar_state_color(_), do: "bg-base-content/20"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
