defmodule Synkade.SkillsTest do
  use Synkade.DataCase, async: true

  alias Synkade.Skills

  import Synkade.AccountsFixtures

  setup do
    user = user_fixture()
    scope = user_scope_fixture(user)
    %{user: user, scope: scope}
  end

  describe "defaults/0" do
    test "returns a list of skill maps" do
      defaults = Skills.defaults()
      assert is_list(defaults)
      assert length(defaults) > 0

      for skill <- defaults do
        assert is_binary(skill["name"])
        assert is_binary(skill["content"])
        assert skill["built_in"] == true
      end
    end

    test "includes synkade skill" do
      defaults = Skills.defaults()
      names = Enum.map(defaults, & &1["name"])
      assert "synkade" in names
    end

    test "includes live-preview skill" do
      defaults = Skills.defaults()
      names = Enum.map(defaults, & &1["name"])
      assert "live-preview" in names
    end
  end

  describe "seed_defaults/1" do
    test "creates built-in skills for user", %{user: user} do
      # seed_defaults is already called during user creation, so skills should exist
      skills = Skills.list_skills_for_user(user.id)
      assert length(skills) > 0
      assert Enum.all?(skills, & &1.built_in)
    end

    test "is idempotent", %{user: user} do
      # Already seeded during user creation; seed again
      Skills.seed_defaults(user.id)
      skills = Skills.list_skills_for_user(user.id)
      assert length(skills) == length(Skills.defaults())
    end
  end

  describe "CRUD" do
    test "list_skills/1 returns all user skills", %{scope: scope} do
      skills = Skills.list_skills(scope)
      assert length(skills) == length(Skills.defaults())
    end

    test "create_skill/2 creates a custom skill", %{scope: scope} do
      {:ok, skill} = Skills.create_skill(scope, %{"name" => "my-skill", "content" => "do stuff"})
      assert skill.name == "my-skill"
      assert skill.content == "do stuff"
      assert skill.built_in == false
    end

    test "create_skill/2 enforces unique name per user", %{scope: scope} do
      {:ok, _} = Skills.create_skill(scope, %{"name" => "unique-skill", "content" => "a"})
      {:error, changeset} = Skills.create_skill(scope, %{"name" => "unique-skill", "content" => "b"})
      assert errors_on(changeset).user_id != []
    end

    test "update_skill/3 updates a skill", %{scope: scope} do
      {:ok, skill} = Skills.create_skill(scope, %{"name" => "edit-me", "content" => "old"})
      {:ok, updated} = Skills.update_skill(scope, skill, %{"content" => "new"})
      assert updated.content == "new"
    end

    test "delete_skill/2 removes a skill", %{scope: scope} do
      {:ok, skill} = Skills.create_skill(scope, %{"name" => "delete-me", "content" => "bye"})
      {:ok, _} = Skills.delete_skill(scope, skill)
      assert_raise Ecto.NoResultsError, fn -> Skills.get_skill!(skill.id) end
    end
  end

  describe "skills_to_maps/1" do
    test "converts Skill structs to maps", %{scope: scope} do
      {:ok, skill} = Skills.create_skill(scope, %{"name" => "test", "content" => "hello"})
      [map] = Skills.skills_to_maps([skill])
      assert map == %{"name" => "test", "content" => "hello", "built_in" => false}
    end
  end
end
