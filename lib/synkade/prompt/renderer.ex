defmodule Synkade.Prompt.Renderer do
  @moduledoc false

  @default_template """
  You are working on issue {{ issue.identifier }}: {{ issue.title }}

  {{ issue.description }}
  """

  @pr_suffix ~S"""

  When you have completed the work, create a pull request using `gh pr create` and push it.
  The PR title should reference the issue (e.g. "Fix #{{ issue.id }}: {{ issue.title }}").
  Include a summary of changes in the PR body.
  """

  @ancestor_template """
  {% if has_parent %}

  ## Context from parent issues
  {% for ancestor in ancestors %}
  ### {{ ancestor.title }}
  {{ ancestor.description }}
  {% if ancestor.agent_output %}
  #### Findings:
  {{ ancestor.agent_output }}
  {% endif %}
  {% endfor %}
  {% endif %}
  """

  @children_suffix """

  If your work produces actionable sub-tasks, output them in this format:
  <!-- SYNKADE:CHILDREN
  - title: "Sub-task title"
    description: "What needs to be done"
    priority: 1
  SYNKADE:CHILDREN -->
  """

  @spec render(String.t() | nil, map(), map(), integer() | nil, list()) ::
          {:ok, String.t()} | {:error, term()}
  def render(template, project, issue, attempt \\ nil, ancestors \\ []) do
    template = (template || @default_template) <> @pr_suffix

    # Add ancestor context if there are ancestors
    template =
      if ancestors != [] do
        @ancestor_template <> template
      else
        template
      end

    # Always include children instruction — agents infer when to create sub-tasks
    template = template <> @children_suffix

    context =
      %{
        "project" => stringify_keys(project),
        "issue" => stringify_keys(issue),
        "attempt" => attempt,
        "ancestors" => Enum.map(ancestors, &stringify_keys/1),
        "has_parent" => ancestors != []
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
