defmodule Synkade.Settings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "settings" do
    # GitHub integration
    field :github_auth_mode, :string, default: "pat"
    field :github_pat, Synkade.Encrypted.Binary
    field :github_app_id, :string
    field :github_private_key, Synkade.Encrypted.Binary
    field :github_webhook_secret, Synkade.Encrypted.Binary
    field :github_installation_id, :string
    field :github_endpoint, :string
    field :github_repo, :string
    field :tracker_labels, {:array, :string}, default: []

    # Agent config
    field :agent_kind, :string, default: "claude"
    field :agent_api_key, Synkade.Encrypted.Binary
    field :agent_model, :string
    field :agent_max_turns, :integer
    field :agent_allowed_tools, {:array, :string}, default: []
    field :agent_max_concurrent, :integer

    # Prompt template
    field :prompt_template, :string

    timestamps()
  end

  @github_fields ~w(github_auth_mode github_pat github_app_id github_private_key
    github_webhook_secret github_installation_id github_endpoint github_repo tracker_labels)a

  @agent_fields ~w(agent_kind agent_api_key agent_model agent_max_turns
    agent_allowed_tools agent_max_concurrent prompt_template)a

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @github_fields ++ @agent_fields)
    |> validate_inclusion(:github_auth_mode, ["pat", "app"])
    |> validate_inclusion(:agent_kind, ["claude", "codex"])
    |> validate_number(:agent_max_turns, greater_than: 0)
    |> validate_number(:agent_max_concurrent, greater_than: 0)
    |> validate_auth_mode()
  end

  defp validate_auth_mode(changeset) do
    case get_field(changeset, :github_auth_mode) do
      "pat" ->
        changeset
        |> validate_required([:github_pat, :github_repo],
          message: "is required for PAT auth mode"
        )

      "app" ->
        changeset
        |> validate_required([:github_app_id, :github_private_key],
          message: "is required for App auth mode"
        )

      _ ->
        changeset
    end
  end
end
