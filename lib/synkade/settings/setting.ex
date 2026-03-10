defmodule Synkade.Settings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "settings" do
    # GitHub integration
    field :github_pat, Synkade.Encrypted.Binary
    field :github_webhook_secret, Synkade.Encrypted.Binary
    # Agent config
    field :agent_kind, :string, default: "claude"
    field :agent_auth_mode, :string, default: "api_key"
    field :agent_api_key, Synkade.Encrypted.Binary
    field :agent_oauth_token, Synkade.Encrypted.Binary
    field :agent_model, :string
    field :agent_max_turns, :integer
    field :agent_allowed_tools, {:array, :string}, default: []
    field :agent_max_concurrent, :integer

    # Execution
    field :execution_backend, :string, default: "local"
    field :execution_sprites_token, Synkade.Encrypted.Binary
    field :execution_sprites_org, :string

    # Prompt template
    field :prompt_template, :string

    timestamps()
  end

  @github_fields ~w(github_pat github_webhook_secret)a

  @agent_fields ~w(agent_kind agent_auth_mode agent_api_key agent_oauth_token
    agent_model agent_max_turns agent_allowed_tools agent_max_concurrent prompt_template)a

  @execution_fields ~w(execution_backend execution_sprites_token execution_sprites_org)a

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @github_fields ++ @agent_fields ++ @execution_fields)
    |> validate_required([:github_pat])
    |> validate_inclusion(:agent_kind, ["claude", "codex"])
    |> validate_inclusion(:agent_auth_mode, ["api_key", "oauth"])
    |> validate_inclusion(:execution_backend, ["local", "sprites"])
    |> validate_number(:agent_max_turns, greater_than: 0)
    |> validate_number(:agent_max_concurrent, greater_than: 0)
    |> validate_agent_auth()
  end

  defp validate_agent_auth(changeset) do
    case get_field(changeset, :agent_auth_mode) do
      "oauth" ->
        validate_required(changeset, [:agent_oauth_token],
          message: "is required for OAuth auth mode"
        )

      _ ->
        changeset
    end
  end
end
