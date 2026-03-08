defmodule Synkade.Workspace.Safety do
  @moduledoc false

  @allowed_chars ~r/^[A-Za-z0-9._\-\/]+$/

  @spec sanitize_key(String.t()) :: String.t()
  def sanitize_key(key) do
    key
    |> String.replace(~r/[^A-Za-z0-9._\-\/]/, "_")
  end

  @spec validate_path_containment(String.t(), String.t()) :: :ok | {:error, String.t()}
  def validate_path_containment(workspace_path, root) do
    expanded_root = Path.expand(root)
    expanded_path = Path.expand(workspace_path)

    if String.starts_with?(expanded_path, expanded_root <> "/") or
         expanded_path == expanded_root do
      :ok
    else
      {:error, "workspace path #{expanded_path} is not under root #{expanded_root}"}
    end
  end

  @spec validate_key(String.t()) :: :ok | {:error, String.t()}
  def validate_key(key) do
    if Regex.match?(@allowed_chars, key) do
      :ok
    else
      {:error, "workspace key contains invalid characters: #{key}"}
    end
  end
end
