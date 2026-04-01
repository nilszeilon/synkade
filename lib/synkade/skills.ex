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
    [synkade(), live_preview()]
  end

  ## Conversion for config/writer

  def skills_to_maps(skills) do
    Enum.map(skills, fn %Skill{} = s ->
      %{"name" => s.name, "content" => s.content, "built_in" => s.built_in}
    end)
  end

  ## Built-in skill definitions

  defp synkade do
    %{
      "name" => "synkade",
      "built_in" => true,
      "content" => """
      ---
      name: synkade
      description: Git workflow, Synkade API, status reporting, and pull-based agent protocol
      user-invocable: false
      allowed-tools: Bash(git *), Bash(gh *), Bash(curl *)
      ---

      ## Git & Pull Requests

      You have a `GITHUB_TOKEN` environment variable. After making changes, commit and open a PR:

      ```bash
      git checkout -b fix/short-description
      git add -A && git commit -m "Description of changes"
      gh pr create --title "Short title" --body "Description"
      ```

      Always create a PR with your changes so they can be reviewed.

      ## Synkade API

      Environment variables: `$SYNKADE_API_URL`, `$SYNKADE_API_TOKEN`.

      ```bash
      # List issues for this project
      curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" \\
        "$SYNKADE_API_URL/issues?project_id=PROJECT_ID"

      # Create an issue
      curl -s -X POST "$SYNKADE_API_URL/issues" \\
        -H "Authorization: Bearer $SYNKADE_API_TOKEN" \\
        -H "Content-Type: application/json" \\
        -d '{"project_id":"PROJECT_ID","body":"# Title\\n\\nDetails"}'

      # Update an issue
      curl -s -X PATCH "$SYNKADE_API_URL/issues/<issue_id>" \\
        -H "Authorization: Bearer $SYNKADE_API_TOKEN" \\
        -H "Content-Type: application/json" \\
        -d '{"state":"done"}'

      # Read issue history
      curl -s -H "Authorization: Bearer $SYNKADE_API_TOKEN" \\
        "$SYNKADE_API_URL/issues/<issue_id>"
      ```

      ## Status Reporting

      Send heartbeats every 2-3 minutes during long tasks to prevent stall detection:

      ```bash
      curl -s -X POST "$SYNKADE_API_URL/heartbeat" \\
        -H "Authorization: Bearer $SYNKADE_API_TOKEN" \\
        -H "Content-Type: application/json" \\
        -d '{"issue_id":"<issue_id>","status":"working","message":"Brief status"}'
      ```

      Valid statuses: `working`, `error`, `blocked`.

      ## Follow-Up Issues

      When you discover out-of-scope work (bugs, tech debt, follow-ups), create issues rather than scope-creeping:

      ```bash
      curl -s -X POST "$SYNKADE_API_URL/issues" \\
        -H "Authorization: Bearer $SYNKADE_API_TOKEN" \\
        -H "Content-Type: application/json" \\
        -d '{"project_id":"PROJECT_ID","body":"# Issue Title\\n\\nDescription"}'
      ```

      """
    }
  end

  defp live_preview do
    %{
      "name" => "live-preview",
      "built_in" => true,
      "content" => """
      ---
      name: live-preview
      description: Expose a dev server running in this worktree via the Sprite's public URL
      user-invocable: false
      allowed-tools: Bash(socat *), Bash(kill *), Bash(lsof *), Bash(nohup *), Bash(npm *), Bash(pnpm *), Bash(yarn *), Bash(npx *), Bash(python *), Bash(mix *)
      ---

      ## Live Preview

      When this project has a dev server (web frontend, API, etc.), you can expose it
      to the user via the Sprite's public URL. The Sprite routes all HTTP traffic
      arriving at port **8080** to `https://<sprite-name>-<org>.sprites.dev/`.

      Your preview URL is available in `$SPRITE_PREVIEW_URL` (empty when running locally).

      ### How it works

      Multiple worktrees share a single Sprite. Each runs its dev server on a
      **different port**. A `socat` forwarder on port 8080 points to whichever
      worktree the user wants to preview. You control which one is active.

      ### Step-by-step

      1. **Start the dev server** on any free port (not 8080):

         ```bash
         # Pick a deterministic port from the issue id to avoid collisions
         PORT=$((30000 + ($RANDOM % 30000)))
         # Example: Next.js
         nohup npm run dev -- --port $PORT > /tmp/dev-server.log 2>&1 &
         DEV_PID=$!
         echo "Dev server PID=$DEV_PID on port $PORT"
         ```

         Adapt the command to the project's framework (vite, next, mix phx.server, etc.).

      2. **Wait for the server to be ready** before forwarding:

         ```bash
         for i in $(seq 1 30); do
           curl -s http://localhost:$PORT > /dev/null && break
           sleep 1
         done
         ```

      3. **Forward port 8080 → your dev server port**:

         ```bash
         # Kill any existing forwarder on 8080
         lsof -ti :8080 | xargs -r kill -9 2>/dev/null || true
         # Start socat forwarder
         nohup socat TCP-LISTEN:8080,fork,reuseaddr TCP:localhost:$PORT > /tmp/socat.log 2>&1 &
         SOCAT_PID=$!
         echo "Forwarding 8080 → $PORT (socat PID=$SOCAT_PID)"
         ```

      4. **Report the preview URL** so the user can open it:

         ```bash
         echo "Preview: $SPRITE_PREVIEW_URL"
         ```

         Also include the URL in your heartbeat messages so it shows in the dashboard:

         ```bash
         curl -s -X POST "$SYNKADE_API_URL/heartbeat" \\
           -H "Authorization: Bearer $SYNKADE_API_TOKEN" \\
           -H "Content-Type: application/json" \\
           -d '{"issue_id":"<issue_id>","status":"working","message":"Preview live at '$SPRITE_PREVIEW_URL'"}'
         ```

      5. **Cleanup** when done — stop the forwarder and dev server:

         ```bash
         kill $SOCAT_PID $DEV_PID 2>/dev/null || true
         ```

      ### Important notes

      - **Only one worktree can own port 8080 at a time.** Your `lsof | kill` in step 3
        takes over from whoever had it before. This is expected — the user requested
        your branch.
      - If `socat` is not installed, install it: `apt-get update && apt-get install -y socat`
      - If `$SPRITE_PREVIEW_URL` is empty, you are running on the local backend —
        just print `http://localhost:$PORT` instead.
      - The Sprite URL requires authentication by default (org members + API tokens).
        The user can make it public from the Synkade settings if needed.
      """
    }
  end
end
