defmodule Synkade.Workspace.Hooks do
  @moduledoc false

  require Logger

  @spec run_hook(String.t() | nil, String.t(), keyword()) ::
          :ok | {:error, String.t()}
  def run_hook(script, workspace_path, opts \\ [])
  def run_hook(nil, _workspace_path, _opts), do: :ok

  def run_hook(script, workspace_path, opts) do
    timeout = Keyword.get(opts, :timeout_ms, 60_000)

    task =
      Task.async(fn ->
        System.cmd("sh", ["-c", script],
          cd: workspace_path,
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {output, exit_code}} ->
        {:error, "hook exited with code #{exit_code}: #{String.trim(output)}"}

      nil ->
        {:error, "hook timed out after #{timeout}ms"}
    end
  end
end
