defmodule Synkade.Skills.Skill do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "skills" do
    belongs_to :user, Synkade.Accounts.User
    field :name, :string
    field :content, :string
    field :built_in, :boolean, default: false

    timestamps()
  end

  @fields ~w(name content built_in user_id)a

  def changeset(skill, attrs) do
    skill
    |> cast(attrs, @fields)
    |> validate_required([:name, :content])
    |> unique_constraint([:user_id, :name])
  end
end
