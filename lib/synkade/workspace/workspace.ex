defmodule Synkade.Workspace do
  @moduledoc false

  @type t :: %__MODULE__{
          project_name: String.t(),
          path: String.t(),
          workspace_key: String.t(),
          created_now: boolean()
        }

  @enforce_keys [:project_name, :path, :workspace_key]
  defstruct [
    :project_name,
    :path,
    :workspace_key,
    created_now: false
  ]
end
