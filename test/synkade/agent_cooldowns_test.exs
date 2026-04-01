defmodule Synkade.AgentCooldownsTest do
  use ExUnit.Case, async: true

  alias Synkade.AgentCooldowns

  setup do
    # Each test uses a unique agent_id to avoid ETS conflicts
    %{agent_id: Ecto.UUID.generate()}
  end

  describe "set_cooldown/2 and cooled_down?/1" do
    test "agent is cooled down after set_cooldown", %{agent_id: id} do
      AgentCooldowns.set_cooldown(id, 60)
      assert AgentCooldowns.cooled_down?(id)
    end

    test "agent is not cooled down when no cooldown set", %{agent_id: id} do
      refute AgentCooldowns.cooled_down?(id)
    end

    test "expired cooldown returns false", %{agent_id: id} do
      # Set cooldown that expires immediately (0 seconds in the past)
      expires_at = DateTime.add(DateTime.utc_now(), -1, :second)
      :ets.insert(:agent_cooldowns, {id, expires_at})

      refute AgentCooldowns.cooled_down?(id)
    end
  end

  describe "clear_cooldown/1" do
    test "clears an active cooldown", %{agent_id: id} do
      AgentCooldowns.set_cooldown(id, 60)
      assert AgentCooldowns.cooled_down?(id)

      AgentCooldowns.clear_cooldown(id)
      refute AgentCooldowns.cooled_down?(id)
    end
  end

  describe "list_cooldowns/0" do
    test "returns only active cooldowns" do
      active_id = Ecto.UUID.generate()
      expired_id = Ecto.UUID.generate()

      AgentCooldowns.set_cooldown(active_id, 60)

      expired_at = DateTime.add(DateTime.utc_now(), -10, :second)
      :ets.insert(:agent_cooldowns, {expired_id, expired_at})

      cooldowns = AgentCooldowns.list_cooldowns()
      ids = Enum.map(cooldowns, fn {id, _} -> id end)

      assert active_id in ids
      refute expired_id in ids
    end
  end
end
