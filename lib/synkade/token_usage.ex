defmodule Synkade.TokenUsage do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Synkade.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "token_usage" do
    field :date, :date
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0

    timestamps()
  end

  def changeset(token_usage, attrs) do
    token_usage
    |> cast(attrs, [:date, :model, :input_tokens, :output_tokens])
    |> validate_required([:date, :model])
    |> unique_constraint([:date, :model])
  end

  @doc "Upsert today's token counts for a model (increment)."
  def record_usage(model, input_tokens, output_tokens)
      when is_binary(model) and is_integer(input_tokens) and is_integer(output_tokens) do
    today = Date.utc_today()

    Repo.insert(
      %__MODULE__{date: today, model: model, input_tokens: input_tokens, output_tokens: output_tokens},
      on_conflict: [inc: [input_tokens: input_tokens, output_tokens: output_tokens]],
      conflict_target: [:date, :model]
    )
  end

  def record_usage(_model, _input, _output), do: :ok

  @doc "Return daily usage for the last N days."
  def daily_usage(days \\ 30) do
    cutoff = Date.utc_today() |> Date.add(-(days - 1))

    from(t in __MODULE__,
      where: t.date >= ^cutoff,
      order_by: [asc: t.date, asc: t.model],
      select: %{date: t.date, model: t.model, input_tokens: t.input_tokens, output_tokens: t.output_tokens}
    )
    |> Repo.all()
  end
end
