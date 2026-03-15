defmodule Synkade.Settings do
  @moduledoc false

  import Ecto.Query
  alias Synkade.Repo
  alias Synkade.Settings.{Setting, Project, Agent}

  @pubsub_topic "settings:updates"

  def pubsub_topic, do: @pubsub_topic

  @doc "Returns the settings row, or nil if none exists."
  def get_settings do
    Repo.one(from(s in Setting, limit: 1))
  end

  @doc "Returns the settings row, or raises if none exists."
  def get_settings! do
    Repo.one!(from(s in Setting, limit: 1))
  end

  @doc "Creates or updates the single settings row (upsert)."
  def save_settings(attrs) do
    result =
      case get_settings() do
        nil -> %Setting{}
        existing -> existing
      end
      |> Setting.changeset(attrs)
      |> Repo.insert_or_update()

    case result do
      {:ok, settings} ->
        broadcast_update(settings)
        {:ok, settings}

      error ->
        error
    end
  end

  @doc "Saves the theme preference."
  def save_theme(theme) when is_binary(theme) do
    setting = get_settings() || %Setting{}

    result =
      setting
      |> Setting.theme_changeset(%{theme: theme})
      |> Repo.insert_or_update()

    case result do
      {:ok, setting} ->
        broadcast_theme_updated(setting.theme)
        {:ok, setting}

      error ->
        error
    end
  end

  @doc "Returns a changeset for the settings form."
  def change_settings(setting \\ nil, attrs \\ %{}) do
    (setting || get_settings() || %Setting{})
    |> Setting.changeset(attrs)
  end

  # --- Projects ---

  @doc "Lists all projects."
  def list_projects do
    Repo.all(from(p in Project, order_by: [asc: p.name]))
  end

  @doc "Lists enabled projects."
  def list_enabled_projects do
    Repo.all(from(p in Project, where: p.enabled == true, order_by: [asc: p.name]))
  end

  @doc "Gets a single project by ID. Raises if not found."
  def get_project!(id) do
    Repo.get!(Project, id)
  end

  @doc "Gets a single project by name."
  def get_project_by_name(name) do
    Repo.get_by(Project, name: name)
  end

  @doc "Creates a project."
  def create_project(attrs) do
    result =
      %Project{}
      |> Project.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, project} ->
        broadcast_projects_updated()
        {:ok, project}

      error ->
        error
    end
  end

  @doc "Updates a project."
  def update_project(%Project{} = project, attrs) do
    result =
      project
      |> Project.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, project} ->
        broadcast_projects_updated()
        {:ok, project}

      error ->
        error
    end
  end

  @doc "Deletes a project."
  def delete_project(%Project{} = project) do
    result = Repo.delete(project)

    case result do
      {:ok, project} ->
        broadcast_projects_updated()
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

  # --- Agents ---

  @doc "Lists all agents."
  def list_agents do
    Repo.all(from(a in Agent, order_by: [asc: a.name]))
  end

  @doc "Gets a single agent by ID. Raises if not found."
  def get_agent!(id) do
    Repo.get!(Agent, id)
  end

  @doc "Gets a single agent by name."
  def get_agent_by_name(name) do
    Repo.get_by(Agent, name: name)
  end

  @doc "Creates an agent with an auto-generated API token."
  def create_agent(attrs) do
    result =
      %Agent{}
      |> Agent.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, agent} ->
        {:ok, _plaintext} = generate_agent_token(agent)
        agent = get_agent!(agent.id)
        broadcast_agents_updated()
        {:ok, agent}

      error ->
        error
    end
  end

  @doc "Updates an agent."
  def update_agent(%Agent{} = agent, attrs) do
    result =
      agent
      |> Agent.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, agent} ->
        broadcast_agents_updated()
        {:ok, agent}

      error ->
        error
    end
  end

  @doc "Deletes an agent."
  def delete_agent(%Agent{} = agent) do
    result = Repo.delete(agent)

    case result do
      {:ok, agent} ->
        broadcast_agents_updated()
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
        broadcast_agents_updated()
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
  def revoke_agent_token(%Agent{} = agent) do
    result =
      agent
      |> Ecto.Changeset.change(%{api_token_hash: nil, api_token: nil})
      |> Repo.update()

    case result do
      {:ok, agent} ->
        broadcast_agents_updated()
        {:ok, agent}

      error ->
        error
    end
  end

  defp broadcast_theme_updated(theme) do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      @pubsub_topic,
      {:theme_updated, theme}
    )
  end

  defp broadcast_update(settings) do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      @pubsub_topic,
      {:settings_updated, settings}
    )
  end

  defp broadcast_projects_updated do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      @pubsub_topic,
      {:projects_updated}
    )
  end

  defp broadcast_agents_updated do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      @pubsub_topic,
      {:agents_updated}
    )
  end
end
