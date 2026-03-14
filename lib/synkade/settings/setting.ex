defmodule Synkade.Settings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @valid_themes ~w(ops copper midnight phantom ember daylight paper)

  schema "settings" do
    # GitHub integration
    field :github_pat, Synkade.Encrypted.Binary
    field :github_webhook_secret, Synkade.Encrypted.Binary

    # Execution
    field :execution_backend, :string, default: "local"
    field :execution_sprites_token, Synkade.Encrypted.Binary
    field :execution_sprites_org, :string

    # Appearance
    field :theme, :string, default: "ops"

    timestamps()
  end

  def valid_themes, do: @valid_themes

  @github_fields ~w(github_pat github_webhook_secret)a
  @execution_fields ~w(execution_backend execution_sprites_token execution_sprites_org)a

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @github_fields ++ @execution_fields ++ [:theme])
    |> validate_required([:github_pat])
    |> validate_inclusion(:execution_backend, ["local", "sprites"])
    |> validate_inclusion(:theme, @valid_themes)
  end

  def theme_changeset(setting, attrs) do
    setting
    |> cast(attrs, [:theme])
    |> validate_inclusion(:theme, @valid_themes)
  end
end
