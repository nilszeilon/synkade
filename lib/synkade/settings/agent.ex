defmodule Synkade.Settings.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @kinds ~w(claude codex opencode hermes)

  schema "agents" do
    belongs_to :user, Synkade.Accounts.User

    field :name, :string
    field :kind, :string, default: "claude"
    field :auth_mode, :string, default: "api_key"
    field :api_key, Synkade.Encrypted.Binary
    field :oauth_token, Synkade.Encrypted.Binary
    field :api_token_hash, :string
    field :api_token, Synkade.Encrypted.Binary
    field :usage_limit, :integer
    field :usage_limit_period, :string, default: "day"

    timestamps()
  end

  @fields ~w(name kind auth_mode api_key oauth_token user_id usage_limit usage_limit_period)a

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @fields)
    |> maybe_set_name()
    |> validate_required([:name])
    |> unique_constraint([:user_id, :name])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:auth_mode, ["api_key", "oauth"])
    |> validate_inclusion(:usage_limit_period, ["day", "week"])
    |> validate_number(:usage_limit, greater_than: 0)
  end

  defp maybe_set_name(changeset) do
    kind = get_field(changeset, :kind) || "claude"
    put_change(changeset, :name, kind)
  end

  def kinds, do: @kinds

  @kind_modules %{
    "claude" => Synkade.Agent.ClaudeCode,
    "codex" => Synkade.Agent.Codex,
    "opencode" => Synkade.Agent.OpenCode,
    "hermes" => Synkade.Agent.Hermes
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
