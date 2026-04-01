defmodule Synkade.Execution.AgentRunner do
  @moduledoc "Runs an agent session for an issue. Extracted from Orchestrator.Worker."

  require Logger

  alias Synkade.Prompt.Renderer
  alias Synkade.Execution.BackendClient
  alias Synkade.Tracker.Client, as: TrackerClient
  alias Synkade.Workflow.Config
  alias Synkade.Issues.ChildParser

  @doc """
  Run a worker for an issue. Called from Oban AgentWorker.

  `opts` may include `:user_id` and `:agent_id` for token usage tracking.
  """
  def run(project, issue, attempt, opts \\ []) do
    config = project.config
    project_name = project.name

    Logger.info(
      "AgentRunner starting for #{project_name}:#{issue.identifier} (attempt #{inspect(attempt)})"
    )

    context = %{
      user_id: Keyword.get(opts, :user_id),
      agent_id: Keyword.get(opts, :agent_id)
    }

    with {:ok, env_ref} <- BackendClient.setup_env(config, project_name, issue.identifier),
         :ok <- BackendClient.run_before_hook(config, env_ref),
         {:ok, prompt} <- render_prompt(project, issue, attempt),
         {:ok, session} <- start_agent(config, prompt, env_ref) do
      result = event_loop(project, issue, session, config, 1, context)
      BackendClient.run_after_hook(config, env_ref)
      result
    else
      {:error, reason} ->
        Logger.error(
          "AgentRunner failed for #{project_name}:#{issue.identifier}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp render_prompt(project, issue, attempt) do
    project_map = %{name: project.name, config: project.config, db_id: project.db_id}
    issue_map = Map.from_struct(issue)

    {ancestors, dispatch_message, issue_map} =
      try do
        case Synkade.Issues.get_issue(issue.id) do
          nil ->
            {[], nil, issue_map}

          db_issue ->
            ancestor_maps =
              Synkade.Issues.ancestor_chain(db_issue)
              |> Enum.map(fn a ->
                %{
                  title: Synkade.Issues.Issue.title(a),
                  body: a.body,
                  agent_output: a.agent_output
                }
              end)

            {ancestor_maps, db_issue.dispatch_message, issue_map}
        end
      catch
        _, _ -> {[], nil, issue_map}
      end

    Renderer.render(project_map, issue_map, attempt, ancestors, dispatch_message)
  end

  defp start_agent(config, prompt, env_ref) do
    BackendClient.start_agent(config, prompt, env_ref)
  end

  defp event_loop(project, issue, session, config, turn, context) do
    turn_timeout = Config.get(config, "agent", "turn_timeout_ms") || 3_600_000

    case BackendClient.await_event(config, session, turn_timeout) do
      {:partial, chunk} ->
        pending = Map.get(session, :pending_line, "")
        session = Map.put(session, :pending_line, pending <> chunk)
        event_loop(project, issue, session, config, turn, context)

      {:data, data} ->
        pending = Map.get(session, :pending_line, "")
        data = if pending != "", do: pending <> data, else: data
        session = Map.put(session, :pending_line, "")
        {session, events} = process_data(config, data, session)

        # Broadcast events via PubSub directly
        for event <- events do
          Phoenix.PubSub.broadcast(
            Synkade.PubSub,
            "agent_events:#{issue.id}",
            {:agent_event, event}
          )
        end

        # Record token usage per event
        record_token_usage(events, context, config)

        # Update heartbeat on DB
        if events != [] do
          last = List.last(events)
          Synkade.Issues.update_issue_heartbeat(issue.id, last.message)
        end

        event_loop(project, issue, session, config, turn, context)

      {:exit, 0} ->
        Logger.info("Agent exited normally for #{project.name}:#{issue.identifier}")

        case extract_pr_url(session) do
          {:ok, pr_url} ->
            {:ok, {:pr_created, pr_url}, session}

          :none ->
            agent_output = collect_agent_output(session)
            children = ChildParser.parse(agent_output)

            if agent_output != "" or children != [] do
              {:ok, {:completed_with_output, agent_output, children}, session}
            else
              check_and_continue(project, issue, session, config, turn, context)
            end
        end

      {:exit, code} ->
        Logger.warning("Agent exited with code #{code} for #{project.name}:#{issue.identifier}")

        case detect_rate_limit(session) do
          {:usage_cap, info} ->
            Logger.warning(
              "Usage cap hit for #{project.name}:#{issue.identifier}: #{info.reason}"
            )

            {:error, {:usage_cap, info}, session}

          {:rate_limited, info} ->
            Logger.warning(
              "Rate limit detected for #{project.name}:#{issue.identifier}: #{info.reason}"
            )

            {:error, {:rate_limited, info}, session}

          :not_rate_limited ->
            {:error, {:agent_exit, code}, session}
        end

      :timeout ->
        Logger.warning("Agent turn timed out for #{project.name}:#{issue.identifier}")
        BackendClient.stop_agent(config, session)
        {:error, :turn_timeout, session}
    end
  end

  defp check_and_continue(project, issue, session, config, turn, context) do
    case TrackerClient.fetch_issue_states_by_ids(project.config, project.name, [issue.id]) do
      {:ok, states} ->
        current_state = Map.get(states, issue.id)
        active = Config.active_states(project.config) |> Enum.map(&normalize_state/1)

        if current_state && normalize_state(current_state) in active do
          continuation_prompt =
            "Continue working on this issue. Check the current state and proceed."

          session_id = session.session_id

          case BackendClient.continue_agent(
                 config,
                 session_id,
                 continuation_prompt,
                 session.env_ref
               ) do
            {:ok, new_session} ->
              event_loop(project, issue, new_session, config, turn + 1, context)

            {:error, reason} ->
              {:error, reason, session}
          end
        else
          {:ok, :issue_no_longer_active, session}
        end

      {:error, _} ->
        {:ok, :state_check_failed, session}
    end
  end

  defp process_data(config, data, session) do
    lines = String.split(data, "\n", trim: true)

    Enum.reduce(lines, {session, []}, fn line, {sess, events} ->
      case BackendClient.parse_event(config, line) do
        {:ok, event} ->
          sess = if event.session_id, do: %{sess | session_id: event.session_id}, else: sess
          sess = %{sess | events: sess.events ++ [event]}
          {sess, events ++ [event]}

        :skip ->
          trimmed = String.trim(line)

          if trimmed != "" do
            stderr_event = %Synkade.Agent.Event{
              type: "stderr",
              message: trimmed,
              timestamp: DateTime.utc_now()
            }

            {sess, events ++ [stderr_event]}
          else
            {sess, events}
          end
      end
    end)
  end

  @doc "Extract a GitHub PR URL from session events."
  def extract_pr_url(session) do
    pr_regex = ~r{https://github\.com/[^/]+/[^/]+/pull/\d+}

    session.events
    |> Enum.reverse()
    |> Enum.find_value(fn event ->
      if event.message do
        case Regex.run(pr_regex, event.message) do
          [url | _] -> url
          _ -> nil
        end
      end
    end)
    |> case do
      nil -> :none
      url -> {:ok, url}
    end
  end

  defp collect_agent_output(session) do
    session.events
    |> Enum.filter(& &1.message)
    |> Enum.map(& &1.message)
    |> Enum.join("\n")
  end

  defp normalize_state(state), do: state |> String.trim() |> String.downcase()

  defp record_token_usage(events, context, config) do
    user_id = context[:user_id]
    agent_id = context[:agent_id]
    model = Config.get(config, "agent", "model") || "unknown"

    if user_id do
      for event <- events,
          event.input_tokens > 0 or event.output_tokens > 0 do
        Synkade.TokenUsage.record_usage(
          user_id,
          model,
          event.input_tokens,
          event.output_tokens,
          agent_id
        )
      end
    end
  end

  # Usage cap patterns — the plan/billing limit is exhausted, won't recover for hours/days.
  # These should trigger immediate fallback with a long cooldown.
  @usage_cap_patterns [
    "usage limit exceeded",
    "usagelimitexceeded",
    "insufficient_quota",
    "billing_hard_limit_reached",
    "credit balance is too low",
    "quota exceeded",
    "exceeded your current quota",
    "check your plan and billing"
  ]

  # Temporary rate limit patterns — too many requests per minute, recovers quickly.
  # These get a short cooldown.
  @temp_rate_limit_patterns [
    "rate_limit",
    "rate limit",
    "rate_limit_exceeded",
    "overloaded",
    "429",
    "too many requests"
  ]

  @doc """
  Detect whether a failed session was due to a rate limit or usage cap.

  Returns:
    - `{:usage_cap, info}` — plan/billing limit exhausted (long cooldown, fallback immediately)
    - `{:rate_limited, info}` — temporary rate limit (short cooldown)
    - `:not_rate_limited` — not a rate limit issue

  `info` is a map with `:reason` and optional `:retry_after_seconds`.
  """
  def detect_rate_limit(session) do
    messages =
      session.events
      |> Enum.flat_map(fn event ->
        [event.message || "", inspect(event.raw || "")]
      end)
      |> Enum.join(" ")
      |> String.downcase()

    retry_seconds = extract_retry_hint(session)

    # Check usage caps first — they're more specific and take priority
    case Enum.find(@usage_cap_patterns, &String.contains?(messages, &1)) do
      nil ->
        case Enum.find(@temp_rate_limit_patterns, &String.contains?(messages, &1)) do
          nil ->
            :not_rate_limited

          pattern ->
            {:rate_limited, %{reason: "matched pattern: #{pattern}", retry_after_seconds: retry_seconds}}
        end

      pattern ->
        {:usage_cap, %{reason: "matched pattern: #{pattern}", retry_after_seconds: retry_seconds}}
    end
  end

  # Extract retry/cooldown hints from event data.
  # Claude Code: system/api_retry events have retry_delay_ms in raw JSON.
  # Codex: rate_limits.primary.resets_in_seconds in token_count events (may be null in exec mode).
  # Codex errors: "Try again in Ns" or "Try again at <time>" in error messages.
  defp extract_retry_hint(session) do
    # Try Claude Code retry_delay_ms from api_retry events (take the max seen)
    claude_delay =
      session.events
      |> Enum.filter(fn e -> is_map(e.raw) end)
      |> Enum.map(fn e -> e.raw["retry_delay_ms"] end)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        delays -> delays |> Enum.max() |> div(1000)
      end

    # Try Codex resets_in_seconds from rate_limits in token_count or event_msg events
    codex_reset =
      session.events
      |> Enum.filter(fn e -> is_map(e.raw) end)
      |> Enum.flat_map(fn e ->
        [
          get_in(e.raw, ["rate_limits", "primary", "resets_in_seconds"]),
          get_in(e.raw, ["payload", "rate_limits", "primary", "resets_in_seconds"])
        ]
      end)
      |> Enum.reject(&is_nil/1)
      |> List.first()

    # Try parsing "Try again in Ns" from error messages
    parsed_from_text = parse_retry_from_text(session)

    # Return the most specific hint available
    codex_reset || claude_delay || parsed_from_text
  end

  @retry_in_regex ~r/try again in (\d+)\s*s/i
  @retry_in_min_regex ~r/try again in (\d+)\s*m/i

  defp parse_retry_from_text(session) do
    text =
      session.events
      |> Enum.map(fn e -> e.message || "" end)
      |> Enum.join(" ")

    cond do
      match = Regex.run(@retry_in_regex, text) ->
        String.to_integer(Enum.at(match, 1))

      match = Regex.run(@retry_in_min_regex, text) ->
        String.to_integer(Enum.at(match, 1)) * 60

      true ->
        nil
    end
  end
end
