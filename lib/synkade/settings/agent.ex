defmodule Synkade.Settings.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @ephemeral_kinds ~w(claude codex opencode)
  @pull_kinds ~w(hermes openclaw)

  schema "agents" do
    belongs_to :user, Synkade.Accounts.User

    field :name, :string
    field :kind, :string, default: "claude"
    field :auth_mode, :string, default: "api_key"
    field :api_key, Synkade.Encrypted.Binary
    field :oauth_token, Synkade.Encrypted.Binary
    field :api_token_hash, :string
    field :api_token, Synkade.Encrypted.Binary

    timestamps()
  end

  @fields ~w(name kind auth_mode api_key oauth_token user_id)a

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @fields)
    |> maybe_set_ephemeral_name()
    |> validate_required([:name])
    |> unique_constraint([:user_id, :name])
    |> validate_inclusion(:kind, @ephemeral_kinds ++ @pull_kinds)
    |> validate_inclusion(:auth_mode, ["api_key", "oauth"])
  end

  defp maybe_set_ephemeral_name(changeset) do
    kind = get_field(changeset, :kind) || "claude"

    if ephemeral_kind?(kind) do
      put_change(changeset, :name, kind)
    else
      changeset
    end
  end

  def ephemeral_kind?(kind), do: kind in @ephemeral_kinds
  def ephemeral_kinds, do: @ephemeral_kinds
  def pull_kind?(kind), do: kind in @pull_kinds
  def pull_kinds, do: @pull_kinds

  @kind_modules %{
    "claude" => Synkade.Agent.ClaudeCode,
    "codex" => Synkade.Agent.Codex,
    "opencode" => Synkade.Agent.OpenCode
  }

  @doc "Returns the adapter module for an agent kind."
  def adapter_module(kind), do: Map.get(@kind_modules, kind)

  @doc "Fetch available models from the provider API for the given agent kind and API key."
  def fetch_models(kind, api_key) do
    case adapter_module(kind) do
      nil -> {:ok, []}
      mod -> mod.fetch_models(api_key)
    end
  end

  @doc "Find the label for a model ID from a fetched model list."
  def model_label(model_id, models) when is_list(models) do
    case Enum.find(models, fn {_label, id} -> id == model_id end) do
      {label, _} -> label
      nil -> model_id
    end
  end

  def model_label(_model_id, _models), do: nil
end
