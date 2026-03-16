import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :synkade, Synkade.Repo,
  database: Path.expand("../synkade_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool_size: 1,
  pool: Ecto.Adapters.SQL.Sandbox,
  journal_mode: :wal,
  busy_timeout: 5000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :synkade, SynkadeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "SnUzKajXYEYYKabUSnbRjF/pKQiihxgZ3PeIVXnQRIdekwHIEAaK1VdsSlo3mF3I",
  server: false

# In test we don't send emails
config :synkade, Synkade.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Cloak vault config for field encryption (test-only key)
config :synkade, Synkade.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("dVBuNmtoYXhxNHd5N3FqZGtncjM2aGRrdmZ0cWh5YmE=")}
  ]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
