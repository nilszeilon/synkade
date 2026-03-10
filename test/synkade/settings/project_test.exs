defmodule Synkade.Settings.ProjectTest do
  use Synkade.DataCase, async: true

  alias Synkade.Settings.Project

  describe "changeset/2" do
    test "valid with just a name" do
      changeset = Project.changeset(%Project{}, %{name: "my-project"})
      assert changeset.valid?
    end

    test "requires name" do
      changeset = Project.changeset(%Project{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "accepts name and tracker_repo" do
      changeset =
        Project.changeset(%Project{}, %{
          name: "my-project",
          tracker_repo: "acme/repo"
        })

      assert changeset.valid?
    end

    test "defaults enabled to true" do
      changeset = Project.changeset(%Project{}, %{name: "p"})
      assert Ecto.Changeset.get_field(changeset, :enabled) == true
    end
  end
end
