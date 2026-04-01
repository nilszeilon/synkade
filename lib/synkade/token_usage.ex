defmodule Synkade.TokenUsage do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Synkade.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "token_usage" do
    belongs_to :user, Synkade.Accounts.User

    field :date, :date
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0

    timestamps()
  end

  def changeset(token_usage, attrs) do
    token_usage
    |> cast(attrs, [:date, :model, :input_tokens, :output_tokens, :user_id])
    |> validate_required([:date, :model])
    |> unique_constraint([:user_id, :date, :model])
  end

  @doc "Upsert today's token counts for a model (increment)."
  def record_usage(user_id, model, input_tokens, output_tokens)
      when is_binary(user_id) and is_binary(model) and is_integer(input_tokens) and is_integer(output_tokens) do
    today = Date.utc_today()

    result =
      Repo.insert(
        %__MODULE__{user_id: user_id, date: today, model: model, input_tokens: input_tokens, output_tokens: output_tokens},
        on_conflict:
          from(t in __MODULE__,
            update: [
              set: [
                input_tokens: fragment("? + ?", t.input_tokens, ^input_tokens),
                output_tokens: fragment("? + ?", t.output_tokens, ^output_tokens)
              ]
            ]
          ),
        conflict_target: [:user_id, :date, :model]
      )

    Phoenix.PubSub.broadcast(Synkade.PubSub, "token_usage:#{user_id}", :token_usage_updated)
    result
  end

  def record_usage(_user_id, _model, _input, _output), do: :ok

  @doc "Return daily usage for the last N days for a user."
  def daily_usage(user_id, days \\ 30) do
    cutoff = Date.utc_today() |> Date.add(-(days - 1))

    from(t in __MODULE__,
      where: t.user_id == ^user_id and t.date >= ^cutoff,
      order_by: [asc: t.date, asc: t.model],
      select: %{date: t.date, model: t.model, input_tokens: t.input_tokens, output_tokens: t.output_tokens}
    )
    |> Repo.all()
  end
end
