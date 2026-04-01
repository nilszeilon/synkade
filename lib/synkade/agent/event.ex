defmodule Synkade.Agent.Event do
  @moduledoc false

  @type t :: %__MODULE__{
          type: String.t(),
          session_id: String.t() | nil,
          message: String.t() | nil,
          model: String.t() | nil,
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          timestamp: DateTime.t() | nil,
          raw: map() | nil
        }

  defstruct [
    :type,
    :session_id,
    :message,
    :model,
    :timestamp,
    :raw,
    input_tokens: 0,
    output_tokens: 0,
    total_tokens: 0
  ]
end
