defmodule Synkade.Issues.Issue do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @states ~w(backlog queued in_progress awaiting_review done cancelled)

  schema "issues" do
    field :body, :string
    field :state, :string, default: "backlog"
    field :depth, :integer, default: 0
    field :position, :integer, default: 0
    field :agent_output, :string
    field :github_issue_url, :string
    field :github_pr_url, :string
    field :metadata, :map, default: %{}
    field :dispatch_message, :string

    belongs_to :project, Synkade.Settings.Project
    belongs_to :parent, __MODULE__
    belongs_to :assigned_agent, Synkade.Settings.Agent
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps()
  end

  def states, do: @states

  @doc "Derive title from first `# Heading` in body, defaulting to \"Unnamed\"."
  def title(%__MODULE__{body: nil}), do: "Unnamed"
  def title(%__MODULE__{body: ""}), do: "Unnamed"

  def title(%__MODULE__{body: text}) do
    case Regex.run(~r/^#\s+(.+)$/m, text) do
      [_, heading] -> String.trim(heading)
      nil -> "Unnamed"
    end
  end

  @required_fields ~w(project_id)a
  @optional_fields ~w(body state depth position parent_id
                      agent_output github_issue_url github_pr_url metadata
                      dispatch_message assigned_agent_id)a

  def changeset(issue, attrs) do
    issue
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:state, @states)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:parent_id)
  end
end
