defmodule Synkade.Orchestrator.Retry do
  @moduledoc false

  @continuation_delay_ms 1_000

  @doc "Calculate backoff delay for a given attempt."
  @spec backoff_delay_ms(pos_integer(), pos_integer()) :: pos_integer()
  def backoff_delay_ms(attempt, max_backoff_ms) do
    delay = (10_000 * :math.pow(2, attempt - 1)) |> trunc()
    min(delay, max_backoff_ms)
  end

  @doc "Schedule an exponential backoff retry."
  @spec schedule_retry(
          pid(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer(),
          pos_integer(),
          String.t() | nil,
          String.t() | nil
        ) ::
          map()
  def schedule_retry(
        orchestrator,
        project_name,
        issue_id,
        identifier,
        attempt,
        max_backoff_ms,
        error \\ nil,
        agent_name \\ nil
      ) do
    delay = backoff_delay_ms(attempt, max_backoff_ms)
    timer_ref = Process.send_after(orchestrator, {:retry_timer, project_name, issue_id}, delay)

    %{
      project_name: project_name,
      issue_id: issue_id,
      identifier: identifier,
      attempt: attempt,
      due_at_ms: System.monotonic_time(:millisecond) + delay,
      timer_handle: timer_ref,
      error: error,
      agent_name: agent_name
    }
  end

  @doc "Schedule a continuation retry (short delay)."
  @spec schedule_continuation(pid(), String.t(), String.t(), String.t(), String.t() | nil) ::
          map()
  def schedule_continuation(orchestrator, project_name, issue_id, identifier, agent_name \\ nil) do
    timer_ref =
      Process.send_after(
        orchestrator,
        {:retry_timer, project_name, issue_id},
        @continuation_delay_ms
      )

    %{
      project_name: project_name,
      issue_id: issue_id,
      identifier: identifier,
      attempt: 1,
      due_at_ms: System.monotonic_time(:millisecond) + @continuation_delay_ms,
      timer_handle: timer_ref,
      error: nil,
      agent_name: agent_name
    }
  end

  @doc "Cancel a scheduled retry timer."
  @spec cancel_retry(map()) :: :ok
  def cancel_retry(%{timer_handle: ref}) when not is_nil(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  def cancel_retry(_), do: :ok
end
