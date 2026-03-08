defmodule Synkade.Settings do
  @moduledoc false

  import Ecto.Query
  alias Synkade.Repo
  alias Synkade.Settings.Setting

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

  defp broadcast_update(settings) do
    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      @pubsub_topic,
      {:settings_updated, settings}
    )
  end
end
