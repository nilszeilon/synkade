defmodule SynkadeWeb.Components.AgentBrand do
  @moduledoc """
  Branding components for agent kinds — SVG icons, branded cards, and helpers.
  """
  use Phoenix.Component


  @brands %{
    "claude" => %{
      label: "Claude Code",
      desc: "Anthropic CLI agent",
      color: "text-warning"
    },
    "opencode" => %{
      label: "OpenCode",
      desc: "Multi-provider agent",
      color: "text-info"
    },
    "codex" => %{
      label: "Codex",
      desc: "OpenAI CLI agent",
      color: "text-success"
    },
    "hermes" => %{
      label: "Hermes",
      desc: "Nous Research CLI agent",
      color: "text-secondary"
    },
  }

  def brand_label(kind), do: (@brands[kind] || %{label: kind}).label
  def brand_color(kind), do: (@brands[kind] || %{color: "text-base-content"}).color
  def brands, do: @brands

  @doc "Renders the agent kind SVG icon inline. Inherits currentColor."
  attr :kind, :string, required: true
  attr :class, :string, default: "size-4"

  def agent_icon(assigns) do
    ~H"""
    <%= case @kind do %>
      <% "claude" -> %>
        <%!-- Anthropic Claude mark from paperclipai/paperclip --%>
        <svg class={@class} viewBox="0 0 16 16" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
          <path d="m3.127 10.604 3.135-1.76.053-.153-.053-.085H6.11l-.525-.032-1.791-.048-1.554-.065-1.505-.08-.38-.081L0 7.832l.036-.234.32-.214.455.04 1.009.069 1.513.105 1.097.064 1.626.17h.259l.036-.105-.089-.065-.068-.064-1.566-1.062-1.695-1.121-.887-.646-.48-.327-.243-.306-.104-.67.435-.48.585.04.15.04.593.456 1.267.981 1.654 1.218.242.202.097-.068.012-.049-.109-.181-.9-1.626-.96-1.655-.428-.686-.113-.411a2 2 0 0 1-.068-.484l.496-.674L4.446 0l.662.089.279.242.411.94.666 1.48 1.033 2.014.302.597.162.553.06.17h.105v-.097l.085-1.134.157-1.392.154-1.792.052-.504.25-.605.497-.327.387.186.319.456-.045.294-.19 1.23-.37 1.93-.243 1.29h.142l.161-.16.654-.868 1.097-1.372.484-.545.565-.601.363-.287h.686l.505.751-.226.775-.707.895-.585.759-.839 1.13-.524.904.048.072.125-.012 1.897-.403 1.024-.186 1.223-.21.553.258.06.263-.218.536-1.307.323-1.533.307-2.284.54-.028.02.032.04 1.029.098.44.024h1.077l2.005.15.525.346.315.424-.053.323-.807.411-3.631-.863-.872-.218h-.12v.073l.726.71 1.331 1.202 1.667 1.55.084.383-.214.302-.226-.032-1.464-1.101-.565-.497-1.28-1.077h-.084v.113l.295.432 1.557 2.34.08.718-.112.234-.404.141-.444-.08-.911-1.28-.94-1.44-.759-1.291-.093.053-.448 4.821-.21.246-.484.186-.403-.307-.214-.496.214-.98.258-1.28.21-1.016.19-1.263.112-.42-.008-.028-.092.012-.953 1.307-1.448 1.957-1.146 1.227-.274.109-.477-.247.045-.44.266-.39 1.586-2.018.956-1.25.617-.723-.004-.105h-.036l-4.212 2.736-.75.096-.324-.302.04-.496.154-.162 1.267-.871z" />
        </svg>
      <% "opencode" -> %>
        <%!-- OpenCode geometric mark --%>
        <svg class={@class} viewBox="0 0 32 40" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M24 32H8V16H24V32Z" fill="currentColor" opacity="0.4" />
          <path d="M24 8H8V32H24V8ZM32 40H0V0H32V40Z" fill="currentColor" />
        </svg>
      <% "codex" -> %>
        <%!-- OpenAI mark --%>
        <svg class={@class} viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
          <path d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z" />
        </svg>
      <% "hermes" -> %>
        <%!-- Hermes winged helmet mark --%>
        <svg class={@class} viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
          <path d="M12 2C8.13 2 5 5.13 5 9c0 1.74.63 3.33 1.67 4.56L3 18l2.5-1.5L7 18l1.5-1.5L10 18l2-2 2 2 1.5-1.5L17 18l1.5-1.5L21 18l-3.67-4.44A6.97 6.97 0 0 0 19 9c0-3.87-3.13-7-7-7zm0 2c2.76 0 5 2.24 5 5s-2.24 5-5 5-5-2.24-5-5 2.24-5 5-5z"/>
          <path d="M1 8c1.5-1 3-1.5 4-1.5M23 8c-1.5-1-3-1.5-4-1.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" fill="none"/>
          <circle cx="12" cy="9" r="2.5"/>
        </svg>
      <% _ -> %>
        <svg class={@class} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2" />
          <text x="12" y="16" text-anchor="middle" font-size="12" fill="currentColor">?</text>
        </svg>
    <% end %>
    """
  end

  @doc "Renders the agent wordmark (logo + name) where available. Falls back to icon."
  attr :kind, :string, required: true
  attr :class, :string, default: "h-6"

  def agent_wordmark(assigns) do
    ~H"""
    <%= case @kind do %>
      <% "opencode" -> %>
        <svg class={@class} viewBox="0 0 234 42" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M18 30H6V18H18V30Z" fill="currentColor" opacity="0.4" />
          <path d="M18 12H6V30H18V12ZM24 36H0V6H24V36Z" fill="currentColor" />
          <path d="M48 30H36V18H48V30Z" fill="currentColor" opacity="0.4" />
          <path d="M36 30H48V12H36V30ZM54 36H36V42H30V6H54V36Z" fill="currentColor" />
          <path d="M84 24V30H66V24H84Z" fill="currentColor" opacity="0.4" />
          <path d="M84 24H66V30H84V36H60V6H84V24ZM66 18H78V12H66V18Z" fill="currentColor" />
          <path d="M108 36H96V18H108V36Z" fill="currentColor" opacity="0.4" />
          <path d="M108 12H96V36H90V6H108V12ZM114 36H108V12H114V36Z" fill="currentColor" />
          <path d="M144 30H126V18H144V30Z" fill="currentColor" opacity="0.4" />
          <path d="M144 12H126V30H144V36H120V6H144V12Z" fill="currentColor" />
          <path d="M168 30H156V18H168V30Z" fill="currentColor" opacity="0.4" />
          <path d="M168 12H156V30H168V12ZM174 36H150V6H174V36Z" fill="currentColor" />
          <path d="M198 30H186V18H198V30Z" fill="currentColor" opacity="0.4" />
          <path d="M198 12H186V30H198V12ZM204 36H180V6H198V0H204V36Z" fill="currentColor" />
          <path d="M234 24V30H216V24H234Z" fill="currentColor" opacity="0.4" />
          <path d="M216 12V18H228V12H216ZM234 24H216V30H234V36H210V6H234V24Z" fill="currentColor" />
        </svg>
      <% _ -> %>
        <.agent_icon kind={@kind} class={@class} />
    <% end %>
    """
  end

  @doc "Renders a selectable branded card for agent kind picker."
  attr :kind, :string, required: true
  attr :selected, :boolean, default: false

  def agent_card(assigns) do
    brand = @brands[assigns.kind] || %{label: assigns.kind, desc: "", color: "text-base-content"}
    assigns = assign(assigns, :brand, brand)

    ~H"""
    <button
      type="button"
      phx-click="select_agent_kind"
      phx-value-kind={@kind}
      class={[
        "card bg-base-200 border p-4 text-left transition-all cursor-pointer",
        if(@selected,
          do: "border-primary ring-1 ring-primary",
          else: "border-base-300 hover:border-base-content/30"
        )
      ]}
    >
      <div class="flex flex-col items-center gap-2">
        <span class={@brand.color}>
          <.agent_wordmark kind={@kind} class="h-5" />
        </span>
        <p class="text-xs text-base-content/50">{@brand.desc}</p>
      </div>
    </button>
    """
  end
end
