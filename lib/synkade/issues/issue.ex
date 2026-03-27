defmodule Synkade.Issues.Issue do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @states ~w(backlog worked_on done)

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
    field :auto_merge, :boolean, default: false
    field :recurring, :boolean, default: false
    field :recurrence_interval, :integer, default: 24
    field :recurrence_unit, :string, default: "hours"

    field :last_heartbeat_at, :utc_datetime
    field :last_heartbeat_message, :string

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
                      dispatch_message assigned_agent_id
                      auto_merge recurring recurrence_interval recurrence_unit
                      last_heartbeat_at last_heartbeat_message)a

  def changeset(issue, attrs) do
    issue
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:state, @states)
    |> validate_number(:recurrence_interval, greater_than: 0, less_than_or_equal_to: 365)
    |> validate_inclusion(:recurrence_unit, ~w(hours days weeks))
    |> validate_recurrence_minimum()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:parent_id)
  end

  # Enforce minimum recurrence of 1 hour
  defp validate_recurrence_minimum(changeset) do
    interval = get_field(changeset, :recurrence_interval)
    unit = get_field(changeset, :recurrence_unit)

    case {interval, unit} do
      {nil, _} -> changeset
      {_, nil} -> changeset
      {i, "hours"} when i < 1 -> add_error(changeset, :recurrence_interval, "must be at least 1 hour")
      {i, "days"} when i < 1 -> add_error(changeset, :recurrence_interval, "must be at least 1 day")
      {i, "weeks"} when i < 1 -> add_error(changeset, :recurrence_interval, "must be at least 1 week")
      _ -> changeset
    end
  end
end
