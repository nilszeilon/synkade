defmodule Synkade.Workspace.Git do
  @moduledoc "Git operations for workspace diff viewing."

  @doc """
  Detects the default/base branch of the repo (main, master, or falls back to HEAD).
  Returns the branch name as a string.
  """
  @spec detect_base_branch(String.t()) :: String.t()
  def detect_base_branch(path) do
    # Try origin remote HEAD first (most reliable for cloned repos)
    case System.cmd("git", ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"],
           cd: path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        # Returns "origin/main" — strip the "origin/" prefix
        output |> String.trim() |> String.replace_prefix("origin/", "")

      _ ->
        # Fall back to checking if main or master exists
        cond do
          branch_exists?(path, "main") -> "main"
          branch_exists?(path, "master") -> "master"
          true -> "HEAD"
        end
    end
  end

  defp branch_exists?(path, branch) do
    case System.cmd("git", ["rev-parse", "--verify", branch],
           cd: path,
           stderr_to_stdout: true
         ) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Returns the current branch name, or nil if detached/not a repo.
  """
  @spec current_branch(String.t()) :: String.t() | nil
  def current_branch(path) do
    case System.cmd("git", ["branch", "--show-current"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        branch = String.trim(output)
        if branch == "", do: nil, else: branch

      _ ->
        nil
    end
  end

  @doc """
  Returns a list of changed files compared to the base branch.
  Includes both committed changes on the branch AND uncommitted working tree changes.
  Each entry is a map: `%{status: "M", file: "path/to/file.ex", additions: 10, deletions: 3}`.
  """
  @spec changed_files(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def changed_files(path, base_ref) do
    if not File.dir?(Path.join(path, ".git")) do
      {:ok, []}
    else
      # Diff working tree against base branch — shows all changes (committed + uncommitted)
      {stat_output, stat_exit} =
        System.cmd("git", ["diff", "--numstat", base_ref], cd: path, stderr_to_stdout: true)

      {status_output, status_exit} =
        System.cmd("git", ["diff", "--name-status", base_ref], cd: path, stderr_to_stdout: true)

      # Get untracked files (new files not yet staged)
      {untracked_output, untracked_exit} =
        System.cmd("git", ["ls-files", "--others", "--exclude-standard"],
          cd: path,
          stderr_to_stdout: true
        )

      if stat_exit == 0 and status_exit == 0 and untracked_exit == 0 do
        numstat = parse_numstat(stat_output)

        diff_files =
          status_output
          |> String.trim()
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            case String.split(line, "\t", parts: 2) do
              [status, file] ->
                {add, del} = Map.get(numstat, file, {0, 0})
                %{status: status, file: file, additions: add, deletions: del}

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        # Untracked files won't appear in diff against base — add them separately
        tracked_files = MapSet.new(diff_files, & &1.file)

        untracked_files =
          untracked_output
          |> String.trim()
          |> String.split("\n", trim: true)
          |> Enum.reject(&MapSet.member?(tracked_files, &1))
          |> Enum.map(fn file ->
            line_count = count_file_lines(path, file)
            %{status: "U", file: file, additions: line_count, deletions: 0}
          end)

        {:ok, diff_files ++ untracked_files}
      else
        # base_ref might not exist — fall back to showing everything vs empty tree
        empty_tree = "4b825dc642cb6eb9a060e54bf899d69f82cf7115"

        {stat_out, exit_code} =
          System.cmd("git", ["diff", "--numstat", empty_tree, "HEAD"],
            cd: path,
            stderr_to_stdout: true
          )

        {status_out, _} =
          System.cmd("git", ["diff", "--name-status", empty_tree, "HEAD"],
            cd: path,
            stderr_to_stdout: true
          )

        if exit_code == 0 do
          numstat = parse_numstat(stat_out)

          files =
            status_out
            |> String.trim()
            |> String.split("\n", trim: true)
            |> Enum.map(fn line ->
              case String.split(line, "\t", parts: 2) do
                [status, file] ->
                  {add, del} = Map.get(numstat, file, {0, 0})
                  %{status: status, file: file, additions: add, deletions: del}

                _ ->
                  nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          {:ok, files}
        else
          {:error, stat_output}
        end
      end
    end
  end

  @doc """
  Returns the unified diff for a specific file compared to the base branch.
  Shows the full branch diff for that file (committed + uncommitted changes).
  """
  @spec file_diff(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def file_diff(path, filename, base_ref) do
    {output, exit_code} =
      System.cmd("git", ["diff", base_ref, "--", filename],
        cd: path,
        stderr_to_stdout: true
      )

    cond do
      exit_code == 0 and output != "" ->
        {:ok, output}

      true ->
        # Might be an untracked file not known to base — show full content as addition
        file_path = Path.join(path, filename) |> Path.expand()
        base_path = Path.expand(path)

        if not String.starts_with?(file_path, base_path <> "/") do
          {:error, :path_traversal}
        else
          if File.exists?(file_path) do
            case File.read(file_path) do
              {:ok, content} ->
                lines =
                  content
                  |> String.split("\n")
                  |> Enum.map(fn line -> "+#{line}" end)
                  |> Enum.join("\n")

                line_count = content |> String.split("\n") |> length()

                {:ok,
                 "--- /dev/null\n+++ b/#{filename}\n@@ -0,0 +1,#{line_count} @@\n#{lines}"}

              {:error, reason} ->
                {:error, reason}
            end
          else
            {:ok, ""}
          end
        end
    end
  end

  @doc """
  Parses a unified diff string into structured lines for rendering.
  """
  @spec parse_diff(String.t()) :: [map()]
  def parse_diff(""), do: []

  def parse_diff(raw) do
    raw
    |> String.split("\n")
    |> parse_lines(nil, nil, [])
    |> Enum.reverse()
  end

  # --- Private helpers ---

  defp parse_numstat(output) do
    output
    |> String.trim()
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      case String.split(line, "\t", parts: 3) do
        [add, del, file] -> {file, {parse_int(add), parse_int(del)}}
        _ -> {nil, {0, 0}}
      end
    end)
  end

  defp parse_int("-"), do: 0

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp count_file_lines(workspace_path, file) do
    full_path = Path.join(workspace_path, file)

    if File.exists?(full_path) do
      case File.read(full_path) do
        {:ok, content} -> content |> String.split("\n") |> length()
        _ -> 0
      end
    else
      0
    end
  end

  defp parse_lines([], _old, _new, acc), do: acc

  defp parse_lines(["--- " <> _ | rest], _old, _new, acc) do
    parse_lines(rest, nil, nil, acc)
  end

  defp parse_lines(["+++ " <> _ | rest], _old, _new, acc) do
    parse_lines(rest, nil, nil, acc)
  end

  defp parse_lines(["@@" <> _ = line | rest], _old, _new, acc) do
    {old_start, new_start} = parse_hunk_header(line)
    entry = %{type: :header, text: line, old_line: nil, new_line: nil}
    parse_lines(rest, old_start, new_start, [entry | acc])
  end

  defp parse_lines(["+" <> text | rest], old, new, acc) when not is_nil(new) do
    entry = %{type: :add, text: text, old_line: nil, new_line: new}
    parse_lines(rest, old, new + 1, [entry | acc])
  end

  defp parse_lines(["-" <> text | rest], old, new, acc) when not is_nil(old) do
    entry = %{type: :remove, text: text, old_line: old, new_line: nil}
    parse_lines(rest, old + 1, new, [entry | acc])
  end

  defp parse_lines([" " <> text | rest], old, new, acc)
       when not is_nil(old) and not is_nil(new) do
    entry = %{type: :context, text: text, old_line: old, new_line: new}
    parse_lines(rest, old + 1, new + 1, [entry | acc])
  end

  defp parse_lines(["" | rest], old, new, acc) when not is_nil(old) and not is_nil(new) do
    entry = %{type: :context, text: "", old_line: old, new_line: new}
    parse_lines(rest, old + 1, new + 1, [entry | acc])
  end

  defp parse_lines([_line | rest], old, new, acc) do
    parse_lines(rest, old, new, acc)
  end

  defp parse_hunk_header(line) do
    case Regex.run(~r/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/, line) do
      [_, old_start, new_start] ->
        {String.to_integer(old_start), String.to_integer(new_start)}

      _ ->
        {1, 1}
    end
  end
end
