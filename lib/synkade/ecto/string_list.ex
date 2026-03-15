defmodule Synkade.Ecto.StringList do
  @moduledoc """
  Custom Ecto type that stores a list of strings as JSON text in SQLite.
  """
  use Ecto.Type

  def type, do: :string

  def cast(list) when is_list(list) do
    if Enum.all?(list, &is_binary/1), do: {:ok, list}, else: :error
  end

  def cast(binary) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, list} when is_list(list) -> {:ok, list}
      _ -> :error
    end
  end

  def cast(_), do: :error

  def dump(list) when is_list(list), do: Jason.encode(list)
  def dump(_), do: :error

  def load(nil), do: {:ok, []}
  def load(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> {:ok, list}
      _ -> :error
    end
  end

  def load(_), do: :error
end
