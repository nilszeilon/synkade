defmodule Synkade.Workers.ReconcileWorkerTest do
  use Synkade.DataCase
  use Oban.Testing, repo: Synkade.Repo

  alias Synkade.Workers.ReconcileWorker

  describe "perform/1" do
    test "completes without error" do
      assert :ok = perform_job(ReconcileWorker, %{})
    end
  end
end
