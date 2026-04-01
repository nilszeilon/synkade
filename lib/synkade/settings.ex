defmodule Synkade.Settings do
  @moduledoc false

  import Ecto.Query
  alias Synkade.Repo
  alias Synkade.Settings.{Setting, Project, Agent}
  alias Synkade.Accounts.Scope

  def pubsub_topic(%Scope{user: user}), do: "settings:updates:#{user.id}"

  @doc "Returns the settings row for the scoped user, or nil if none exists."
  def get_settings(%Scope{user: user}) do
    Repo.one(from(s in Setting, where: s.user_id == ^user.id, limit: 1))
  end

  @doc "Returns the settings row for a user_id (for workers, no Scope)."
  def get_settings_for_user(user_id) do
    Repo.one(from(s in Setting, where: s.user_id == ^user_id, limit: 1))
  end

  @doc "Creates or updates the settings row for the scoped user."
  def save_settings(%Scope{user: user} = scope, attrs) do
    result =
      case get_settings(scope) do
        nil ->
          %Setting{user_id: user.id}
          |> Setting.changeset(attrs)

        existing ->
          pat_present = Map.get(attrs, "github_pat", "") != ""

          if pat_present do
            Setting.changeset(existing, attrs)
          else
            Setting.update_changeset(existing, Map.delete(attrs, "github_pat"))
          end
      end
      |> Repo.insert_or_update()

    case result do
      {:ok, settings} ->
        broadcast_update(scope, settings)
        {:ok, settings}

      error ->
        error
    end
  end

  @doc "Saves the theme preference for the scoped user."
  def save_theme(%Scope{user: user} = scope, theme) when is_binary(theme) do
    setting = get_settings(scope) || %Setting{user_id: user.id}

    result =
      setting
      |> Setting.theme_changeset(%{theme: theme})
      |> Repo.insert_or_update()

    case result do
      {:ok, setting} ->
        broadcast_theme_updated(scope, setting.theme)
        {:ok, setting}

      error ->
        error
    end
  end

  @doc "Returns a changeset for the settings form."
  def change_settings(%Scope{} = scope, setting \\ nil, attrs \\ %{}) do
    s = setting || get_settings(scope) || %Setting{}

    if s.id && Map.get(attrs, "github_pat", "") == "" do
      Setting.update_changeset(s, Map.delete(attrs, "github_pat"))
    else
      Setting.changeset(s, attrs)
    end
  end

  @doc "Returns true if the user has completed onboarding (has PAT + at least one agent)."
  def onboarding_completed?(%Scope{user: user}) do
    setting = get_settings(%Scope{user: user})
    has_pat = setting != nil and setting.github_pat != nil
    has_agent = Repo.exists?(from(a in Agent, where: a.user_id == ^user.id))
    has_pat and has_agent
  end

  # --- Projects ---

  @doc "Lists all projects for the scoped user."
  def list_projects(%Scope{user: user}) do
    Repo.all(from(p in Project, where: p.user_id == ^user.id, order_by: [asc: p.name]))
  end

  @doc "Lists enabled projects for the scoped user."
  def list_enabled_projects(%Scope{user: user}) do
    Repo.all(
      from(p in Project,
        where: p.user_id == ^user.id and p.enabled == true,
        order_by: [asc: p.name]
      )
    )
  end

  @doc "Lists enabled projects for a user_id (for workers, no Scope)."
  def list_enabled_projects_for_user(user_id) do
    Repo.all(
      from(p in Project,
        where: p.user_id == ^user_id and p.enabled == true,
        order_by: [asc: p.name]
      )
    )
  end

  @doc "Gets a single project by ID. Raises if not found."
  def get_project!(id) do
    Repo.get!(Project, id)
  end

  @doc "Gets a single project by ID. Returns nil if not found."
  def get_project(id) do
    Repo.get(Project, id)
  end

  @doc "Gets a single project by name for the scoped user."
  def get_project_by_name(%Scope{user: user}, name) do
    Repo.one(from(p in Project, where: p.user_id == ^user.id and p.name == ^name))
  end

  @doc "Creates a project for the scoped user."
  def create_project(%Scope{user: user} = scope, attrs) do
    result =
      %Project{user_id: user.id}
      |> Project.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, project} ->
        broadcast_projects_updated(scope)
        {:ok, project}

      error ->
        error
    end
  end

  @doc "Updates a project."
  def update_project(%Scope{} = scope, %Project{} = project, attrs) do
    result =
      project
      |> Project.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, project} ->
        broadcast_projects_updated(scope)
        {:ok, project}

      error ->
        error
    end
  end

  @doc "Deletes a project."
  def delete_project(%Scope{} = scope, %Project{} = project) do
    result = Repo.delete(project)

    case result do
      {:ok, project} ->
        broadcast_projects_updated(scope)
        {:ok, project}

      error ->
        error
    end
  end

  @doc "Returns a changeset for the project form."
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  @doc "Lists all projects accessible to a given agent (default agent or has assigned issues)."
  def list_agent_projects(agent_id) do
    default_projects =
      from(p in Project, where: p.default_agent_id == ^agent_id)

    assigned_projects =
      from(p in Project,
        join: i in Synkade.Issues.Issue,
        on: i.project_id == p.id,
        where: i.assigned_agent_id == ^agent_id,
        distinct: true
      )

    Repo.all(union(default_projects, ^assigned_projects))
  end

  @doc """
  Resolve an agent using the standard priority chain:
  assigned → project override → user default → first agent.

  `agents` is a list of agent structs.
  All ID args are optional (nil means skip that tier).
  """
  def resolve_agent(agents, opts \\ []) do
    agents_by_id = Map.new(agents, fn a -> {a.id, a} end)

    assigned_id = Keyword.get(opts, :assigned_agent_id)
    project_agent_id = Keyword.get(opts, :project_agent_id)
    user_default_id = Keyword.get(opts, :user_default_id)

    agents_by_id[assigned_id] ||
      agents_by_id[project_agent_id] ||
      agents_by_id[user_default_id] ||
      List.first(agents)
  end

  # --- Agents ---

  @doc "Lists all agents for the scoped user."
  def list_agents(%Scope{user: user}) do
    Repo.all(from(a in Agent, where: a.user_id == ^user.id, order_by: [asc: a.name]))
  end

  @doc "Lists all agents for a user_id (for workers, no Scope)."
  def list_agents_for_user(user_id) do
    Repo.all(from(a in Agent, where: a.user_id == ^user_id, order_by: [asc: a.name]))
  end

  @doc "Gets a single agent by ID. Raises if not found."
  def get_agent!(id) do
    Repo.get!(Agent, id)
  end

  @doc "Gets an agent by kind for the scoped user."
  def get_agent_by_kind(%Scope{user: user}, kind) do
    Repo.one(from(a in Agent, where: a.user_id == ^user.id and a.kind == ^kind))
  end

  @doc "Gets a single agent by name for the scoped user."
  def get_agent_by_name(%Scope{user: user}, name) do
    Repo.one(from(a in Agent, where: a.user_id == ^user.id and a.name == ^name))
  end

  @doc "Creates an agent with an auto-generated API token for the scoped user."
  def create_agent(%Scope{user: user} = scope, attrs) do
    result =
      %Agent{user_id: user.id}
      |> Agent.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, agent} ->
        {:ok, _plaintext} = generate_agent_token(agent)
        agent = get_agent!(agent.id)
        broadcast_agents_updated(scope)
        {:ok, agent}

      error ->
        error
    end
  end

  @doc "Creates or updates an agent (one-per-kind)."
  def upsert_agent(%Scope{} = scope, attrs) do
    kind = attrs["kind"] || attrs[:kind] || "claude"

    case get_agent_by_kind(scope, kind) do
      nil -> create_agent(scope, attrs)
      existing -> update_agent(scope, existing, attrs)
    end
  end

  @doc "Updates an agent."
  def update_agent(%Scope{} = scope, %Agent{} = agent, attrs) do
    result =
      agent
      |> Agent.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, agent} ->
        broadcast_agents_updated(scope)
        {:ok, agent}

      error ->
        error
    end
  end

  @doc "Deletes an agent."
  def delete_agent(%Scope{} = scope, %Agent{} = agent) do
    result = Repo.delete(agent)

    case result do
      {:ok, agent} ->
        broadcast_agents_updated(scope)
        {:ok, agent}

      error ->
        error
    end
  end

  @doc "Returns a changeset for the agent form."
  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    Agent.changeset(agent, attrs)
  end

  # --- Agent API Tokens ---

  @doc "Generates a new API token for an agent. Returns {:ok, plaintext_token}."
  def generate_agent_token(%Agent{} = agent) do
    plaintext = "synkade_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    hash = :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)

    result =
      agent
      |> Ecto.Changeset.change(%{api_token_hash: hash, api_token: plaintext})
      |> Repo.update()

    case result do
      {:ok, _agent} ->
        {:ok, plaintext}

      error ->
        error
    end
  end

  @doc "Verifies a plaintext token and returns the matching agent."
  def verify_agent_token(plaintext_token) do
    hash = :crypto.hash(:sha256, plaintext_token) |> Base.encode16(case: :lower)

    case Repo.one(from(a in Agent, where: a.api_token_hash == ^hash)) do
      %Agent{} = agent -> {:ok, agent}
      nil -> :error
    end
  end

  @doc "Revokes the API token for an agent."
  def revoke_agent_token(%Scope{} = scope, %Agent{} = agent) do
    result =
      agent
      |> Ecto.Changeset.change(%{api_token_hash: nil, api_token: nil})
      |> Repo.update()

    case result do
      {:ok, agent} ->
        broadcast_agents_updated(scope)
        {:ok, agent}

      error ->
        error
    end
  end

  @doc "Regenerates the API token for an agent."
  def generate_agent_token(%Scope{} = scope, %Agent{} = agent) do
    result = generate_agent_token(agent)

    case result do
      {:ok, _plaintext} ->
        broadcast_agents_updated(scope)
        result

      error ->
        error
    end
  end

  defp broadcast_theme_updated(%Scope{} = scope, theme) do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      pubsub_topic(scope),
      {:theme_updated, theme}
    )
  end

  defp broadcast_update(%Scope{} = scope, settings) do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      pubsub_topic(scope),
      {:settings_updated, settings}
    )
  end

  defp broadcast_projects_updated(%Scope{} = scope) do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      pubsub_topic(scope),
      {:projects_updated}
    )
  end

  defp broadcast_agents_updated(%Scope{} = scope) do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      pubsub_topic(scope),
      {:agents_updated}
    )
  end
end
