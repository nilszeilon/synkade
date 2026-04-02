defmodule SynkadeWeb.Components.Ide.ChatView do
  @moduledoc """
  Components for rendering agent session events in the IDE chat view.
  """
  use Phoenix.Component

  import SynkadeWeb.Components.AgentBrand

  alias Synkade.Agent.EventParser

  @text_truncate_lines 3

  # --- Public helpers ---

  def md(text) when is_binary(text) do
    case MDEx.to_html(text, sanitize: MDEx.Document.default_sanitize_options()) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end

  def md(_), do: ""

  def extract_session_id(events) do
    Enum.find_value(events, fn e -> e.session_id end)
  end

  def drop_trailing_agent_messages(messages) do
    messages
    |> Enum.reverse()
    |> Enum.drop_while(&(&1["type"] == "agent"))
    |> Enum.reverse()
  end

  def truncate_output(nil, _), do: ""

  def truncate_output(text, max) when is_binary(text) do
    if String.length(text) > max do
      String.slice(text, 0, max) <> "\n... (truncated)"
    else
      text
    end
  end

  def truncate_output(other, _), do: inspect(other)

  # --- Components ---

  attr :group, :map, required: true
  attr :running_entry, :any, default: nil
  attr :session_id, :string, default: nil

  def chat_event_group(assigns) do
    ~H"""
    <%= case @group.type do %>
      <% :step -> %>
        <.step_group step={@group} />
      <% :text -> %>
        <div class="max-w-[90%]">
          <div :if={@group.first_in_turn} class="flex items-center gap-1.5 mb-1">
            <span :if={@running_entry && @running_entry[:agent_kind]} class={brand_color(@running_entry[:agent_kind])}>
              <.agent_icon kind={@running_entry[:agent_kind]} class="size-3.5" />
            </span>
            <span class="text-xs text-base-content/40 font-medium">
              {if @running_entry, do: @running_entry[:agent_name] || "agent", else: "agent"}
            </span>
            <code :if={@session_id} class="text-[10px] text-base-content/20 font-mono ml-auto">
              {String.slice(@session_id, 0..7)}
            </code>
          </div>
          <.text_block text={@group.text} />
        </div>
      <% :result -> %>
        <div class="max-w-[90%]">
          <.text_block text={@group.text} />
        </div>
      <% :error -> %>
        <div class="text-sm text-error font-mono bg-error/5 rounded-lg px-3 py-2">{@group.text}</div>
      <% :system -> %>
        <div class="text-xs text-base-content/30 font-mono bg-base-200/30 rounded px-2 py-1">
          <span class="text-base-content/20">[system]</span> {@group.text}
        </div>
      <% _ -> %>
        <div class="text-xs text-base-content/30">{@group.type}</div>
    <% end %>
    """
  end

  attr :step, :map, required: true

  def step_group(assigns) do
    running = Enum.filter(assigns.step.tools, &(&1.status == :running))

    tool_summary =
      if assigns.step.tools != [] do
        assigns.step.tools
        |> Enum.map(& &1.name)
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_, count} -> -count end)
        |> Enum.map(fn
          {name, 1} -> EventParser.display_name(%{name: name, detail: nil})
          {name, n} -> "#{EventParser.display_name(%{name: name, detail: nil})} ×#{n}"
        end)
        |> Enum.join(", ")
      end

    tool_count = length(assigns.step.tools)

    assigns =
      assigns
      |> assign(:running, running)
      |> assign(:tool_summary, tool_summary)
      |> assign(:tool_count, tool_count)

    ~H"""
    <details class="group">
      <summary class="cursor-pointer select-none flex items-center gap-2 py-0.5 text-sm list-none [&::-webkit-details-marker]:hidden">
        <span class="text-[10px] text-base-content/30 group-open:rotate-90 transition-transform inline-block">&#9654;</span>
        <span class="text-base-content/40 text-xs font-medium">Step {@step.number}</span>
        <span :if={@tool_count > 0} class="text-base-content/50 flex-shrink-0">{"\u{1F527}"}</span>
        <span :if={@tool_count > 0} class="text-xs text-base-content/40 truncate">
          {if @tool_count == 1, do: "1 tool", else: "#{@tool_count} tools"}
          <span :if={@tool_summary} class="text-base-content/30">&middot; {@tool_summary}</span>
        </span>
        <span
          :if={@running != []}
          id={"step-timer-#{System.unique_integer([:positive])}"}
          phx-hook="ToolTimer"
          class="ml-auto flex items-center gap-1.5 text-xs text-base-content/30"
        >
          <span class="loading loading-dots loading-xs"></span>
          <span data-timer>0.0s</span>
        </span>
      </summary>
      <div class="ml-4 mt-1 space-y-1 border-l border-base-300 pl-3">
        <details :for={thought <- @step.thinking} class="group/think text-sm">
          <summary class="cursor-pointer select-none list-none [&::-webkit-details-marker]:hidden flex items-center gap-2 py-0.5 text-base-content/40 hover:text-base-content/60">
            <span class="text-[10px] group-open/think:rotate-90 transition-transform inline-block">&#9654;</span>
            <span class="text-base-content/30">Thinking</span>
            <span class="text-xs text-base-content/20">{String.length(thought)} chars</span>
          </summary>
          <div class="ml-5 mt-1 pl-3 border-l border-base-300/50 text-base-content/50 text-xs font-mono whitespace-pre-wrap max-h-40 overflow-y-auto">
            {thought}
          </div>
        </details>
        <.tool_card :for={tool <- @step.tools} tool={tool} />
      </div>
    </details>
    """
  end

  attr :tool, :map, required: true

  def tool_card(assigns) do
    has_content =
      assigns.tool.status == :running ||
        (assigns.tool.input_preview && !assigns.tool[:edit_old]) ||
        assigns.tool[:edit_old] ||
        (assigns.tool.status == :done && assigns.tool.output)

    assigns = assign(assigns, :has_content, has_content)

    ~H"""
    <details :if={@has_content} class="group/card text-sm">
      <summary class="cursor-pointer select-none list-none [&::-webkit-details-marker]:hidden flex items-center gap-2 py-0.5 hover:bg-base-200/50 rounded -mx-1 px-1">
        <span class="text-[10px] text-base-content/25 group-open/card:rotate-90 transition-transform inline-block flex-shrink-0">&#9654;</span>
        <span class="text-base-content/50 flex-shrink-0">{EventParser.icon(@tool.name)}</span>
        <span class="font-medium text-base-content/80">{EventParser.display_name(@tool)}</span>
        <.tool_card_badges tool={@tool} />
        <span
          :if={@tool.status == :running}
          id={"tool-timer-#{System.unique_integer([:positive])}"}
          phx-hook="ToolTimer"
          class="ml-auto flex items-center gap-1.5 text-xs text-base-content/30"
        >
          <span class="loading loading-dots loading-xs"></span>
          <span data-timer>0.0s</span>
        </span>
      </summary>
      <div class="ml-5 mt-0.5 pl-3 border-l border-base-300 space-y-1">
        <%!-- Bash command preview --%>
        <pre :if={@tool.input_preview && !@tool[:edit_old]} class="font-mono text-xs text-base-content/40 whitespace-pre-wrap break-all max-h-32 overflow-y-auto">{@tool.input_preview}</pre>
        <%!-- Edit diff view --%>
        <div :if={@tool[:edit_old]} class="font-mono text-[11px] whitespace-pre-wrap break-all max-h-64 overflow-y-auto">
          <div :for={line <- String.split(@tool.edit_old, "\n")} class="text-error/60">- {line}</div>
          <div :for={line <- String.split(@tool.edit_new, "\n")} class="text-success/60">+ {line}</div>
        </div>
        <%!-- Output --%>
        <pre :if={@tool.status == :done && @tool.output && !@tool[:edit_old]} class="font-mono text-[11px] text-base-content/30 whitespace-pre-wrap break-all max-h-48 overflow-y-auto">{truncate_output(@tool.output, 2000)}</pre>
      </div>
    </details>
    <%!-- Non-expandable card (no content to show) --%>
    <div :if={!@has_content} class="text-sm flex items-center gap-2 py-0.5">
      <span class="text-base-content/50 flex-shrink-0">{EventParser.icon(@tool.name)}</span>
      <span class="font-medium text-base-content/80">{EventParser.display_name(@tool)}</span>
      <.tool_card_badges tool={@tool} />
    </div>
    """
  end

  attr :tool, :map, required: true

  defp tool_card_badges(assigns) do
    ~H"""
    <%!-- File badge --%>
    <span
      :if={@tool.file_name}
      class="inline-flex items-center gap-1 bg-base-300/70 rounded px-1.5 py-0.5 text-xs font-mono text-base-content/60"
    >
      <svg class="size-3 opacity-50" viewBox="0 0 16 16" fill="currentColor">
        <path d="M3.75 1.5a.25.25 0 00-.25.25v11.5c0 .138.112.25.25.25h8.5a.25.25 0 00.25-.25V4.664a.25.25 0 00-.073-.177l-2.914-2.914a.25.25 0 00-.177-.073H3.75z" />
      </svg>
      {@tool.file_name}
    </span>
    <%!-- Edit line counts --%>
    <span :if={@tool[:edit_additions]} class="text-xs text-success font-mono">+{@tool.edit_additions}</span>
    <span :if={@tool[:edit_deletions]} class="text-xs text-error font-mono">-{@tool.edit_deletions}</span>
    <%!-- Non-file detail --%>
    <span :if={!@tool.file_name && @tool.detail} class="font-mono text-xs text-base-content/40 truncate">
      {@tool.detail}
    </span>
    """
  end

  attr :text, :string, required: true

  def text_block(assigns) do
    lines = String.split(assigns.text, "\n")
    needs_truncation = length(lines) > @text_truncate_lines

    assigns =
      assigns
      |> assign(:needs_truncation, needs_truncation)
      |> assign(:preview, lines |> Enum.take(@text_truncate_lines) |> Enum.join("\n"))

    ~H"""
    <%= if @needs_truncation do %>
      <details class="group text-sm prose-chat">
        <summary class="list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none">
          <div class="group-open:hidden">{md(@preview)}<span class="text-base-content/30 text-xs ml-1 hover:text-base-content/50">show more</span></div>
          <div class="hidden group-open:block">{md(@text)}<span class="text-base-content/30 text-xs ml-1 hover:text-base-content/50">show less</span></div>
        </summary>
      </details>
    <% else %>
      <div class="text-sm prose-chat">{md(@text)}</div>
    <% end %>
    """
  end
end
