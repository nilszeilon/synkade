defmodule SynkadeWeb.Components.Ide.DiffView do
  @moduledoc """
  Diff viewer and file list components for the IDE.
  """
  use Phoenix.Component

  # --- Helpers ---

  def diff_line_class(:add), do: "bg-success/10"
  def diff_line_class(:remove), do: "bg-error/10"
  def diff_line_class(:header), do: ""
  def diff_line_class(_), do: ""

  def diff_line_prefix(:add), do: "+"
  def diff_line_prefix(:remove), do: "-"
  def diff_line_prefix(_), do: " "

  def file_status_color("M"), do: "text-warning"
  def file_status_color("A"), do: "text-success"
  def file_status_color("D"), do: "text-error"
  def file_status_color("U"), do: "text-info"
  def file_status_color("?"), do: "text-info"
  def file_status_color(_), do: "text-base-content/50"

  def file_dir(path) do
    dir = Path.dirname(path)
    if dir == ".", do: "", else: dir <> "/"
  end

  # --- Components ---

  attr :file, :string, required: true
  attr :diff_lines, :list, required: true

  def diff_viewer(assigns) do
    ~H"""
    <div
      id={"diff-viewer-#{@file}"}
      class="font-mono text-xs"
      phx-hook="DiffComment"
    >
      <div
        :for={{line, idx} <- Enum.with_index(@diff_lines)}
        id={"diff-line-#{idx}"}
        class={["flex group", diff_line_class(line.type)]}
      >
        <%= if line.type == :header do %>
          <div class="px-3 py-1 text-base-content/40 bg-info/10 w-full">
            {line.text}
          </div>
        <% else %>
          <button
            class="w-8 text-right pr-1 text-base-content/20 hover:text-primary cursor-pointer select-none flex-shrink-0 diff-line-btn"
            data-file={@file}
            data-line={line.new_line || line.old_line}
          >
            {line.new_line || line.old_line}
          </button>
          <span class="w-5 text-center text-base-content/30 flex-shrink-0">
            {diff_line_prefix(line.type)}
          </span>
          <pre class="flex-1 whitespace-pre-wrap break-all px-1">{line.text}</pre>
        <% end %>
      </div>

      <div :if={@diff_lines == []} class="px-3 py-4 text-base-content/30 text-center">
        No diff available
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :selected, :boolean, default: false

  def file_list_entry(assigns) do
    ~H"""
    <div
      phx-click="select_file"
      phx-value-file={@entry.file}
      class={[
        "flex items-center gap-2 px-4 py-1.5 cursor-pointer transition-colors",
        if(@selected,
          do: "bg-base-200",
          else: "hover:bg-base-200/50"
        )
      ]}
    >
      <span class="flex-1 min-w-0 text-sm font-mono truncate">
        <span class="text-base-content/40">{file_dir(@entry.file)}</span><span class="font-semibold">{Path.basename(@entry.file)}</span>
      </span>
      <span class={["text-xs font-mono flex-shrink-0", file_status_color(@entry.status)]}>
        {@entry.status}
      </span>
      <span :if={@entry.additions > 0} class="text-xs font-mono text-success flex-shrink-0">
        +{@entry.additions}
      </span>
      <span :if={@entry.deletions > 0} class="text-xs font-mono text-error flex-shrink-0">
        -{@entry.deletions}
      </span>
    </div>
    """
  end
end
