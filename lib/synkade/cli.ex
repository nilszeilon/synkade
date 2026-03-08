defmodule Synkade.CLI do
  @moduledoc false

  @doc "Parse CLI arguments and apply to application config."
  @spec parse_args([String.t()]) :: :ok
  def parse_args(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [port: :integer],
        aliases: [p: :port]
      )

    # First positional arg is the workflow path
    workflow_path =
      case rest do
        [path | _] -> path
        [] -> nil
      end

    if workflow_path do
      Application.put_env(:synkade, :workflow_path, workflow_path)
    end

    if opts[:port] do
      config = Application.get_env(:synkade, SynkadeWeb.Endpoint, [])
      config = Keyword.put(config, :http, [port: opts[:port]])
      Application.put_env(:synkade, SynkadeWeb.Endpoint, config)
    end

    :ok
  end
end
