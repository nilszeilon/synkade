defmodule Synkade.Tracker.GitHub do
  @moduledoc false
  @behaviour Synkade.Tracker.Behaviour

  alias Synkade.Tracker.Issue
  alias Synkade.Workflow.Config

  @impl true
  def fetch_candidate_issues(config, project_name) do
    active_states = Config.active_states(config)
    fetch_issues_by_states(config, project_name, active_states)
  end

  @impl true
  def fetch_issues_by_states(config, project_name, states) do
    repo = Config.get(config, "tracker", "repo")
    endpoint = Config.get(config, "tracker", "endpoint") || "https://api.github.com"
    labels = Config.tracker_labels(config)

    gh_state =
      cond do
        Enum.all?(states, &(normalize_state(&1) == "open")) -> "open"
        Enum.all?(states, &(normalize_state(&1) == "closed")) -> "closed"
        true -> "all"
      end

    params = [state: gh_state, per_page: 100, sort: "created", direction: "asc"]
    params =
      if labels && labels != [], do: [{:labels, Enum.join(labels, ",")} | params], else: params

    url = "#{endpoint}/repos/#{repo}/issues"

    case fetch_all_pages(url, params, config) do
      {:ok, raw_issues} ->
        issues =
          raw_issues
          |> Enum.reject(&Map.has_key?(&1, "pull_request"))
          |> Enum.filter(fn issue ->
            state = normalize_state(issue["state"])
            state in Enum.map(states, &normalize_state/1)
          end)
          |> Enum.map(&normalize_issue(&1, project_name, config))

        {:ok, issues}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def fetch_issue_states_by_ids(config, _project_name, ids) do
    repo = Config.get(config, "tracker", "repo")
    endpoint = Config.get(config, "tracker", "endpoint") || "https://api.github.com"

    results =
      Enum.reduce_while(ids, {:ok, %{}}, fn id, {:ok, acc} ->
        url = "#{endpoint}/repos/#{repo}/issues/#{id}"

        case req_get(url, [], config) do
          {:ok, %{status: 200, body: body}} ->
            {:cont, {:ok, Map.put(acc, to_string(id), body["state"])}}

          {:ok, %{status: 404}} ->
            {:cont, {:ok, acc}}

          {:ok, %{status: status, body: body}} ->
            {:halt, {:error, "GitHub API error #{status}: #{inspect(body)}"}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    results
  end

  @impl true
  def fetch_all_issues(config, project_name, opts \\ []) do
    repo = Config.get(config, "tracker", "repo")
    endpoint = Config.get(config, "tracker", "endpoint") || "https://api.github.com"

    states = Keyword.get(opts, :states, ["open"])

    gh_state =
      cond do
        Enum.all?(states, &(normalize_state(&1) == "open")) -> "open"
        Enum.all?(states, &(normalize_state(&1) == "closed")) -> "closed"
        true -> "all"
      end

    params = [state: gh_state, per_page: 100, sort: "created", direction: "asc"]
    url = "#{endpoint}/repos/#{repo}/issues"

    case fetch_all_pages(url, params, config) do
      {:ok, raw_issues} ->
        issues =
          raw_issues
          |> Enum.reject(&Map.has_key?(&1, "pull_request"))
          |> Enum.filter(fn issue ->
            state = normalize_state(issue["state"])
            state in Enum.map(states, &normalize_state/1)
          end)
          |> Enum.map(&normalize_issue(&1, project_name, config))

        {:ok, issues}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def add_issue_label(config, _project_name, issue_id, label) do
    repo = Config.get(config, "tracker", "repo")
    endpoint = Config.get(config, "tracker", "endpoint") || "https://api.github.com"
    url = "#{endpoint}/repos/#{repo}/issues/#{issue_id}/labels"

    case req_post(url, %{"labels" => [label]}, config) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, "GitHub API error #{status}: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def remove_issue_label(config, _project_name, issue_id, label) do
    repo = Config.get(config, "tracker", "repo")
    endpoint = Config.get(config, "tracker", "endpoint") || "https://api.github.com"
    url = "#{endpoint}/repos/#{repo}/issues/#{issue_id}/labels/#{URI.encode(label)}"

    case req_delete(url, config) do
      {:ok, %{status: status}} when status in [200, 204, 404] -> :ok
      {:ok, %{status: status, body: body}} -> {:error, "GitHub API error #{status}: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def fetch_pr_status(config, _project_name, pr_number) do
    repo = Config.get(config, "tracker", "repo")
    endpoint = Config.get(config, "tracker", "endpoint") || "https://api.github.com"
    url = "#{endpoint}/repos/#{repo}/pulls/#{pr_number}"

    case req_get(url, [], config) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{state: body["state"], merged: body["merged"] || false}}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Private ---

  defp fetch_all_pages(url, params, config, acc \\ []) do
    case req_get(url, params, config) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        all = acc ++ body

        case next_page_url(headers) do
          nil -> {:ok, all}
          next_url -> fetch_all_pages(next_url, [], config, all)
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req_get(url, params, config) do
    token = resolve_token(config)

    headers =
      [{"accept", "application/vnd.github+json"}] ++
        if(token, do: [{"authorization", "Bearer #{token}"}], else: [])

    opts = [params: params, headers: headers, receive_timeout: 30_000]

    # Allow test adapter injection via config
    opts =
      case Map.get(config, "__req_options__") do
        nil -> opts
        extra -> Keyword.merge(opts, extra)
      end

    Req.get(url, opts)
  end

  defp req_post(url, body, config) do
    token = resolve_token(config)

    headers =
      [{"accept", "application/vnd.github+json"}] ++
        if(token, do: [{"authorization", "Bearer #{token}"}], else: [])

    opts = [headers: headers, json: body, receive_timeout: 30_000]

    opts =
      case Map.get(config, "__req_options__") do
        nil -> opts
        extra -> Keyword.merge(opts, extra)
      end

    Req.post(url, opts)
  end

  defp req_delete(url, config) do
    token = resolve_token(config)

    headers =
      [{"accept", "application/vnd.github+json"}] ++
        if(token, do: [{"authorization", "Bearer #{token}"}], else: [])

    opts = [headers: headers, receive_timeout: 30_000]

    opts =
      case Map.get(config, "__req_options__") do
        nil -> opts
        extra -> Keyword.merge(opts, extra)
      end

    Req.delete(url, opts)
  end

  defp resolve_token(config) do
    case Config.auth_mode(config) do
      "app" ->
        installation_id = Config.get(config, "tracker", "installation_id")

        case Synkade.Tracker.GitHub.TokenServer.get_token(installation_id) do
          {:ok, token} -> token
          {:error, _} -> nil
        end

      "pat" ->
        raw = Config.get(config, "tracker", "api_key")

        case raw do
          nil ->
            case System.get_env("GITHUB_TOKEN") do
              nil -> nil
              "" -> nil
              token -> token
            end

          token ->
            token
        end
    end
  end

  defp next_page_url(headers) do
    link_header =
      headers
      |> Enum.find(fn {name, _} -> String.downcase(name) == "link" end)

    case link_header do
      {_, value} ->
        value
        |> String.split(",")
        |> Enum.find_value(fn part ->
          if String.contains?(part, "rel=\"next\"") do
            case Regex.run(~r/<([^>]+)>/, part) do
              [_, url] -> url
              _ -> nil
            end
          end
        end)

      nil ->
        nil
    end
  end

  defp normalize_issue(raw, project_name, config) do
    repo = Config.get(config, "tracker", "repo")
    number = raw["number"]

    %Issue{
      project_name: project_name,
      id: to_string(number),
      identifier: "#{repo}##{number}",
      title: raw["title"],
      description: raw["body"],
      priority: extract_priority(raw["labels"]),
      state: raw["state"],
      branch_name: nil,
      url: raw["html_url"],
      labels: normalize_labels(raw["labels"]),
      blocked_by: parse_blockers(raw["body"]),
      created_at: parse_datetime(raw["created_at"]),
      updated_at: parse_datetime(raw["updated_at"])
    }
  end

  defp normalize_labels(nil), do: []

  defp normalize_labels(labels) do
    labels
    |> Enum.map(fn
      %{"name" => name} -> String.downcase(name)
      name when is_binary(name) -> String.downcase(name)
    end)
  end

  defp extract_priority(nil), do: nil

  defp extract_priority(labels) do
    labels
    |> Enum.find_value(fn
      %{"name" => name} -> parse_priority_label(name)
      name when is_binary(name) -> parse_priority_label(name)
    end)
  end

  defp parse_priority_label(name) do
    case Regex.run(~r/^priority[:\-_\s]*(\d+)$/i, name) do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  defp parse_blockers(nil), do: []
  defp parse_blockers(""), do: []

  defp parse_blockers(body) do
    # Parse "blocked by #123" or "depends on #456" patterns
    Regex.scan(~r/(?:blocked\s+by|depends\s+on)\s+#(\d+)/i, body)
    |> Enum.map(fn [_, num] ->
      %{id: num, identifier: "##{num}", state: nil}
    end)
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp normalize_state(state), do: state |> String.trim() |> String.downcase()
end
