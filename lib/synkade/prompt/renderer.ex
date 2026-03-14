defmodule Synkade.Prompt.Renderer do
  @moduledoc false

  @default_template """
  You are working on issue {{ issue.identifier }}: {{ issue.title }}

  {{ issue.body }}

  Analyze the issue, implement the fix or feature, and run the test suite to verify your changes.
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

  @children_suffix """

  If your work produces actionable sub-tasks, output them in this format:
  <!-- SYNKADE:CHILDREN
  - body: "# Sub-task title\\n\\nWhat needs to be done"
  SYNKADE:CHILDREN -->
  """

  @git_suffix """

  ## Git & Pull Requests

  You have a `GITHUB_TOKEN` environment variable set with a GitHub Personal Access Token.
  The workspace is a git clone of `{{ tracker_repo }}`.

  After making changes, commit your work and create a pull request using `gh`:

  ```bash
  git checkout -b fix/{{ issue.identifier }}
  git add -A
  git commit -m "Description of changes"
  gh pr create --title "Short title" --body "Description of what was done"
  ```

  Always create a PR with your changes so they can be reviewed.
  """

  @auto_merge_suffix """

  ## Auto-Merge

  This issue has auto-merge enabled. After creating your pull request, merge it directly to main:

  ```bash
  gh pr merge --merge
  ```

  Do NOT wait for review — merge immediately after PR creation.
  """

  @api_suffix """

  ## Synkade Issue API

  You have access to the Synkade issue management API via environment variables:
  - `SYNKADE_API_URL` — base URL for API calls
  - `SYNKADE_API_TOKEN` — bearer token for authentication

  Use these to create, list, and update issues at runtime:

  ```bash
  # List issues for this project
  curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" "$SYNKADE_API_URL/issues?project_id={{ project_id }}"

  # Create a sub-issue
  curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" -H "Content-Type: application/json" \\
    -d '{"project_id":"{{ project_id }}","body":"# Sub-task title\\n\\nDetails","parent_id":"{{ issue.id }}"}' \\
    "$SYNKADE_API_URL/issues"

  # Update an issue (state, description, etc.)
  curl -s -X PATCH -H "Authorization: Bearer $SYNKADE_API_TOKEN" -H "Content-Type: application/json" \\
    -d '{"state":"done"}' \\
    "$SYNKADE_API_URL/issues/<issue_id>"

  # Create multiple child issues at once
  curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" -H "Content-Type: application/json" \\
    -d '{"children":[{"body":"# Child 1\\n\\nDetails"},{"body":"# Child 2\\n\\nDetails"}]}' \\
    "$SYNKADE_API_URL/issues/{{ issue.id }}/children"
  ```

  Alternatively, you can output children using SYNKADE:CHILDREN markers (see below).

  ### Status Reporting

  Report your status periodically so Synkade knows you're still working:

  ```bash
  # Report working status (send every 2-3 minutes during long tasks)
  curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" -H "Content-Type: application/json" \\
    -d '{"issue_id":"{{ issue.id }}","status":"working","message":"Brief description of current step"}' \\
    "$SYNKADE_API_URL/heartbeat"

  # Report an error
  curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" -H "Content-Type: application/json" \\
    -d '{"issue_id":"{{ issue.id }}","status":"error","message":"What went wrong"}' \\
    "$SYNKADE_API_URL/heartbeat"

  # Report being blocked
  curl -s -X POST -H "Authorization: Bearer $SYNKADE_API_TOKEN" -H "Content-Type: application/json" \\
    -d '{"issue_id":"{{ issue.id }}","status":"blocked","message":"What is blocking progress"}' \\
    "$SYNKADE_API_URL/heartbeat"
  ```

  Valid statuses: `working`, `error`, `blocked`. Send a heartbeat every 2-3 minutes during long-running tasks to prevent stall detection from killing your session.
  """

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

    # Add git/PR suffix if tracker has a repo and API key (PAT)
    tracker_repo = get_in(project, [:config, "tracker", "repo"])
    tracker_api_key = get_in(project, [:config, "tracker", "api_key"])

    template =
      if tracker_repo && tracker_api_key do
        git_template = template <> @git_suffix

        if Map.get(issue, :auto_merge) do
          git_template <> @auto_merge_suffix
        else
          git_template
        end
      else
        template
      end

    # Add API suffix if Synkade API is configured, otherwise fallback to children markers
    has_api = get_in(project, [:config, "agent", "synkade_api_url"]) != nil

    template =
      if has_api do
        template <> @api_suffix <> @children_suffix
      else
        template <> @children_suffix
      end

    project_id = get_in(project, [:config, "agent", "synkade_api_url"]) && get_project_id(project)

    context =
      %{
        "project" => stringify_keys(project),
        "issue" => stringify_keys(issue),
        "attempt" => attempt,
        "ancestors" => Enum.map(ancestors, &stringify_keys/1),
        "has_parent" => ancestors != [],
        "dispatch_message" => dispatch_message,
        "project_id" => project_id,
        "tracker_repo" => tracker_repo
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

  defp get_project_id(%{db_id: id}) when is_binary(id), do: id
  defp get_project_id(_), do: nil

  defp format_errors(errors) when is_list(errors) do
    errors |> Enum.map(&format_error/1) |> Enum.join("; ")
  end

  defp format_error(%{message: msg}), do: msg
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
