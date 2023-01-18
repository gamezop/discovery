import Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :discovery, DiscoveryWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task:
#
#     mix phx.gen.cert
#
# Note that this task requires Erlang/OTP 20 or later.
# Run `mix help phx.gen.cert` for more information.
#
# The `http:` config above can be replaced with:
#
#     https: [
#       port: 4001,
#       cipher_suite: :strong,
#       keyfile: "priv/cert/selfsigned_key.pem",
#       certfile: "priv/cert/selfsigned.pem"
#     ],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Watch static and templates for browser reloading.
config :discovery, DiscoveryWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/discovery_web/(live|views)/.*(ex)$",
      ~r"lib/discovery_web/templates/.*(eex)$"
    ]
  ]

# uncomment for testing on localhost for quizzop question upload module
config :ex_aws, :s3,
  scheme: "http://",
  region: "ap-south-1",
  host: "localhost",
  port: 4566

config :discovery,
  discovery_bucket: "dev-discovery",
  discovery_bucket_url: "https://dev-discovery.gamezop.com"

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :discovery, :base_url, "http://localhost:4000"

config :discovery,
  connection_method: :kube_config,
  namespace: "discovery",
  service_account: "discovery-service-account",
  resources: %{
    limits: %{cpu: "500m", memory: "500Mi"},
    requests: %{cpu: "100m", memory: "300Mi"}
  },
  image_pull_secrets: "ghostdsb-auth-discovery",
  use_external_ingress_class: false,
  use_service_account: true
