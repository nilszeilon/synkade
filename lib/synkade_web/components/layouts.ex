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
  attr :active_tab, :atom, default: :dashboard, doc: ":dashboard or :settings"
  attr :current_project, :string, default: nil, doc: "selected project name"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen">
      <aside class="w-56 h-screen fixed bg-base-200 flex flex-col border-r border-base-300">
        <%!-- Logo --%>
        <div class="border-b border-base-300">
          <a href="/" class="relative flex items-center justify-center">
            <span
              class="inline-block w-32 h-32 bg-primary"
              style="mask-image: url('/images/cicada.svg'); mask-size: contain; mask-repeat: no-repeat; mask-position: center; -webkit-mask-image: url('/images/cicada.svg'); -webkit-mask-size: contain; -webkit-mask-repeat: no-repeat; -webkit-mask-position: center;"
            >
            </span>
            <span class="absolute bottom-2 ops-label text-primary text-xs tracking-widest">
              Synkade - yolo
            </span>
          </a>
        </div>

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

          <div class="px-3 mb-1">
            <span class="ops-label text-primary/70">Projects</span>
          </div>
          <ul class="menu menu-sm">
            <li :for={{name, _project} <- @projects}>
              <.link
                patch={"/?project=#{name}"}
                class={[@current_project == name && "active"]}
              >
                <span class="truncate text-xs">{name}</span>
                <span
                  :if={running_count(@running, name) > 0}
                  class="badge badge-sm badge-primary"
                >
                  {running_count(@running, name)}
                </span>
              </.link>
            </li>
            <li :if={map_size(@projects) == 0}>
              <span class="text-base-content/30 text-xs">No projects loaded</span>
            </li>
          </ul>
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
          <div :if={@current_scope} class="border-t border-base-300 mt-2 pt-2 px-2">
            <div class="text-xs text-base-content/60 truncate">{@current_scope.user.email}</div>
            <.link
              href="/users/log-out"
              method="delete"
              class="text-xs text-error/70 hover:text-error mt-1 inline-block"
            >
              Log out
            </.link>
          </div>
        </div>
      </aside>

      <main class="ml-56 flex-1 overflow-y-auto min-h-screen">
        <.flash_group flash={@flash} />
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  defp running_count(running, project_name) do
    Enum.count(running, fn {_key, entry} -> entry.project_name == project_name end)
  end

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
