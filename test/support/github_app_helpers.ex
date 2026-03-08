defmodule Synkade.Test.GitHubAppHelpers do
  @moduledoc false

  @doc "Generate an RSA private key PEM for testing."
  def generate_test_private_key do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_type, pem} = JOSE.JWK.to_pem(key)
    pem
  end
end
