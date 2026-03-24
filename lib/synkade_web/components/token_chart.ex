defmodule SynkadeWeb.Components.TokenChart do
  @moduledoc """
  SVG token usage chart component.

  Renders a mirrored bar chart showing daily input/output token usage
  over the last 7 days, with per-model color coding and logarithmic scale.
  Bloomberg-terminal aesthetic: edge-to-edge bars, overlaid labels, no chrome.
  """
  use Phoenix.Component

  alias Synkade.TokenUsage

  @model_colors ~w(#6366f1 #f59e0b #10b981 #ef4444 #8b5cf6 #ec4899 #14b8a6 #f97316)

  @doc """
  Prepares chart data assigns from TokenUsage daily aggregates.
  Call this in mount/handle_info to populate chart_days, chart_models, etc.
  """
  def assign_chart_data(socket) do
    require Logger

    user_id = socket.assigns.current_scope.user.id

    usage =
      try do
        TokenUsage.daily_usage(user_id, 7)
      catch
        kind, reason ->
          Logger.warning("Failed to load token usage data: #{kind} #{inspect(reason)}")
          []
      end

    today = Date.utc_today()
    dates = for i <- 6..0//-1, do: Date.add(today, -i)

    models =
      usage
      |> Enum.map(& &1.model)
      |> Enum.uniq()
      |> Enum.sort()

    usage_map =
      Map.new(usage, fn row -> {{row.date, row.model}, row} end)

    days =
      Enum.map(dates, fn date ->
        model_data =
          Enum.map(models, fn model ->
            row = Map.get(usage_map, {date, model}, %{input_tokens: 0, output_tokens: 0})
            %{model: model, input: row.input_tokens, output: row.output_tokens}
          end)

        total_input = Enum.sum(Enum.map(model_data, & &1.input))
        total_output = Enum.sum(Enum.map(model_data, & &1.output))

        %{date: date, models: model_data, total_input: total_input, total_output: total_output}
      end)

    max_output = days |> Enum.map(& &1.total_output) |> Enum.max(fn -> 0 end)
    max_input = days |> Enum.map(& &1.total_input) |> Enum.max(fn -> 0 end)
    max_val = max(max_output, max_input)
    y_max = max(log_scale(max_val), log_scale(1000))

    socket
    |> assign(:chart_days, days)
    |> assign(:chart_models, models)
    |> assign(:chart_y_max, y_max)
    |> assign(:chart_dates, dates)
  end

  # --- Component ---

  attr :days, :list, required: true
  attr :models, :list, required: true
  attr :y_max, :integer, required: true
  attr :dates, :list, required: true

  def token_chart(assigns) do
    chart_w = 600
    chart_h = 280
    # No outer padding — bars and grid go edge to edge
    plot_w = chart_w
    plot_h = chart_h

    num_days = length(assigns.dates)
    gap = if num_days > 0, do: plot_w / num_days, else: 10
    bar_width = gap - 2
    zero_y = plot_h / 2
    y_max = assigns.y_max
    half_h = plot_h / 2
    colors = @model_colors

    bars =
      assigns.days
      |> Enum.with_index()
      |> Enum.flat_map(fn {day, i} ->
        x = i * gap + 1

        {output_bars, _} =
          Enum.reduce(day.models, {[], 0}, fn m, {acc, offset} ->
            if m.output > 0 do
              h = log_scale(m.output) / y_max * half_h
              y = zero_y - offset - h
              color_idx = Enum.find_index(assigns.models, &(&1 == m.model)) || 0
              color = Enum.at(colors, rem(color_idx, length(colors)))

              bar = %{
                x: x,
                y: y,
                w: bar_width,
                h: h,
                color: color,
                title: "#{m.model} output: #{format_number(m.output)} on #{day.date}"
              }

              {[bar | acc], offset + h}
            else
              {acc, offset}
            end
          end)

        {input_bars, _} =
          Enum.reduce(day.models, {[], 0}, fn m, {acc, offset} ->
            if m.input > 0 do
              h = log_scale(m.input) / y_max * half_h
              y = zero_y + offset
              color_idx = Enum.find_index(assigns.models, &(&1 == m.model)) || 0
              color = Enum.at(colors, rem(color_idx, length(colors)))

              bar = %{
                x: x,
                y: y,
                w: bar_width,
                h: h,
                color: color,
                title: "#{m.model} input: #{format_number(m.input)} on #{day.date}",
                opacity: "0.5"
              }

              {[bar | acc], offset + h}
            else
              {acc, offset}
            end
          end)

        output_bars ++ input_bars
      end)

    y_ticks = build_y_ticks(y_max, zero_y, half_h)

    x_labels =
      assigns.dates
      |> Enum.with_index()
      |> Enum.map(fn {date, i} ->
        x = i * gap + gap / 2
        %{x: x, label: Calendar.strftime(date, "%a")}
      end)

    legend =
      assigns.models
      |> Enum.with_index()
      |> Enum.map(fn {model, i} ->
        color = Enum.at(colors, rem(i, length(colors)))
        %{model: model, color: color}
      end)

    assigns =
      assigns
      |> assign(:chart_w, chart_w)
      |> assign(:chart_h, chart_h)
      |> assign(:bars, bars)
      |> assign(:zero_y, zero_y)
      |> assign(:plot_w, plot_w)
      |> assign(:y_ticks, y_ticks)
      |> assign(:x_labels, x_labels)
      |> assign(:legend, legend)

    ~H"""
    <div>
      <svg viewBox={"0 0 #{@chart_w} #{@chart_h}"} class="w-full block" preserveAspectRatio="none">
        <%!-- Grid lines — subtle, edge to edge --%>
        <line
          :for={tick <- @y_ticks}
          x1="0"
          y1={tick.y}
          x2={@plot_w}
          y2={tick.y}
          stroke="currentColor"
          stroke-opacity="0.06"
        />
        <%!-- Center line --%>
        <line
          x1="0"
          y1={@zero_y}
          x2={@plot_w}
          y2={@zero_y}
          stroke="currentColor"
          stroke-opacity="0.15"
        />
        <%!-- Bars --%>
        <rect
          :for={bar <- @bars}
          x={bar.x}
          y={bar.y}
          width={bar.w}
          height={max(bar.h, 0)}
          fill={bar.color}
          opacity={Map.get(bar, :opacity, "0.85")}
        >
          <title>{bar.title}</title>
        </rect>
        <%!-- Y-axis tick labels — overlaid inside left edge --%>
        <text
          :for={tick <- Enum.reject(@y_ticks, &(&1.label == "0"))}
          x="4"
          y={tick.y - 3}
          class="fill-base-content/30"
          font-size="9"
          font-family="monospace"
        >
          {tick.label}
        </text>
        <%!-- X-axis day labels — overlaid at bottom of each bar column --%>
        <text
          :for={lbl <- @x_labels}
          x={lbl.x}
          y={@chart_h - 4}
          text-anchor="middle"
          class="fill-base-content/30"
          font-size="9"
          font-family="monospace"
        >
          {lbl.label}
        </text>
        <%!-- Output / Input labels at center line --%>
        <text x="4" y={@zero_y - 4} class="fill-base-content/20" font-size="8" font-family="monospace">
          OUT
        </text>
        <text x="4" y={@zero_y + 11} class="fill-base-content/20" font-size="8" font-family="monospace">
          IN
        </text>
      </svg>
      <%!-- Inline legend — compact, below chart with no gap --%>
      <div :if={@legend != []} class="flex flex-wrap gap-x-3 gap-y-1 mt-1">
        <div :for={item <- @legend} class="flex items-center gap-1">
          <span class="inline-block w-2 h-2 rounded-sm" style={"background:#{item.color}"}></span>
          <span class="text-base-content/40 text-[10px] font-mono">{item.model}</span>
        </div>
      </div>
      <p :if={@legend == []} class="text-base-content/30 text-xs text-center py-4 font-mono">
        No data yet
      </p>
    </div>
    """
  end

  # --- Formatting helpers ---

  def format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  def format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  def format_number(n) when is_number(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  def format_number(n) when is_number(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  def format_number(n), do: to_string(n)

  def format_duration(seconds) when is_float(seconds) do
    cond do
      seconds < 60 -> "#{trunc(seconds)}s"
      seconds < 3600 -> "#{trunc(seconds / 60)}m #{rem(trunc(seconds), 60)}s"
      true -> "#{trunc(seconds / 3600)}h #{rem(trunc(seconds / 60), 60)}m"
    end
  end

  def format_duration(_), do: "0s"

  # --- Private ---

  # log10(n + 1) so that 0 maps to 0, and values scale logarithmically
  defp log_scale(0), do: 0.0
  defp log_scale(n) when n > 0, do: :math.log10(n + 1)
  defp log_scale(n), do: -:math.log10(abs(n) + 1)

  # Build y-axis ticks at powers of 10 (1K, 10K, 100K, 1M, ...)
  defp build_y_ticks(y_max_log, zero_y, half_h) do
    powers = [1_000, 10_000, 100_000, 1_000_000, 10_000_000]

    above =
      powers
      |> Enum.filter(fn val -> log_scale(val) <= y_max_log * 1.05 end)

    above_ticks =
      Enum.map(above, fn val ->
        y = zero_y - log_scale(val) / y_max_log * half_h
        %{y: y, label: format_number(val)}
      end)

    below_ticks =
      Enum.map(above, fn val ->
        y = zero_y + log_scale(val) / y_max_log * half_h
        %{y: y, label: format_number(val)}
      end)

    [%{y: zero_y, label: "0"} | above_ticks ++ below_ticks]
  end
end
