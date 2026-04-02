defmodule SynkadeWeb.SettingsLive.SkillsHelpers do
  @moduledoc "Skills management event handling and components for SettingsLive."

  use Phoenix.Component

  alias Synkade.Skills

  @doc "Handle skills events. Returns `{:halt, socket}` or `:cont`."
  def handle_skills_event("new_skill", _params, socket) do
    changeset = Skills.change_skill(%Synkade.Skills.Skill{})
    {:halt, assign(socket, :skill_form, to_form(changeset))}
  end

  def handle_skills_event("cancel_skill", _params, socket) do
    {:halt, assign(socket, :skill_form, nil)}
  end

  def handle_skills_event("save_skill", %{"skill" => params}, socket) do
    scope = socket.assigns.current_scope

    case Skills.create_skill(scope, params) do
      {:ok, _skill} ->
        {:halt,
         socket
         |> assign(:skills, Skills.list_skills(scope))
         |> assign(:skill_form, nil)
         |> Phoenix.LiveView.put_flash(:info, "Skill created.")}

      {:error, changeset} ->
        {:halt, assign(socket, :skill_form, to_form(changeset))}
    end
  end

  def handle_skills_event("delete_skill", %{"id" => id}, socket) do
    skill = Skills.get_skill!(id)
    scope = socket.assigns.current_scope

    case Skills.delete_skill(scope, skill) do
      {:ok, _} ->
        {:halt,
         socket
         |> assign(:skills, Skills.list_skills(scope))
         |> Phoenix.LiveView.put_flash(:info, "Skill removed.")}

      {:error, _} ->
        {:halt, Phoenix.LiveView.put_flash(socket, :error, "Failed to remove skill.")}
    end
  end

  def handle_skills_event("restore_skill", %{"name" => name}, socket) do
    scope = socket.assigns.current_scope
    default = Enum.find(Skills.defaults(), &(&1["name"] == name))

    if default do
      Skills.create_skill(scope, %{
        "name" => default["name"],
        "content" => default["content"],
        "built_in" => true
      })

      {:halt,
       socket
       |> assign(:skills, Skills.list_skills(scope))
       |> Phoenix.LiveView.put_flash(:info, "Skill re-enabled.")}
    else
      {:halt, socket}
    end
  end

  def handle_skills_event(_event, _params, _socket), do: :cont

  # --- Component ---

  attr :skills, :list, required: true
  attr :skill_form, :any, required: true

  def skills_tab(assigns) do
    defaults = Skills.defaults()
    present_names = MapSet.new(assigns.skills, & &1.name)
    missing_defaults = Enum.reject(defaults, fn d -> d["name"] in present_names end)
    built_in = Enum.filter(assigns.skills, & &1.built_in)
    custom = Enum.reject(assigns.skills, & &1.built_in)

    assigns =
      assign(assigns, built_in: built_in, custom: custom, missing_defaults: missing_defaults)

    ~H"""
    <div>
      <p class="text-sm text-base-content/60 mb-4">
        Skills are prompt files written into every agent's workspace. They define capabilities like creating follow-up issues.
      </p>

      <%!-- Built-in skills --%>
      <%= for skill <- @built_in do %>
        <div class="bg-base-300 rounded p-3 mb-2">
          <div class="flex items-center justify-between mb-1">
            <div class="flex items-center gap-2">
              <span class="font-mono text-sm font-medium">{skill.name}</span>
              <span class="badge badge-primary badge-xs">built-in</span>
            </div>
            <button
              type="button"
              phx-click="delete_skill"
              phx-value-id={skill.id}
              class="btn btn-ghost btn-xs text-warning"
              data-confirm="Disable this built-in skill?"
            >
              Disable
            </button>
          </div>
          <details class="mt-1">
            <summary class="text-xs text-base-content/50 cursor-pointer">View content</summary>
            <pre class="text-xs mt-2 whitespace-pre-wrap opacity-60">{String.trim(skill.content)}</pre>
          </details>
        </div>
      <% end %>

      <%!-- Disabled defaults that can be re-enabled --%>
      <%= for default <- @missing_defaults do %>
        <div class="bg-base-300/50 rounded p-3 mb-2 border border-dashed border-base-300">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="font-mono text-sm font-medium opacity-50">{default["name"]}</span>
              <span class="badge badge-ghost badge-xs">disabled</span>
            </div>
            <button
              type="button"
              phx-click="restore_skill"
              phx-value-name={default["name"]}
              class="btn btn-ghost btn-xs"
            >
              Enable
            </button>
          </div>
        </div>
      <% end %>

      <%!-- Custom skills --%>
      <%= for skill <- @custom do %>
        <div class="bg-base-300 rounded p-3 mb-2">
          <div class="flex items-center justify-between mb-1">
            <span class="font-mono text-sm font-medium">{skill.name}</span>
            <button
              type="button"
              phx-click="delete_skill"
              phx-value-id={skill.id}
              class="btn btn-ghost btn-xs text-error"
              data-confirm="Delete this skill?"
            >
              Remove
            </button>
          </div>
          <details class="mt-1">
            <summary class="text-xs text-base-content/50 cursor-pointer">View content</summary>
            <pre class="text-xs mt-2 whitespace-pre-wrap opacity-60">{String.trim(skill.content)}</pre>
          </details>
        </div>
      <% end %>

      <%!-- New skill form --%>
      <%= if @skill_form do %>
        <div class="card bg-base-200 mt-4">
          <div class="card-body">
            <h3 class="card-title text-sm">New Skill</h3>
            <.form for={@skill_form} phx-submit="save_skill">
              <div class="space-y-3">
                <div class="form-control">
                  <label class="label"><span class="label-text">Name</span></label>
                  <input
                    type="text"
                    class="input input-bordered input-sm w-full font-mono"
                    name="skill[name]"
                    value={@skill_form[:name].value}
                    placeholder="my-skill-name"
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Content</span></label>
                  <textarea
                    class="textarea textarea-bordered w-full font-mono text-xs"
                    rows="8"
                    name="skill[content]"
                    placeholder="---\nname: my-skill\ndescription: What this skill does\nuser-invocable: false\n---\n\nSkill instructions here..."
                  >{@skill_form[:content].value}</textarea>
                </div>
              </div>
              <div class="flex gap-2 mt-4">
                <button type="submit" class="btn btn-primary btn-sm">Save Skill</button>
                <button type="button" phx-click="cancel_skill" class="btn btn-ghost btn-sm">
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% else %>
        <button type="button" phx-click="new_skill" class="btn btn-ghost btn-sm mt-2">
          + Add custom skill
        </button>
      <% end %>
    </div>
    """
  end
end
