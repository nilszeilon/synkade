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
    field :agent_id, :binary_id

    field :date, :date
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0

    timestamps()
  end

  def changeset(token_usage, attrs) do
    token_usage
    |> cast(attrs, [:date, :model, :input_tokens, :output_tokens, :user_id, :agent_id])
    |> validate_required([:date, :model])
  end

  @doc "Upsert today's token counts for a model + agent (increment)."
  def record_usage(user_id, model, input_tokens, output_tokens, agent_id \\ nil)

  def record_usage(user_id, model, input_tokens, output_tokens, agent_id)
      when is_integer(user_id) and is_binary(model) and is_integer(input_tokens) and
             is_integer(output_tokens) do
    today = Date.utc_today()

    Repo.insert(
      %__MODULE__{
        user_id: user_id,
        date: today,
        model: model,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        agent_id: agent_id
      },
      on_conflict:
        from(t in __MODULE__,
          update: [
            set: [
              input_tokens: fragment("? + ?", t.input_tokens, ^input_tokens),
              output_tokens: fragment("? + ?", t.output_tokens, ^output_tokens)
            ]
          ]
        ),
      conflict_target: {:unsafe_fragment, conflict_target_fragment(agent_id)}
    )
  end

  def record_usage(_user_id, _model, _input, _output, _agent_id), do: :ok

  defp conflict_target_fragment(nil) do
    "(user_id, date, model) WHERE agent_id IS NULL"
  end

  defp conflict_target_fragment(_agent_id) do
    "(user_id, date, model, agent_id) WHERE agent_id IS NOT NULL"
  end

  @doc "Sum total tokens for an agent in the given period (`:day` or `:week`)."
  def agent_period_usage(agent_id, period) when period in [:day, :week] do
    cutoff =
      case period do
        :day -> Date.utc_today()
        :week -> Date.utc_today() |> Date.add(-6)
      end

    from(t in __MODULE__,
      where: t.agent_id == ^agent_id and t.date >= ^cutoff,
      select: %{
        input_tokens: coalesce(sum(t.input_tokens), 0),
        output_tokens: coalesce(sum(t.output_tokens), 0)
      }
    )
    |> Repo.one()
    |> case do
      nil -> %{input_tokens: 0, output_tokens: 0}
      result -> result
    end
  end

  @doc "Check if an agent has exceeded its configured usage limit."
  def agent_over_limit?(agent) do
    case agent do
      %{usage_limit: nil} ->
        false

      %{usage_limit: limit, usage_limit_period: period_str}
      when is_integer(limit) and limit > 0 ->
        period = if period_str == "week", do: :week, else: :day
        usage = agent_period_usage(agent.id, period)
        usage.input_tokens + usage.output_tokens >= limit

      _ ->
        false
    end
  end

  @doc "Return daily usage for the last N days for a user."
  def daily_usage(user_id, days \\ 30) do
    cutoff = Date.utc_today() |> Date.add(-(days - 1))

    from(t in __MODULE__,
      where: t.user_id == ^user_id and t.date >= ^cutoff,
      order_by: [asc: t.date, asc: t.model],
      select: %{
        date: t.date,
        model: t.model,
        input_tokens: t.input_tokens,
        output_tokens: t.output_tokens
      }
    )
    |> Repo.all()
  end
end
