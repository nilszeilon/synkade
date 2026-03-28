defmodule Synkade.Settings.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "projects" do
    belongs_to :user, Synkade.Accounts.User

    field :name, :string
    field :enabled, :boolean, default: true
    field :tracker_repo, :string

    belongs_to :default_agent, Synkade.Settings.Agent, type: :binary_id

    timestamps()
  end

  @required_fields ~w(name)a
  @optional_fields ~w(enabled tracker_repo default_agent_id user_id)a

  def changeset(project, attrs) do
    project
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:user_id, :name])
  end
end
