defmodule SynkadeWeb.Components.TokenChart do
  @moduledoc """
  SVG token usage chart component.

  Renders a mirrored bar chart showing daily input/output token usage
  over the last 30 days, with per-model color coding.
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
        TokenUsage.daily_usage(user_id, 30)
      catch
        kind, reason ->
          Logger.warning("Failed to load token usage data: #{kind} #{inspect(reason)}")
          []
      end

    today = Date.utc_today()
    dates = for i <- 29..0//-1, do: Date.add(today, -i)

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
    y_max = max(max_val, 1000)

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
    chart_w = 900
    chart_h = 400
    pad_left = 70
    pad_right = 20
    pad_top = 20
    pad_bottom = 60
    plot_w = chart_w - pad_left - pad_right
    plot_h = chart_h - pad_top - pad_bottom

    num_days = length(assigns.dates)
    bar_width = if num_days > 0, do: plot_w / num_days * 0.7, else: 10
    gap = if num_days > 0, do: plot_w / num_days, else: 10
    zero_y = pad_top + plot_h / 2
    y_max = assigns.y_max
    half_h = plot_h / 2
    colors = @model_colors

    bars =
      assigns.days
      |> Enum.with_index()
      |> Enum.flat_map(fn {day, i} ->
        x = pad_left + i * gap + (gap - bar_width) / 2

        {output_bars, _} =
          Enum.reduce(day.models, {[], 0}, fn m, {acc, offset} ->
            if m.output > 0 do
              h = m.output / y_max * half_h
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
              h = m.input / y_max * half_h
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
                opacity: "0.6"
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
      |> Enum.filter(fn {_d, i} -> rem(i, 5) == 0 or i == num_days - 1 end)
      |> Enum.map(fn {date, i} ->
        x = pad_left + i * gap + gap / 2
        %{x: x, label: Calendar.strftime(date, "%b %d")}
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
      |> assign(:pad_left, pad_left)
      |> assign(:pad_right, pad_right)
      |> assign(:plot_w, plot_w)
      |> assign(:y_ticks, y_ticks)
      |> assign(:x_labels, x_labels)
      |> assign(:legend, legend)

    ~H"""
    <div class="overflow-x-auto">
      <svg
        viewBox={"0 0 #{@chart_w} #{@chart_h + 30}"}
        class="w-full max-w-4xl"
        style="min-height: 300px"
      >
        <line
          :for={tick <- @y_ticks}
          x1={@pad_left}
          y1={tick.y}
          x2={@pad_left + @plot_w}
          y2={tick.y}
          stroke="currentColor"
          stroke-opacity="0.1"
          stroke-dasharray="4,4"
        />
        <line
          x1={@pad_left}
          y1={@zero_y}
          x2={@pad_left + @plot_w}
          y2={@zero_y}
          stroke="currentColor"
          stroke-opacity="0.3"
          stroke-width="1"
        />
        <text
          :for={tick <- @y_ticks}
          x={@pad_left - 8}
          y={tick.y + 4}
          text-anchor="end"
          class="fill-base-content/50"
          font-size="11"
        >
          {tick.label}
        </text>
        <rect
          :for={bar <- @bars}
          x={bar.x}
          y={bar.y}
          width={bar.w}
          height={max(bar.h, 0)}
          fill={bar.color}
          opacity={Map.get(bar, :opacity, "1")}
          rx="2"
        >
          <title>{bar.title}</title>
        </rect>
        <text
          :for={lbl <- @x_labels}
          x={lbl.x}
          y={@chart_h - 5}
          text-anchor="middle"
          class="fill-base-content/50"
          font-size="11"
          transform={"rotate(-30, #{lbl.x}, #{@chart_h - 5})"}
        >
          {lbl.label}
        </text>
        <text
          x={@pad_left - 8}
          y={@zero_y - 10}
          text-anchor="end"
          class="fill-base-content/40"
          font-size="10"
        >
          Output
        </text>
        <text
          x={@pad_left - 8}
          y={@zero_y + 16}
          text-anchor="end"
          class="fill-base-content/40"
          font-size="10"
        >
          Input
        </text>
      </svg>
      <div :if={@legend != []} class="flex flex-wrap gap-4 mt-2 ml-16">
        <div :for={item <- @legend} class="flex items-center gap-1.5 text-sm">
          <span class="inline-block w-3 h-3 rounded-sm" style={"background:#{item.color}"}></span>
          <span class="text-base-content/70">{item.model}</span>
          <span class="text-base-content/30 text-xs">(solid=output, faded=input)</span>
        </div>
      </div>
      <p :if={@legend == []} class="text-base-content/40 text-sm text-center py-8">
        No token usage data yet. Data will appear here as agents run.
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

  defp build_y_ticks(y_max, zero_y, half_h) do
    step = nice_step(y_max)
    above = for i <- 1..4, i * step <= y_max * 1.1, do: i * step
    below = Enum.map(above, &(-&1))

    above_ticks =
      Enum.map(above, fn val ->
        y = zero_y - val / y_max * half_h
        %{y: y, label: format_number(val)}
      end)

    below_ticks =
      Enum.map(below, fn val ->
        y = zero_y - val / y_max * half_h
        %{y: y, label: format_number(abs(val))}
      end)

    [%{y: zero_y, label: "0"} | above_ticks ++ below_ticks]
  end

  defp nice_step(max_val) when max_val <= 0, do: 1000

  defp nice_step(max_val) do
    raw = max_val / 4
    mag = :math.pow(10, floor(:math.log10(raw)))
    normalized = raw / mag

    step =
      cond do
        normalized <= 1.5 -> 1
        normalized <= 3.5 -> 2.5
        normalized <= 7.5 -> 5
        true -> 10
      end

    trunc(step * mag)
  end
end
