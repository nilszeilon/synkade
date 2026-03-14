defmodule SynkadeWeb.Components.IssueView do
  @moduledoc """
  Shared full-width issue view component used by IssuesLive and DashboardLive.
  """
  use Phoenix.Component

  import SynkadeWeb.CoreComponents
  alias Synkade.Issues.Issue

  attr :issue, :map, required: true
  attr :ancestors, :list, required: true
  attr :dispatch_form, :any, required: true
  attr :agents, :list, required: true
  attr :session_events, :list, default: []
  attr :session_id, :string, default: nil
  attr :running_entry, :any, default: nil
  attr :back_path, :string, required: true
  attr :back_label, :string, default: "Back"

  def issue_full_view(assigns) do
    messages = (assigns.issue.metadata || %{})["messages"] || []
    assigns = assign(assigns, :messages, messages)

    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-4">
        <.link patch={@back_path} class="btn btn-ghost btn-sm gap-1">
          <.icon name="hero-arrow-left" class="size-4" />
          {@back_label}
        </.link>
      </div>

      <div class="mb-4">
        <span class={"badge badge-sm #{state_badge_class(@issue.state)} mb-2"}>{@issue.state}</span>
        <h1 class="text-2xl font-bold">{Issue.title(@issue)}</h1>
      </div>

      <!-- Agent status bar -->
      <div
        :if={@running_entry}
        class="mb-4 px-4 py-3 bg-info/10 rounded-lg flex items-center gap-2"
      >
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
        <p :if={ancestor.body} class="text-sm text-base-content/60 whitespace-pre-wrap mt-1">{ancestor.body}</p>
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
        <p :if={body_without_title(@issue.body)} class="text-sm whitespace-pre-wrap">{body_without_title(@issue.body)}</p>
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
          <%= if msg["type"] == "dispatch" do %>
            <div class="border-l-2 border-info pl-4">
              <p class="text-xs text-base-content/50 font-semibold mb-1">
                #{idx}{if msg["agent_name"], do: " — #{msg["agent_name"]}", else: ""}
              </p>
              <p class="text-sm whitespace-pre-wrap">{msg["text"]}</p>
            </div>
          <% else %>
            <div class="border-l-2 border-success pl-4">
              <p class="text-xs text-base-content/50 font-semibold mb-1">
                #{idx} — {msg["agent_name"] || "agent"} output
              </p>
              <div class="collapse collapse-arrow bg-base-200 rounded">
                <input type="checkbox" />
                <div class="collapse-title text-xs py-2 min-h-0">
                  {msg["text"] |> String.slice(0..120) |> then(fn s -> if String.length(msg["text"] || "") > 120, do: s <> "...", else: s end)}
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
        :if={@issue.state == "in_progress" && (@session_events != [] || @session_id)}
        class="mb-4"
      >
        <div class="flex items-center justify-between mb-2">
          <p class="text-sm text-base-content/50 font-semibold">Agent Session</p>
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
        <div :if={@issue.state in ["backlog", "done", "awaiting_review", "cancelled"]} class="mb-3">
          <.form for={@dispatch_form} phx-submit="dispatch_issue">
            <div class="flex gap-2">
              <input
                type="text"
                name="dispatch[message]"
                value={@dispatch_form[:message].value}
                placeholder="@agent instructions..."
                class="input input-bordered input-sm flex-1"
                list="agent-names"
                autocomplete="off"
              />
              <button type="submit" class="btn btn-sm btn-primary">Go</button>
            </div>
            <datalist id="agent-names">
              <option :for={agent <- @agents} value={"@#{agent.name} "} />
            </datalist>
          </.form>
        </div>

        <div class="flex gap-2">
          <button
            :if={@issue.state == "queued"}
            phx-click="unqueue_issue"
            phx-value-id={@issue.id}
            class="btn btn-sm btn-ghost"
          >
            Backlog
          </button>
          <button
            :if={@issue.state not in ["done", "cancelled"]}
            phx-click="cancel_issue"
            phx-value-id={@issue.id}
            class="btn btn-sm btn-ghost"
          >
            Cancel
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

  defp state_badge_class("backlog"), do: "badge-ghost"
  defp state_badge_class("queued"), do: "badge-info"
  defp state_badge_class("in_progress"), do: "badge-warning"
  defp state_badge_class("awaiting_review"), do: "badge-secondary"
  defp state_badge_class("done"), do: "badge-success"
  defp state_badge_class("cancelled"), do: "badge-error"
  defp state_badge_class(_), do: "badge-ghost"

  defp format_relative_time(monotonic_ms) when is_integer(monotonic_ms) do
    elapsed_ms = System.monotonic_time(:millisecond) - monotonic_ms
    elapsed_s = div(elapsed_ms, 1000)

    cond do
      elapsed_s < 5 -> "just now"
      elapsed_s < 60 -> "#{elapsed_s}s ago"
      elapsed_s < 3600 -> "#{div(elapsed_s, 60)}m ago"
      true -> "#{div(elapsed_s, 3600)}h ago"
    end
  end

  defp format_relative_time(_), do: nil

  defp body_without_title(nil), do: nil
  defp body_without_title(""), do: nil

  defp body_without_title(body) do
    result = String.replace(body, ~r/^#\s+.+\n*/, "", global: false) |> String.trim_leading("\n") |> String.trim()
    if result == "", do: nil, else: result
  end
end
