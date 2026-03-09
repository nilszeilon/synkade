defmodule Synkade.Settings.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "projects" do
    field :name, :string
    field :enabled, :boolean, default: true

    # Tracker
    field :tracker_kind, :string
    field :tracker_endpoint, :string
    field :tracker_repo, :string
    field :tracker_api_key, Synkade.Encrypted.Binary
    field :tracker_labels, {:array, :string}
    field :tracker_app_id, :string
    field :tracker_private_key, Synkade.Encrypted.Binary
    field :tracker_webhook_secret, Synkade.Encrypted.Binary
    field :tracker_installation_id, :string

    # Agent
    field :agent_kind, :string
    field :agent_auth_mode, :string
    field :agent_api_key, Synkade.Encrypted.Binary
    field :agent_oauth_token, Synkade.Encrypted.Binary
    field :agent_model, :string
    field :agent_max_turns, :integer
    field :agent_allowed_tools, {:array, :string}
    field :agent_max_concurrent, :integer

    # Execution
    field :execution_backend, :string
    field :execution_sprites_token, Synkade.Encrypted.Binary
    field :execution_sprites_org, :string

    # Prompt
    field :prompt_template, :string

    timestamps()
  end

  @required_fields ~w(name)a

  @optional_fields ~w(enabled
    tracker_kind tracker_endpoint tracker_repo tracker_api_key tracker_labels
    tracker_app_id tracker_private_key tracker_webhook_secret tracker_installation_id
    agent_kind agent_auth_mode agent_api_key agent_oauth_token
    agent_model agent_max_turns agent_allowed_tools agent_max_concurrent
    execution_backend execution_sprites_token execution_sprites_org
    prompt_template)a

  def changeset(project, attrs) do
    project
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
    |> validate_inclusion(:tracker_kind, ["github", "linear"])
    |> validate_inclusion(:agent_kind, ["claude", "codex"])
    |> validate_inclusion(:agent_auth_mode, ["api_key", "oauth"])
    |> validate_inclusion(:execution_backend, ["local", "sprites"])
    |> validate_number(:agent_max_turns, greater_than: 0)
    |> validate_number(:agent_max_concurrent, greater_than: 0)
  end
end
