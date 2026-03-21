defmodule Synkade.Settings.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @pull_kinds ~w(hermes openclaw)

  schema "agents" do
    field :name, :string
    field :kind, :string, default: "claude"
    field :auth_mode, :string, default: "api_key"
    field :api_key, Synkade.Encrypted.Binary
    field :oauth_token, Synkade.Encrypted.Binary
    field :model, :string
    field :max_turns, :integer
    field :allowed_tools, {:array, :string}, default: []
    field :system_prompt, :string
    field :api_token_hash, :string
    field :api_token, Synkade.Encrypted.Binary

    timestamps()
  end

  @fields ~w(name kind auth_mode api_key oauth_token model max_turns allowed_tools system_prompt)a

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @fields)
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> validate_inclusion(:kind, ~w(claude codex opencode hermes openclaw))
    |> validate_inclusion(:auth_mode, ["api_key", "oauth"])
    |> validate_number(:max_turns, greater_than: 0)
  end

  def pull_kind?(kind), do: kind in @pull_kinds
end
