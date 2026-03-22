defmodule Synkade.Skills do
  @moduledoc false

  import Ecto.Query
  alias Synkade.Repo
  alias Synkade.Skills.Skill

  ## CRUD

  def list_skills(%{user: user}), do: list_skills_for_user(user.id)

  def list_skills_for_user(user_id) do
    Skill
    |> where(user_id: ^user_id)
    |> order_by(:name)
    |> Repo.all()
  end

  def get_skill!(id), do: Repo.get!(Skill, id)

  def create_skill(%{user: user}, attrs) do
    %Skill{user_id: user.id}
    |> Skill.changeset(attrs)
    |> Repo.insert()
  end

  def update_skill(_scope, %Skill{} = skill, attrs) do
    skill
    |> Skill.changeset(attrs)
    |> Repo.update()
  end

  def delete_skill(_scope, %Skill{} = skill) do
    Repo.delete(skill)
  end

  def change_skill(%Skill{} = skill, attrs \\ %{}) do
    Skill.changeset(skill, attrs)
  end

  ## Defaults / seeding

  def seed_defaults(user_id) do
    now = DateTime.utc_now(:second)

    for default <- defaults() do
      Repo.insert!(
        %Skill{
          user_id: user_id,
          name: default["name"],
          content: default["content"],
          built_in: true,
          inserted_at: now,
          updated_at: now
        },
        on_conflict: :nothing,
        conflict_target: [:user_id, :name]
      )
    end

    :ok
  end

  def defaults do
    [synkade_create_issues()]
  end

  ## Conversion for config/writer

  def skills_to_maps(skills) do
    Enum.map(skills, fn %Skill{} = s ->
      %{"name" => s.name, "content" => s.content, "built_in" => s.built_in}
    end)
  end

  ## Built-in skill definitions

  defp synkade_create_issues do
    %{
      "name" => "synkade-create-issues",
      "built_in" => true,
      "content" => """
      ---
      name: synkade-create-issues
      description: Create follow-up issues on the Synkade board for future work discovered during this task
      user-invocable: false
      allowed-tools: Bash(curl *)
      ---

      When you discover work that is out of scope for your current task — bugs, tech debt,
      missing tests, follow-up features — create a follow-up issue on the Synkade board.

      **When to create issues:**
      - Bugs you notice but shouldn't fix in this PR
      - Tech debt that should be addressed separately
      - Follow-up tasks that logically come after this work
      - Missing test coverage outside your current scope

      **How to create an issue:**
      ```bash
      curl -s -X POST "$SYNKADE_API_URL/issues" \\
        -H "Authorization: Bearer $SYNKADE_API_TOKEN" \\
        -H "Content-Type: application/json" \\
        -d '{
          "project_id": "PROJECT_ID",
          "body": "# Issue Title\\n\\nDescription of the work needed."
        }'
      ```

      The `SYNKADE_API_URL` and `SYNKADE_API_TOKEN` environment variables are available.

      Keep your current task focused. Create issues for tangential work rather than scope-creeping.
      """
    }
  end
end
