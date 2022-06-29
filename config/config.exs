# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the endpoint
config :discovery, DiscoveryWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "g1PHdlhOK+iqbT8lX0iVWGra5tUPixVmSD752nswvRja0x1NLeqGEeSJdOR3/UVS",
  render_errors: [view: DiscoveryWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Discovery.PubSub,
  live_view: [signing_salt: "0tLW2WSY"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :discovery,
  # Connection method for K8s
  # available methods
  #   - :kube_config
  #   - :service_account
  connection_method: :kube_config,
  # The namespace to watch for Namespaced CRDs.
  # Defaults to "default". `:all` for all namespaces
  namespace: "discovery",
  # Name must only consist of only lowercase letters and hyphens.
  # Defaults to hyphenated mix app name
  service_account: "discovery-sa",
  # Operator deployment resources. These are the defaults.
  resources: %{
    limits: %{cpu: "500m", memory: "500Mi"},
    requests: %{cpu: "100m", memory: "300Mi"}
  },
  image_pull_secrets: "dockerhub-auth-discovery"

config :discovery, :api_version,
  config_map: "v1",
  deployment: "apps/v1",
  ingress: "networking.k8s.io/v1beta1",
  namespace: "v1",
  service: "v1"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
