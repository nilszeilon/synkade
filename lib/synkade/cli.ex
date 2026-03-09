defmodule Synkade.CLI do
  @moduledoc false

  @doc "Parse CLI arguments and apply to application config."
  @spec parse_args([String.t()]) :: :ok
  def parse_args(args) do
    {opts, _rest, _} =
      OptionParser.parse(args,
        strict: [port: :integer],
        aliases: [p: :port]
      )

    if opts[:port] do
      config = Application.get_env(:synkade, SynkadeWeb.Endpoint, [])
      config = Keyword.put(config, :http, port: opts[:port])
      Application.put_env(:synkade, SynkadeWeb.Endpoint, config)
    end

    :ok
  end
end
