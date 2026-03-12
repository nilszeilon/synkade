defmodule Synkade.Issues.ChildParser do
  @moduledoc false

  @doc """
  Parse structured child issue declarations from agent output.

  Looks for content between `<!-- SYNKADE:CHILDREN` and `SYNKADE:CHILDREN -->` markers.
  Content is a simple YAML-like list of maps with keys: title, description, body.

  Returns a list of maps with atom keys containing `:body`.
  For backwards compat, accepts `title`+`description` and assembles into body.
  Also accepts `body` key directly.
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

    # Support `body` key directly, or assemble from `title` + `description`
    body = fields["body"] || assemble_body(fields["title"], fields["description"])

    %{body: body}
  end

  defp assemble_body(nil, nil), do: nil
  defp assemble_body(title, nil), do: "# #{title}"
  defp assemble_body(nil, desc), do: desc
  defp assemble_body(title, desc), do: "# #{title}\n\n#{desc}"

  defp strip_quotes(value) do
    value
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.trim_leading("'")
    |> String.trim_trailing("'")
  end

  defp valid_item?(%{body: body}) when is_binary(body) and body != "", do: true
  defp valid_item?(_), do: false
end
