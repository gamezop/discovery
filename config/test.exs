import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :discovery, DiscoveryWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

config :ex_aws, :s3,
  scheme: "http://",
  region: "ap-south-1",
  host: "localhost",
  port: 4566

config :ex_aws,
  access_key_id: "secret",
  secret_access_key: "secret"
