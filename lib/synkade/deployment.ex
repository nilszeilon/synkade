defmodule Synkade.Deployment do
  @moduledoc false

  def mode do
    case System.get_env("SYNKADE_MODE") do
      "hosted" -> :hosted
      _ -> :self_hosted
    end
  end

  def hosted?, do: mode() == :hosted
end
