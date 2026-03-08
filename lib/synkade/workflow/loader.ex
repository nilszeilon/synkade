defmodule Synkade.Workflow.Loader do
  @moduledoc false

  @type workflow :: %{config: map(), prompt_template: String.t()}

  @spec load(String.t()) :: {:ok, workflow()} | {:error, atom() | {atom(), String.t()}}
  def load(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, :enoent} -> {:error, :missing_workflow_file}
      {:error, reason} -> {:error, {:missing_workflow_file, to_string(reason)}}
    end
  end

  @spec parse(String.t()) :: {:ok, workflow()} | {:error, atom() | {atom(), String.t()}}
  def parse(content) do
    case split_front_matter(content) do
      {:ok, yaml_str, body} ->
        case parse_yaml(yaml_str) do
          {:ok, config} when is_map(config) ->
            {:ok, %{config: config, prompt_template: String.trim(body)}}

          {:ok, _non_map} ->
            {:error, :workflow_front_matter_not_a_map}

          {:error, reason} ->
            {:error, {:workflow_parse_error, reason}}
        end

      :no_front_matter ->
        {:ok, %{config: %{}, prompt_template: String.trim(content)}}
    end
  end

  defp split_front_matter(content) do
    lines = String.split(content, "\n")

    case lines do
      ["---" | rest] ->
        find_closing_fence(rest, [])

      _ ->
        :no_front_matter
    end
  end

  defp find_closing_fence([], _acc), do: :no_front_matter

  defp find_closing_fence([line | rest], acc) do
    if String.match?(line, ~r/^---\s*$/) do
      yaml_str = acc |> Enum.reverse() |> Enum.join("\n")
      body = Enum.join(rest, "\n")
      {:ok, yaml_str, body}
    else
      find_closing_fence(rest, [line | acc])
    end
  end

  defp parse_yaml(""), do: {:ok, %{}}

  defp parse_yaml(yaml_str) do
    if String.trim(yaml_str) == "" do
      {:ok, %{}}
    else
      case YamlElixir.read_from_string(yaml_str) do
        {:ok, result} ->
          {:ok, result}

        {:error, reason} ->
          msg =
            if is_struct(reason) and Map.has_key?(reason, :message) do
              reason.message
            else
              to_string(reason)
            end

          {:error, msg}
      end
    end
  end
end
