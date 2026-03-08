defmodule Synkade.Tracker.Issue do
  @moduledoc false

  @type blocker_ref :: %{
          id: String.t() | nil,
          identifier: String.t() | nil,
          state: String.t() | nil
        }

  @type t :: %__MODULE__{
          project_name: String.t(),
          id: String.t(),
          identifier: String.t(),
          title: String.t(),
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t(),
          branch_name: String.t() | nil,
          url: String.t() | nil,
          labels: [String.t()],
          blocked_by: [blocker_ref()],
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:project_name, :id, :identifier, :title, :state]
  defstruct [
    :project_name,
    :id,
    :identifier,
    :title,
    :description,
    :priority,
    :state,
    :branch_name,
    :url,
    :created_at,
    :updated_at,
    labels: [],
    blocked_by: []
  ]
end
