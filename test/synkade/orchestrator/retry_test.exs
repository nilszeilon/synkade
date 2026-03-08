defmodule Synkade.Orchestrator.RetryTest do
  use ExUnit.Case, async: true

  alias Synkade.Orchestrator.Retry

  describe "backoff_delay_ms/2" do
    test "first attempt is 10s" do
      assert Retry.backoff_delay_ms(1, 300_000) == 10_000
    end

    test "second attempt is 20s" do
      assert Retry.backoff_delay_ms(2, 300_000) == 20_000
    end

    test "third attempt is 40s" do
      assert Retry.backoff_delay_ms(3, 300_000) == 40_000
    end

    test "caps at max_backoff" do
      assert Retry.backoff_delay_ms(10, 300_000) == 300_000
    end

    test "respects custom max_backoff" do
      assert Retry.backoff_delay_ms(5, 50_000) == 50_000
    end
  end

  describe "schedule_retry/7" do
    test "returns retry entry with timer" do
      entry = Retry.schedule_retry(self(), "api", "1", "acme/api#1", 1, 300_000, "timeout")

      assert entry.project_name == "api"
      assert entry.issue_id == "1"
      assert entry.identifier == "acme/api#1"
      assert entry.attempt == 1
      assert entry.error == "timeout"
      assert is_reference(entry.timer_handle)

      # Clean up timer
      Process.cancel_timer(entry.timer_handle)
    end
  end

  describe "schedule_continuation/4" do
    test "returns retry entry with 1s delay" do
      entry = Retry.schedule_continuation(self(), "api", "1", "acme/api#1")

      assert entry.attempt == 1
      assert entry.error == nil
      assert is_reference(entry.timer_handle)

      Process.cancel_timer(entry.timer_handle)
    end
  end
end
