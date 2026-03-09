defmodule Synkade.TokenUsage.Record do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "token_usage" do
    field :project_name, :string
    field :issue_id, :string
    field :issue_identifier, :string
    field :model, :string
    field :auth_mode, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :runtime_seconds, :float, default: 0.0

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :project_name,
      :issue_id,
      :issue_identifier,
      :model,
      :auth_mode,
      :input_tokens,
      :output_tokens,
      :runtime_seconds
    ])
    |> validate_required([:project_name, :issue_id, :auth_mode])
    |> validate_inclusion(:auth_mode, ["api_key", "oauth"])
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
  end
end
