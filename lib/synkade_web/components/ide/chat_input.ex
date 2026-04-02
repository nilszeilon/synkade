defmodule SynkadeWeb.Components.Ide.ChatInput do
  @moduledoc """
  Chat input component for the IDE — textarea, agent picker, file uploads.
  """
  use Phoenix.Component

  import SynkadeWeb.CoreComponents
  import SynkadeWeb.Components.AgentBrand
  import SynkadeWeb.Components.IssueView, only: [model_trigger: 1]
  import SynkadeWeb.Components.SearchPicker

  attr :dispatch_form, :any, required: true
  attr :uploads, :any, required: true
  attr :attachments, :list, default: []
  attr :agents, :list, default: []
  attr :selected_dispatch_agent_id, :string, default: nil
  attr :selected_model, :string, default: nil
  attr :model_picker, :map, required: true
  attr :agent_kind, :string, default: nil

  def chat_input(assigns) do
    ~H"""
    <div class="p-3 flex-shrink-0">
      <.form for={@dispatch_form} phx-submit="dispatch_issue" phx-change="validate_upload" multipart>
        <div
          id="ide-input-box"
          class="rounded-xl border border-base-300 bg-base-300 relative overflow-hidden"
          phx-hook="DropZone"
          phx-drop-target={@uploads.images.ref}
        >
          <%!-- Drop overlay --%>
          <div
            data-drop-overlay
            class="hidden absolute inset-0 z-30 bg-primary/10 border-2 border-dashed border-primary/40 rounded-xl flex flex-col items-center justify-center backdrop-blur-sm"
          >
            <.icon name="hero-arrow-up-tray" class="size-8 text-primary/60 mb-1" />
            <span class="text-sm font-medium text-base-content/70">Drop files here</span>
            <span class="text-xs text-base-content/40">Any file type</span>
          </div>

          <%!-- Attachment cards --%>
          <div
            :if={@attachments != [] or @uploads.images.entries != []}
            class="flex flex-wrap gap-2 px-3 pt-3"
          >
            <div
              :for={att <- @attachments}
              class="flex items-center gap-2 bg-base-300/60 rounded-lg px-2.5 py-1.5 text-xs"
            >
              <.icon name="hero-chat-bubble-left" class="size-3.5 text-base-content/40" />
              <span class="font-mono font-semibold">{Path.basename(att.file)}:{att.line}</span>
              <span class="text-base-content/50 truncate max-w-32">{att.text}</span>
              <button
                type="button"
                phx-click="remove_attachment"
                phx-value-id={att.id}
                class="text-base-content/30 hover:text-error"
              >
                <.icon name="hero-x-mark" class="size-3.5" />
              </button>
            </div>

            <div
              :for={entry <- @uploads.images.entries}
              class="flex items-center gap-2 bg-base-300/60 rounded-lg px-2.5 py-1.5 text-xs"
            >
              <.live_img_preview entry={entry} class="size-8 rounded object-cover" />
              <span class="font-mono truncate max-w-24">{entry.client_name}</span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="text-base-content/30 hover:text-error"
              >
                <.icon name="hero-x-mark" class="size-3.5" />
              </button>
            </div>
          </div>

          <%!-- Textarea --%>
          <textarea
            id="ide-message-input"
            name="dispatch[message]"
            placeholder="Message..."
            class="w-full bg-transparent border-0 focus:ring-0 focus:outline-none resize-none px-3 pt-3 pb-2 text-sm min-h-[60px] max-h-[200px]"
            rows="2"
            phx-debounce="300"
            phx-hook="SubmitOnEnter"
          ><%= @dispatch_form[:message].value %></textarea>

          <%!-- Agent selector + hidden field --%>
          <input type="hidden" name="dispatch[agent_id]" value={@selected_dispatch_agent_id || ""} />

          <%!-- Bottom toolbar --%>
          <div class="flex items-center justify-between px-3 pb-2.5">
            <div class="flex items-center gap-1.5">
              <button
                :for={agent <- @agents}
                type="button"
                phx-click="select_dispatch_agent"
                phx-value-id={agent.id}
                class={[
                  "flex items-center gap-1 px-2 py-1 rounded-md border text-xs transition-all cursor-pointer",
                  if(@selected_dispatch_agent_id == agent.id,
                    do: "border-primary bg-primary/10",
                    else: "border-transparent hover:border-base-content/20"
                  )
                ]}
                title={agent.name}
              >
                <span class={brand_color(agent.kind)}>
                  <.agent_icon kind={agent.kind} class="size-3.5" />
                </span>
                <span class="text-base-content/60">{agent.name}</span>
              </button>
              <span class="text-base-content/10 mx-0.5">|</span>
              <.model_trigger
                agent_kind={@agent_kind}
                selected_model={@selected_model}
                truncate
              />
            </div>
            <div class="flex items-center gap-1.5">
              <label class="btn btn-ghost btn-sm btn-square cursor-pointer" title="Attach files">
                <.icon name="hero-plus" class="size-4" />
                <.live_file_input upload={@uploads.images} class="hidden" />
              </label>
              <button
                type="submit"
                class="btn btn-ghost btn-sm btn-square"
                title="Send"
              >
                <.icon name="hero-arrow-up-circle-solid" class="size-6" />
              </button>
            </div>
          </div>
        </div>
      </.form>
      <.search_picker
        name="model_picker"
        state={@model_picker}
        placeholder="Search models..."
        empty_message="No models available"
      />
    </div>
    """
  end
end
