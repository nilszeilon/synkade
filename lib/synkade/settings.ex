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

  @doc "Creates an agent."
  def create_agent(attrs) do
    result =
      %Agent{}
      |> Agent.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, agent} ->
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
