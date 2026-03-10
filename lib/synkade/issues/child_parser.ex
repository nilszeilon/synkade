defmodule Synkade.Issues.ChildParser do
  @moduledoc false

  @doc """
  Parse structured child issue declarations from agent output.

  Looks for content between `<!-- SYNKADE:CHILDREN` and `SYNKADE:CHILDREN -->` markers.
  Content is a simple YAML-like list of maps with keys: title, kind, description, priority.

  Returns a list of maps with atom keys.
  """
  @spec parse(String.t()) :: [map()]
  def parse(text) when is_binary(text) do
    case extract_block(text) do
      nil -> []
      yaml_text -> parse_items(yaml_text)
    end
  end

  def parse(_), do: []

  defp extract_block(text) do
    case Regex.run(~r/<!-- SYNKADE:CHILDREN\s*\n(.*?)\nSYNKADE:CHILDREN -->/s, text) do
      [_, content] -> String.trim(content)
      _ -> nil
    end
  end

  # Parse a simple YAML-like list format:
  # - title: "Sub-task title"
  #   kind: task
  #   description: "What needs to be done"
  #   priority: 1
  defp parse_items(text) do
    text
    |> String.split(~r/^- /m, trim: true)
    |> Enum.map(&parse_item/1)
    |> Enum.filter(&valid_item?/1)
  end

  defp parse_item(block) do
    lines = String.split(block, "\n", trim: true)

    fields =
      Enum.reduce(lines, %{}, fn line, acc ->
        line = String.trim(line)

        case Regex.run(~r/^(\w+):\s*(.+)$/, line) do
          [_, key, value] ->
            Map.put(acc, key, strip_quotes(String.trim(value)))

          _ ->
            acc
        end
      end)

    %{
      title: fields["title"],
      kind: fields["kind"] || "task",
      description: fields["description"],
      priority: parse_priority(fields["priority"])
    }
  end

  defp strip_quotes(value) do
    value
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.trim_leading("'")
    |> String.trim_trailing("'")
  end

  defp valid_item?(%{title: title}) when is_binary(title) and title != "", do: true
  defp valid_item?(_), do: false

  defp parse_priority(p) when is_binary(p) do
    case Integer.parse(p) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_priority(p) when is_integer(p), do: p
  defp parse_priority(_), do: 0
end
