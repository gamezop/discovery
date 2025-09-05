# In this file, we load production configuration and secrets
# from environment variables. You can also hardcode secrets,
# although such is generally not recommended and you have to
# remember to add this file to your .gitignore.
import Config

if config_env() == :prod or config_env() == :develop do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :discovery, DiscoveryWeb.Endpoint,
    http: [
      port: String.to_integer(System.get_env("DISCOVERY_PORT")),
      transport_options: [socket_opts: [:inet6]]
    ],
    secret_key_base: secret_key_base

  # ## Using releases (Elixir v1.9+)
  #
  # If you are doing OTP releases, you need to instruct Phoenix
  # to start each relevant endpoint:
  #
  config :discovery, DiscoveryWeb.Endpoint, server: true
  #
  # Then you can assemble a release by calling `mix release`.
  # See `mix help release` for more information.
  aws_access_id = System.fetch_env!("AWS_ACCESS_KEY_ID")
  aws_access_key = System.fetch_env!("AWS_SECRET_ACCESS_KEY")
  discovery_bucket = System.fetch_env!("DISCOVERY_BUCKET")
  discovery_bucket_url = System.fetch_env!("DISCOVERY_BUCKET_URL")
  git_access_token = System.fetch_env!("GITHUB_REPO_TOKEN")

  config :ex_aws,
    access_key_id: aws_access_id,
    secret_access_key: aws_access_key

  config :discovery,
    discovery_bucket: discovery_bucket,
    discovery_bucket_url: discovery_bucket_url,
    git_access_token: git_access_token
end
