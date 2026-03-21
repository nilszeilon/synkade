defmodule Synkade.ObanTelemetry do
  @moduledoc "Broadcasts PubSub events when Oban agent jobs change state."

  require Logger

  @pubsub_topic "jobs:updates"

  def attach do
    :telemetry.attach_many(
      "synkade-oban-telemetry",
      [
        [:oban, :job, :start],
        [:oban, :job, :stop],
        [:oban, :job, :exception]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:oban, :job, event], _measurements, %{job: %{queue: "agents"}}, _config)
      when event in [:start, :stop, :exception] do
    Phoenix.PubSub.broadcast(Synkade.PubSub, @pubsub_topic, {:jobs_changed})
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok
end
