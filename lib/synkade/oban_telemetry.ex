defmodule Synkade.ObanTelemetry do
  @moduledoc "Broadcasts PubSub events when Oban agent jobs change state."

  require Logger

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

  def handle_event([:oban, :job, event], _measurements, %{job: %{queue: "agents"} = job}, _config)
      when event in [:start, :stop, :exception] do
    # Look up user_id from the project in the job args
    project_id = job.args["project_id"]

    if project_id do
      case Synkade.Settings.get_project(project_id) do
        %{user_id: user_id} ->
          topic = Synkade.Jobs.pubsub_topic(user_id)
          Phoenix.PubSub.broadcast(Synkade.PubSub, topic, {:jobs_changed})

        _ ->
          :ok
      end
    end
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok
end
