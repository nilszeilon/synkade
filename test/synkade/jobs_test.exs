defmodule Synkade.JobsTest do
  use Synkade.DataCase

  import Synkade.AccountsFixtures

  alias Synkade.Jobs

  setup do
    scope = user_scope_fixture()
    %{scope: scope}
  end

  describe "get_state/1" do
    test "returns state map with expected keys", %{scope: scope} do
      state = Jobs.get_state(scope)
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
