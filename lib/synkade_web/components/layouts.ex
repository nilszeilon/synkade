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
      <aside class="w-60 h-screen fixed bg-base-200 flex flex-col border-r border-base-300">
        <%!-- Logo --%>
        <div class="p-4">
          <a href="/" class="flex items-center gap-2">
            <img src={~p"/images/logo.svg"} width="36" />
            <span class="text-sm font-semibold">Synkade</span>
          </a>
        </div>

        <%!-- Navigation --%>
        <nav class="flex-1 overflow-y-auto px-2">
          <ul class="menu menu-sm">
            <li>
              <.link
                navigate="/"
                class={[@active_tab == :dashboard && !@current_project && "active"]}
              >
                <.icon name="hero-squares-2x2" class="size-4" />
                Overview
              </.link>
            </li>
            <li>
              <.link
                navigate="/issues"
                class={[@active_tab == :issues && "active"]}
              >
                <.icon name="hero-clipboard-document-list" class="size-4" />
                Issues
              </.link>
            </li>
          </ul>

          <div class="divider my-1 px-2"></div>

          <div class="px-3 mb-1">
            <span class="text-xs font-semibold uppercase text-base-content/50">Projects</span>
          </div>
          <ul class="menu menu-sm">
            <li :for={{name, _project} <- @projects}>
              <.link
                patch={"/?project=#{name}"}
                class={[@current_project == name && "active"]}
              >
                <span class="truncate">{name}</span>
                <span
                  :if={running_count(@running, name) > 0}
                  class="badge badge-sm badge-primary"
                >
                  {running_count(@running, name)}
                </span>
              </.link>
            </li>
            <li :if={map_size(@projects) == 0}>
              <span class="text-base-content/40 text-xs">No projects loaded</span>
            </li>
          </ul>
        </nav>

        <%!-- Bottom section --%>
        <div class="mt-auto border-t border-base-300 p-2">
          <ul class="menu menu-sm">
            <li>
              <.link navigate="/projects" class={[@active_tab == :projects && "active"]}>
                <.icon name="hero-folder" class="size-4" />
                Projects
              </.link>
            </li>
            <li>
              <.link navigate="/settings" class={[@active_tab == :settings && "active"]}>
                <.icon name="hero-cog-6-tooth" class="size-4" />
                Settings
              </.link>
            </li>
            <li>
              <.link navigate="/logs" class={[@active_tab == :logs && "active"]}>
                <.icon name="hero-command-line" class="size-4" />
                Logs
              </.link>
            </li>
          </ul>
          <div class="px-2 pt-2">
            <.theme_toggle />
          </div>
        </div>
      </aside>

      <main class="ml-60 flex-1 overflow-y-auto min-h-screen">
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

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
