defmodule Synkade.Prompt.Renderer do
  @moduledoc false

  @default_template """
  You are working on issue {{ issue.identifier }}: {{ issue.title }}

  {{ issue.body }}

  Analyze the issue, implement the fix or feature, and run the test suite to verify your changes.
  Use the synkade skill for git workflow, PR creation, API access, and status reporting.
  """

  @ancestor_template """
  {% if has_parent %}

  ## Context from parent issues
  {% for ancestor in ancestors %}
  ### {{ ancestor.title }}
  {{ ancestor.body }}
  {% if ancestor.agent_output %}
  #### Findings:
  {{ ancestor.agent_output }}
  {% endif %}
  {% endfor %}
  {% endif %}
  """

  @dispatch_template """
  {% if dispatch_message %}

  ## Human Instructions
  {{ dispatch_message }}
  {% endif %}
  """

  @auto_merge_line "\nAfter creating the PR, merge it immediately with `gh pr merge --merge`.\n"

  @spec render(
          String.t() | nil,
          map(),
          map(),
          integer() | nil,
          list(),
          String.t() | nil
        ) ::
          {:ok, String.t()} | {:error, term()}
  def render(
        template,
        project,
        issue,
        attempt \\ nil,
        ancestors \\ [],
        dispatch_message \\ nil
      ) do
    template = template || @default_template

    # Add ancestor context if there are ancestors
    template =
      if ancestors != [] do
        @ancestor_template <> template
      else
        template
      end

    # Add dispatch message section
    template = template <> @dispatch_template

    # Add auto-merge one-liner if enabled
    template =
      if Map.get(issue, :auto_merge) do
        template <> @auto_merge_line
      else
        template
      end

    context =
      %{
        "project" => stringify_keys(project),
        "issue" => stringify_keys(issue),
        "attempt" => attempt,
        "ancestors" => Enum.map(ancestors, &stringify_keys/1),
        "has_parent" => ancestors != [],
        "dispatch_message" => dispatch_message
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
