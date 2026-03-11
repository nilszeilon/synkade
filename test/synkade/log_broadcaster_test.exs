defmodule Synkade.LogBroadcasterTest do
  use ExUnit.Case, async: false

  alias Synkade.LogBroadcaster

  require Logger

  test "topic/0 returns the PubSub topic" do
    assert LogBroadcaster.topic() == "logs:stream"
  end

  test "recent_entries/0 returns a list" do
    entries = LogBroadcaster.recent_entries()
    assert is_list(entries)
  end

  test "logging broadcasts to PubSub subscribers" do
    Phoenix.PubSub.subscribe(Synkade.PubSub, LogBroadcaster.topic())

    Logger.warning("test log broadcaster message")

    assert_receive {:log_entry, entry}, 1000
    assert entry.level == :warning
    assert entry.message =~ "test log broadcaster message"
    assert %DateTime{} = entry.timestamp
  end

  test "entries appear in recent_entries after logging" do
    Logger.warning("broadcaster recent entry test")

    Process.sleep(50)

    entries = LogBroadcaster.recent_entries()
    assert Enum.any?(entries, &(&1.message =~ "broadcaster recent entry test"))
  end

  test "entries have expected shape" do
    Phoenix.PubSub.subscribe(Synkade.PubSub, LogBroadcaster.topic())

    # Test config sets logger level to :warning, so use warning level
    Logger.warning("shape test message")

    assert_receive {:log_entry, entry}, 1000
    assert is_integer(entry.id)
    assert entry.level == :warning
    assert is_binary(entry.message)
    assert %DateTime{} = entry.timestamp
  end
end
