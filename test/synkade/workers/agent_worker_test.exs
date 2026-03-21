defmodule Synkade.Workers.AgentWorkerTest do
  use Synkade.DataCase
  use Oban.Testing, repo: Synkade.Repo

  alias Synkade.Workers.AgentWorker

  describe "perform/1" do
    test "returns :ok when issue not found" do
      assert :ok =
               perform_job(AgentWorker, %{
                 issue_id: Ecto.UUID.generate(),
                 project_id: Ecto.UUID.generate()
               })
    end
  end
end
