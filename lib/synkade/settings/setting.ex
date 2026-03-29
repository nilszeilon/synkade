defmodule Synkade.Settings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @valid_themes ~w(ops copper midnight phantom ember daylight paper)

  schema "settings" do
    belongs_to :user, Synkade.Accounts.User

    # GitHub integration
    field :github_pat, Synkade.Encrypted.Binary
    field :github_webhook_secret, Synkade.Encrypted.Binary

    # Execution
    field :execution_backend, :string, default: "local"
    field :execution_sprites_token, Synkade.Encrypted.Binary
    field :execution_sprites_org, :string

    # Appearance
    field :theme, :string, default: "ops"

    # Default agent
    belongs_to :default_agent, Synkade.Settings.Agent, type: :binary_id

    # Default model (global)
    field :default_model, :string

    timestamps()
  end

  def valid_themes, do: @valid_themes

  @github_fields ~w(github_pat)a
  @execution_fields ~w(execution_backend execution_sprites_token execution_sprites_org)a

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @github_fields ++ @execution_fields ++ [:theme, :user_id, :default_agent_id, :default_model])
    |> validate_required([:github_pat])
    |> validate_inclusion(:execution_backend, ["local", "sprites"])
    |> validate_inclusion(:theme, @valid_themes)
  end

  @doc "Changeset for updates that don't require re-submitting the PAT."
  def update_changeset(setting, attrs) do
    setting
    |> cast(attrs, @github_fields ++ @execution_fields ++ [:theme, :user_id, :default_agent_id])
    |> validate_inclusion(:execution_backend, ["local", "sprites"])
    |> validate_inclusion(:theme, @valid_themes)
  end

  def theme_changeset(setting, attrs) do
    setting
    |> cast(attrs, [:theme])
    |> validate_inclusion(:theme, @valid_themes)
  end
end
