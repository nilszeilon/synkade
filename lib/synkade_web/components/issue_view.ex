defmodule SynkadeWeb.Components.IssueView do
  @moduledoc """
  Shared full-width issue view component used by IssuesLive and DashboardLive.
  """
  use Phoenix.Component

  import SynkadeWeb.CoreComponents
  import SynkadeWeb.Components.AgentBrand
  import SynkadeWeb.Components.SearchPicker
  import SynkadeWeb.IssueLiveHelpers, only: [state_badge_class: 1, format_relative_time: 1]
  alias Synkade.Issues.Issue
  alias Synkade.Settings.Agent

  attr :issue, :map, required: true
  attr :ancestors, :list, required: true
  attr :dispatch_form, :any, required: true
  attr :agents, :list, required: true
  attr :session_events, :list, default: []
  attr :session_id, :string, default: nil
  attr :running_entry, :any, default: nil
  attr :back_path, :string, required: true
  attr :back_label, :string, default: "Back"
  attr :selected_model, :string, default: nil
  attr :resolved_agent_kind, :string, default: nil
  attr :model_picker, :map, default: %{open: false, query: "", items: [], loading: false}

  def issue_full_view(assigns) do
    messages = (assigns.issue.metadata || %{})["messages"] || []
    assigns = assign(assigns, :messages, messages)

    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-4 flex items-center gap-2">
        <.link patch={@back_path} class="btn btn-ghost btn-sm gap-1">
          <.icon name="hero-arrow-left" class="size-4" />
          {@back_label}
        </.link>
      </div>

      <div class="mb-4">
        <span class={"badge badge-sm #{state_badge_class(@issue.state)} mb-2"}>{@issue.state}</span>
        <span :if={@issue.auto_merge} class="badge badge-sm badge-warning mb-2">auto-merge</span>
        <span :if={@issue.recurring} class="badge badge-sm badge-accent mb-2">
          every {@issue.recurrence_interval} {@issue.recurrence_unit}
        </span>
        <h1 class="text-2xl font-bold">{Issue.title(@issue)}</h1>
      </div>
      
    <!-- Agent status bar -->
      <div
        :if={@running_entry}
        class="mb-4 px-4 py-3 bg-info/10 rounded-lg flex items-center gap-2"
      >
        <span :if={@running_entry[:agent_kind]} class={brand_color(@running_entry[:agent_kind])}>
          <.agent_icon kind={@running_entry[:agent_kind]} class="size-4" />
        </span>
        <span class="loading loading-spinner loading-sm text-info"></span>
        <div class="flex-1 min-w-0">
          <p
            :if={@running_entry.last_agent_message && @running_entry.last_agent_message != ""}
            class="text-sm text-base-content/70 truncate"
            title={@running_entry.last_agent_message}
          >
            {@running_entry.last_agent_message}
          </p>
          <p
            :if={!@running_entry.last_agent_message || @running_entry.last_agent_message == ""}
            class="text-sm text-base-content/50"
          >
            Agent running...
          </p>
        </div>
        <span
          :if={@running_entry.last_agent_timestamp}
          class="text-sm text-base-content/40 flex-shrink-0"
        >
          {format_relative_time(@running_entry.last_agent_timestamp)}
        </span>
      </div>
      
    <!-- Ancestor thread -->
      <div :for={ancestor <- @ancestors} class="border-l-2 border-base-300 pl-4 mb-4">
        <p class="text-sm font-semibold text-base-content/70">{Issue.title(ancestor)}</p>
        <p :if={ancestor.body} class="text-sm text-base-content/60 whitespace-pre-wrap mt-1">
          {ancestor.body}
        </p>
        <div :if={ancestor.agent_output} class="mt-2">
          <div class="collapse collapse-arrow bg-base-200 rounded">
            <input type="checkbox" />
            <div class="collapse-title text-xs py-2 min-h-0 text-base-content/50">
              Agent output
            </div>
            <div class="collapse-content">
              <pre class="text-xs whitespace-pre-wrap overflow-auto max-h-64">{ancestor.agent_output}</pre>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Current issue body -->
      <div class="border-l-2 border-primary pl-4 mb-4">
        <p :if={body_without_title(@issue.body)} class="text-sm whitespace-pre-wrap">
          {body_without_title(@issue.body)}
        </p>
        <!-- Show agent_output in drawer when no message history covers it -->
        <div :if={@issue.agent_output && @messages == []} class="mt-3">
          <div class="collapse collapse-arrow bg-base-200 rounded">
            <input type="checkbox" />
            <div class="collapse-title text-xs py-2 min-h-0 text-base-content/50">
              Agent output
            </div>
            <div class="collapse-content">
              <pre class="text-xs whitespace-pre-wrap overflow-auto max-h-64">{@issue.agent_output}</pre>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Message history (numbered) -->
      <div :if={@messages != []} class="mb-4 space-y-3">
        <div :for={{msg, idx} <- Enum.with_index(@messages, 1)}>
          <%= cond do %>
            <% msg["type"] == "dispatch" -> %>
              <div class="border-l-2 border-info pl-4">
                <p class="text-xs text-base-content/50 font-semibold mb-1 inline-flex items-center gap-1">
                  <span :if={msg["agent_kind"]} class={brand_color(msg["agent_kind"])}>
                    <.agent_icon kind={msg["agent_kind"]} class="size-3.5" />
                  </span>
                  #{idx}{if msg["agent_kind"], do: " — #{agent_display_name(msg)}", else: ""}
                </p>
                <p class="text-sm whitespace-pre-wrap">{msg["text"]}</p>
              </div>
            <% msg["type"] == "system" -> %>
              <div class="border-l-2 border-accent pl-4">
                <p class="text-xs text-base-content/50 font-semibold mb-1">
                  #{idx} — system
                </p>
                <p class="text-sm whitespace-pre-wrap italic text-base-content/70">{msg["text"]}</p>
              </div>
            <% true -> %>
              <div class="border-l-2 border-success pl-4">
                <p class="text-xs text-base-content/50 font-semibold mb-1 inline-flex items-center gap-1">
                  <span :if={msg["agent_kind"]} class={brand_color(msg["agent_kind"])}>
                    <.agent_icon kind={msg["agent_kind"]} class="size-3.5" />
                  </span>
                  #{idx} — {agent_display_name(msg)} output
                </p>
                <div class="collapse collapse-arrow bg-base-200 rounded">
                  <input type="checkbox" />
                  <div class="collapse-title text-xs py-2 min-h-0">
                    {msg["text"]
                    |> String.slice(0..120)
                    |> then(fn s ->
                      if String.length(msg["text"] || "") > 120, do: s <> "...", else: s
                    end)}
                  </div>
                  <div class="collapse-content">
                    <pre class="text-xs whitespace-pre-wrap overflow-auto max-h-64">{msg["text"]}</pre>
                  </div>
                </div>
              </div>
          <% end %>
        </div>
      </div>
      
    <!-- Agent session log -->
      <div
        :if={@issue.state == "worked_on" && (@session_events != [] || @session_id)}
        class="mb-4"
      >
        <div class="flex items-center justify-between mb-2">
          <p class="text-sm text-base-content/50 font-semibold inline-flex items-center gap-1.5">
            <span
              :if={@running_entry && @running_entry[:agent_kind]}
              class={brand_color(@running_entry[:agent_kind])}
            >
              <.agent_icon kind={@running_entry[:agent_kind]} class="size-4" />
            </span>
            Agent Session
          </p>
          <div :if={@session_id} class="flex items-center gap-1">
            <code class="text-xs text-base-content/40 font-mono">
              {String.slice(@session_id, 0..11)}...
            </code>
            <button
              phx-click="copy_resume"
              class="btn btn-ghost btn-xs"
              title={"claude --resume #{@session_id}"}
            >
              Copy
            </button>
          </div>
        </div>
        <div
          id="session-event-log"
          class="bg-base-300 rounded p-3 max-h-80 overflow-y-auto font-mono text-xs space-y-1"
          phx-hook="AutoScroll"
        >
          <.session_event :for={event <- @session_events} event={event} />
        </div>
        <p :if={@session_events == []} class="text-xs text-base-content/40 text-center py-2">
          Waiting for agent events...
        </p>
      </div>
      
    <!-- Children list -->
      <div :if={@issue.children != [] and is_list(@issue.children)} class="mb-4">
        <p class="text-sm text-base-content/50 mb-2">Children ({length(@issue.children)})</p>
        <div :for={child <- @issue.children} class="flex items-center gap-2 py-1.5">
          <span
            class="text-sm cursor-pointer hover:underline"
            phx-click="select_issue"
            phx-value-id={child.id}
          >
            {Issue.title(child)}
          </span>
          <span class={"badge badge-xs #{state_badge_class(child.state)} ml-auto"}>
            {child.state}
          </span>
        </div>
      </div>
      
    <!-- GitHub links -->
      <div :if={@issue.github_issue_url || @issue.github_pr_url} class="mb-4 flex gap-3">
        <a
          :if={@issue.github_issue_url}
          href={@issue.github_issue_url}
          target="_blank"
          class="link link-primary text-sm"
        >
          GitHub Issue
        </a>
        <a
          :if={@issue.github_pr_url}
          href={@issue.github_pr_url}
          target="_blank"
          class="link link-primary text-sm"
        >
          Pull Request
        </a>
      </div>
      
    <!-- Bottom input + actions -->
      <div class="border-t border-base-300 pt-4">
        <div :if={@issue.state in ["backlog", "done"]} class="mb-3">
          <.form for={@dispatch_form} phx-submit="dispatch_issue">
            <div class="flex flex-col gap-2">
              <textarea
                name="dispatch[message]"
                placeholder="@agent instructions..."
                class="textarea textarea-bordered textarea-sm w-full font-mono min-h-24"
                rows="4"
                phx-debounce="300"
              ><%= @dispatch_form[:message].value %></textarea>
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <.model_trigger
                    agent_kind={@resolved_agent_kind}
                    selected_model={@selected_model}
                    show_hint
                  />
                </div>
                <button type="submit" class="btn btn-sm btn-primary">Dispatch</button>
              </div>
              <.search_picker
                name="model_picker"
                state={@model_picker}
                placeholder="Search models..."
                empty_message="No models available"
              />
            </div>
          </.form>
        </div>

        <div class="flex gap-2">
          <button
            :if={@issue.state == "worked_on"}
            phx-click="move_to_backlog"
            phx-value-id={@issue.id}
            class="btn btn-sm btn-ghost"
          >
            Backlog
          </button>
          <button
            :if={@issue.state != "done"}
            phx-click="complete_issue"
            phx-value-id={@issue.id}
            class="btn btn-sm btn-ghost"
          >
            Done
          </button>
          <button
            phx-click="new_issue"
            phx-value-parent_id={@issue.id}
            class="btn btn-sm btn-ghost"
          >
            Add Child
          </button>
          <button
            phx-click="delete_issue"
            phx-value-id={@issue.id}
            class="btn btn-sm btn-error btn-ghost ml-auto"
            data-confirm="Delete this issue and orphan its children?"
          >
            Delete
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :db_projects, :list, required: true
  attr :agents, :list, default: []
  attr :selected_agent_id, :string, default: nil
  attr :form_project_id, :any, default: nil
  attr :form_parent_id, :any, default: nil
  attr :create_ancestors, :list, default: []
  attr :back_path, :string, required: true

  def issue_create_view(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-4">
        <.link patch={@back_path} class="btn btn-ghost btn-sm gap-1">
          <.icon name="hero-arrow-left" class="size-4" /> Issues
        </.link>
      </div>

      <div class="mb-4">
        <span class="badge badge-sm badge-info mb-2">new</span>
        <h1 class="text-2xl font-bold">New Issue</h1>
      </div>
      
    <!-- Ancestor thread (when creating a child) -->
      <div :for={ancestor <- @create_ancestors} class="border-l-2 border-base-300 pl-4 mb-4">
        <p class="text-sm font-semibold text-base-content/70">{Issue.title(ancestor)}</p>
        <p :if={ancestor.body} class="text-sm text-base-content/60 whitespace-pre-wrap mt-1">
          {body_without_title(ancestor.body)}
        </p>
      </div>

      <div class="border-l-2 border-primary pl-4 mb-4">
        <.form for={@form} phx-change="validate_issue" phx-submit="save_issue">
          <div class="flex flex-col gap-3">
            <div :if={length(@db_projects) > 1} class="form-control">
              <select name="issue[project_id]" class="select select-bordered select-sm">
                <option
                  :for={p <- @db_projects}
                  value={p.id}
                  selected={p.id == @form_project_id}
                >
                  {p.name}
                </option>
              </select>
            </div>
            <div class="form-control">
              <textarea
                id="issue-body-input"
                name="issue[body]"
                placeholder="# Issue title\n\nDescribe the issue..."
                class="textarea textarea-bordered w-full font-mono min-h-32"
                rows="8"
                phx-debounce="300"
                phx-hook={if(@form[:body].value && @form[:body].value != "", do: "CursorEnd")}
              ><%= @form[:body].value %></textarea>
            </div>
          </div>

          <div class="border-t border-base-300 pt-4 mt-4 space-y-3">
            <div :if={@agents != []} class="flex items-center gap-2">
              <input type="hidden" name="agent_id" value={@selected_agent_id || ""} />
              <button
                :for={agent <- @agents}
                type="button"
                phx-click="select_create_agent"
                phx-value-id={agent.id}
                class={[
                  "flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border text-sm transition-all cursor-pointer",
                  if(@selected_agent_id == agent.id,
                    do: "border-primary ring-1 ring-primary bg-primary/10",
                    else: "border-base-300 hover:border-base-content/30"
                  )
                ]}
              >
                <span class={brand_color(agent.kind)}>
                  <.agent_icon kind={agent.kind} class="size-4" />
                </span>
                <span class="text-xs">{agent.name}</span>
              </button>
            </div>

            <div class="flex items-center gap-3">
              <input type="hidden" name="issue[auto_merge]" value="false" />
              <label class="label cursor-pointer gap-2">
                <input
                  type="checkbox"
                  name="issue[auto_merge]"
                  value="true"
                  class="checkbox checkbox-sm"
                  checked={@form[:auto_merge].value == true or @form[:auto_merge].value == "true"}
                />
                <span class="label-text text-sm">Auto-merge</span>
              </label>
              <span class="text-base-content/20">|</span>
              <input type="hidden" name="issue[recurring]" value="false" />
              <label class="label cursor-pointer gap-2">
                <input
                  type="checkbox"
                  name="issue[recurring]"
                  value="true"
                  class="checkbox checkbox-sm"
                  checked={@form[:recurring].value == true or @form[:recurring].value == "true"}
                />
                <span class="label-text text-sm">Recurring</span>
              </label>
              <input
                :if={@form[:recurring].value == true or @form[:recurring].value == "true"}
                type="number"
                name="issue[recurrence_interval]"
                value={@form[:recurrence_interval].value || 24}
                min="1"
                max="365"
                class="input input-bordered input-sm w-20"
              />
              <select
                :if={@form[:recurring].value == true or @form[:recurring].value == "true"}
                name="issue[recurrence_unit]"
                class="select select-bordered select-sm w-28"
              >
                <option value="hours" selected={(@form[:recurrence_unit].value || "hours") == "hours"}>
                  hours
                </option>
                <option value="days" selected={@form[:recurrence_unit].value == "days"}>days</option>
                <option value="weeks" selected={@form[:recurrence_unit].value == "weeks"}>weeks</option>
              </select>
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-sm btn-ghost">Create</button>
              <button type="submit" name="dispatch" value="true" class="btn btn-sm btn-primary">
                Create & Dispatch
              </button>
              <button type="button" phx-click="cancel_form" class="btn btn-sm btn-ghost">
                Cancel
              </button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true

  def session_event(assigns) do
    badge_class =
      case assigns.event.type do
        "assistant" -> "badge-primary"
        "tool_use" -> "badge-info"
        "tool_result" -> "badge-info"
        "result" -> "badge-success"
        "error" -> "badge-error"
        "stderr" -> "badge-warning"
        _ -> "badge-ghost"
      end

    message =
      case assigns.event.message do
        nil -> ""
        msg when byte_size(msg) > 200 -> String.slice(msg, 0..197) <> "..."
        msg -> msg
      end

    assigns =
      assigns
      |> assign(:badge_class, badge_class)
      |> assign(:display_message, message)

    ~H"""
    <div class="flex items-start gap-1.5 leading-tight">
      <span class={"badge badge-xs #{@badge_class} flex-shrink-0 mt-0.5"}>{@event.type}</span>
      <span :if={@display_message != ""} class="text-base-content/70 break-all">
        {@display_message}
      </span>
    </div>
    """
  end

  defp body_without_title(nil), do: nil
  defp body_without_title(""), do: nil

  defp body_without_title(body) do
    result =
      String.replace(body, ~r/^#\s+.+\n*/, "", global: false)
      |> String.trim_leading("\n")
      |> String.trim()

    if result == "", do: nil, else: result
  end

  defp agent_display_name(msg) do
    kind = msg["agent_kind"]

    if kind && Agent.ephemeral_kind?(kind) do
      brand_label(kind)
    else
      msg["agent_name"] || "agent"
    end
  end

  @doc """
  Model picker trigger button. Shows the current model and opens the picker on click.

  - `truncate` — when true, shows only the last `/`-separated segment of the model ID
  - `show_hint` — when true and no agent can be picked, shows a help text
  """
  attr :agent_kind, :string, default: nil
  attr :selected_model, :string, default: nil
  attr :truncate, :boolean, default: false
  attr :show_hint, :boolean, default: false

  def model_trigger(assigns) do
    can_pick = assigns.agent_kind && Agent.adapter_module(assigns.agent_kind) != nil

    current_label =
      if assigns.selected_model && assigns.selected_model != "" do
        if assigns.truncate do
          assigns.selected_model |> String.split("/") |> List.last()
        else
          assigns.selected_model
        end
      else
        "model"
      end

    assigns = assign(assigns, can_pick: can_pick, current_label: current_label)

    ~H"""
    <input type="hidden" name="dispatch[model]" value={@selected_model || ""} />
    <%= if @can_pick do %>
      <button
        type="button"
        phx-click="model_picker_open"
        phx-value-kind={@agent_kind}
        class="flex items-center gap-1.5 text-xs text-base-content/60 hover:text-base-content transition-colors"
      >
        <span :if={@agent_kind} class={brand_color(@agent_kind)}>
          <.agent_icon kind={@agent_kind} class="size-3.5" />
        </span>
        {@current_label}
        <.icon name="hero-chevron-up-down" class="size-3" />
      </button>
    <% else %>
      <p :if={@show_hint} class="text-xs text-base-content/40">
        Prefix with @agent to target a specific agent (e.g. @claude)
      </p>
    <% end %>
    """
  end
end
