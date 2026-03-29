defmodule Synkade.Agent.Codex do
  @moduledoc "Model fetching for OpenAI Codex CLI agent."

  def fetch_models(api_key) do
    headers = [{"authorization", "Bearer #{api_key}"}]

    case Req.get("https://api.openai.com/v1/models",
           headers: headers,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        items =
          models
          |> Enum.filter(fn m ->
            id = m["id"]
            # Filter to models useful for coding — skip embeddings, tts, dall-e, whisper, etc.
            not String.contains?(id, ["embedding", "tts", "dall-e", "whisper", "moderation"])
          end)
          |> Enum.sort_by(& &1["id"])
          |> Enum.map(fn m -> {m["id"], m["id"]} end)

        {:ok, items}

      {:ok, %{status: status}} ->
        {:error, "OpenAI API returned #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
