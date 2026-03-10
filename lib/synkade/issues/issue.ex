defmodule Synkade.Issues.Issue do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @kinds ~w(epic research task bug)
  @states ~w(backlog queued in_progress awaiting_review done cancelled)

  schema "issues" do
    field :title, :string
    field :description, :string
    field :kind, :string, default: "task"
    field :state, :string, default: "backlog"
    field :priority, :integer, default: 0
    field :depth, :integer, default: 0
    field :position, :integer, default: 0
    field :agent_output, :string
    field :github_issue_url, :string
    field :github_pr_url, :string
    field :metadata, :map, default: %{}

    belongs_to :project, Synkade.Settings.Project
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps()
  end

  def kinds, do: @kinds
  def states, do: @states

  @required_fields ~w(title project_id)a
  @optional_fields ~w(description kind state priority depth position parent_id
                      agent_output github_issue_url github_pr_url metadata)a

  def changeset(issue, attrs) do
    issue
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:state, @states)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:parent_id)
  end
end
