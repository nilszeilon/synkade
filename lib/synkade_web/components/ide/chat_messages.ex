defmodule SynkadeWeb.Components.Ide.ChatMessages do
  @moduledoc """
  Chat message history rendering for the IDE — issue context, dispatch/system/agent messages,
  live session events, and turn summary.
  """
  use Phoenix.Component

  import SynkadeWeb.CoreComponents
  import SynkadeWeb.Components.AgentBrand
  import SynkadeWeb.Components.Ide.ChatView
  import SynkadeWeb.IssueLiveHelpers, only: [body_without_title: 1]

  alias Synkade.Agent.EventParser

  attr :issue, :map, default: nil
  attr :messages, :list, default: []
  attr :session_events, :list, default: []
  attr :session_id, :string, default: nil
  attr :running_entry, :any, default: nil
  attr :agent_kind, :string, default: nil
  attr :project, :map, default: nil
  attr :last_turn_files, :list, default: []
  attr :last_turn_duration, :integer, default: 0

  def chat_messages(assigns) do
    ~H"""
    <div
      id="chat-scroll"
      class="flex-1 overflow-y-auto px-4 py-4 space-y-4"
      phx-hook="AutoScroll"
    >
      <%!-- Draft mode hint --%>
      <div :if={is_nil(@issue) && @messages == []} class="flex flex-col items-center justify-center h-full text-base-content/30">
        <.icon name="hero-chat-bubble-left-right" class="size-8 mb-2" />
        <span class="text-sm">Send a message to start working on {@project.name}</span>
      </div>

      <%!-- Issue context --%>
      <div :if={@issue && body_without_title(@issue.body)} class="space-y-2 mb-2">
        <div :if={body_without_title(@issue.body)} class="flex justify-end">
          <div class="max-w-[85%] rounded-2xl rounded-br-sm bg-primary/10 px-4 py-2.5 text-sm prose-chat">
            {md(body_without_title(@issue.body))}
          </div>
        </div>
      </div>

      <%!-- Message history --%>
      <div :for={msg <- @messages} class="space-y-1">
        <%= cond do %>
          <% msg["type"] == "dispatch" -> %>
            <div class="flex justify-end">
              <div class="max-w-[85%] rounded-2xl rounded-br-sm bg-primary/10 px-4 py-2.5 text-sm prose-chat">
                {md(msg["text"])}
              </div>
            </div>
          <% msg["type"] == "system" -> %>
            <div class="flex justify-center">
              <span class="text-xs text-base-content/40 italic">{msg["text"]}</span>
            </div>
          <% true -> %>
            <div class="max-w-[90%]">
              <div class="flex items-center gap-1.5 mb-1">
                <span :if={msg["agent_kind"]} class={brand_color(msg["agent_kind"])}>
                  <.agent_icon kind={msg["agent_kind"]} class="size-3.5" />
                </span>
                <span class="text-xs text-base-content/40 font-medium">
                  {msg["agent_name"] || "agent"}
                </span>
              </div>
              <div class="text-sm prose-chat">{md(msg["text"])}</div>
            </div>
        <% end %>
      </div>

      <%!-- Live agent session --%>
      <div
        :if={@issue && (@session_events != [] || @running_entry)}
        class="space-y-3"
      >
        <.chat_event_group
          :for={group <- EventParser.group_events(@session_events, @agent_kind, @running_entry != nil)}
          group={group}
          running_entry={@running_entry}
          session_id={@session_id}
        />
        <div
          :if={@session_events == []}
          class="flex items-center gap-2 text-base-content/30 text-sm"
        >
          <span class="loading loading-dots loading-xs"></span>
          Thinking...
        </div>
      </div>

      <%!-- Turn summary --%>
      <div
        :if={@last_turn_files != [] && is_nil(@running_entry)}
        phx-click="toggle_turn_filter"
        class="flex items-center gap-2 flex-wrap text-xs text-base-content/50 bg-base-200/50 rounded-lg px-3 py-2 cursor-pointer hover:bg-base-200/80 transition-colors"
      >
        <span class="text-base-content/30">{format_duration(@last_turn_duration)}</span>
        <span
          :for={f <- @last_turn_files}
          class="inline-flex items-center gap-1 bg-base-300/70 rounded px-1.5 py-0.5 font-mono"
        >
          <svg class="size-3 opacity-40" viewBox="0 0 16 16" fill="currentColor">
            <path d="M3.75 1.5a.25.25 0 00-.25.25v11.5c0 .138.112.25.25.25h8.5a.25.25 0 00.25-.25V4.664a.25.25 0 00-.073-.177l-2.914-2.914a.25.25 0 00-.177-.073H3.75z" />
          </svg>
          {Path.basename(f.file)}
          <span :if={f.additions > 0} class="text-success">+{f.additions}</span>
          <span :if={f.deletions > 0} class="text-error">-{f.deletions}</span>
        </span>
      </div>
    </div>
    """
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    "#{m}m #{s}s"
  end
end
