defmodule Synkade.JobsTest do
  use Synkade.DataCase

  alias Synkade.Jobs

  describe "get_state/0" do
    test "returns state map with expected keys" do
      state = Jobs.get_state()
      assert is_map(state.projects)
      assert is_map(state.running)
      assert is_map(state.retry_attempts)
    end
  end

  describe "running_for_project/1" do
    test "returns 0 when no jobs running" do
      assert Jobs.running_for_project(Ecto.UUID.generate()) == 0
    end
  end
end
