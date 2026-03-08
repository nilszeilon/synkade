defmodule Synkade.Prompt.Renderer do
  @moduledoc false

  @spec render(String.t(), map(), map(), integer() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def render(template, project, issue, attempt \\ nil) do
    context =
      %{
        "project" => stringify_keys(project),
        "issue" => stringify_keys(issue),
        "attempt" => attempt
      }

    with {:ok, parsed} <- parse_template(template),
         {:ok, rendered} <- render_template(parsed, context) do
      {:ok, rendered}
    end
  end

  defp parse_template(template) do
    case Solid.parse(template) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, {:template_parse_error, format_error(reason)}}
    end
  end

  defp render_template(parsed, context) do
    case Solid.render(parsed, context) do
      {:ok, iodata} ->
        {:ok, IO.iodata_to_binary(iodata)}

      {:error, errors, _partial} ->
        {:error, {:template_render_error, format_errors(errors)}}

      {:error, reason} ->
        {:error, {:template_render_error, format_error(reason)}}
    end
  end

  defp stringify_keys(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp stringify_keys(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp stringify_keys(%Date{} = d), do: Date.to_iso8601(d)

  defp stringify_keys(%{__struct__: _} = struct) do
    struct |> Map.from_struct() |> stringify_keys()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp format_errors(errors) when is_list(errors) do
    errors |> Enum.map(&format_error/1) |> Enum.join("; ")
  end

  defp format_error(%{message: msg}), do: msg
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
