defmodule Discovery.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Discovery.Controller.DeploymentController
  alias Discovery.Deploy.DeployManager
  alias Discovery.Engine.Builder
  alias Discovery.GitOps.GitOpsManager
  alias Discovery.Scheduler
  alias Discovery.Utils

  require Logger

  def start(_type, _args) do
    git_access_token = Application.get_env(:discovery, :git_access_token)

    children = [
      # Start the Telemetry supervisor
      DiscoveryWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Discovery.PubSub},
      # Start the Endpoint (http/https)
      DiscoveryWeb.Endpoint,
      {Builder, []},
      {DeploymentController, []},
      {DeployManager, []},
      {GitOpsManager,
       [
         repo_url: "https://github.com/ghostdsb/gitops.git",
         token: git_access_token,
         local_path: "/tmp/discovery-gitops",
         use_pr: false,
         write_layout: :env_first,
         env_root_map: %{"dev" => "dev", "staging" => "staging", "prod" => "prod"},
         base_dir_name: "base",
         file_names: %{
           deployment: "deploy.yml",
           configmap: "configmap.yml",
           secret: "secret.yml",
           service: "service.yml",
           ingress: "ingress.yml"
         }
       ]},
      Scheduler
      # Start a worker by calling: Discovery.Worker.start_link(arg)
      # {Discovery.Worker, arg}
    ]

    create_metadata_db()
    create_bridge_db()
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Discovery.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    DiscoveryWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp create_metadata_db do
    :ets.new(Utils.metadata_db(), [:set, :named_table, :public])
    Logger.info("MetadataDB created \n\n")
  end

  defp create_bridge_db do
    :ets.new(Utils.bridge_db(), [:set, :named_table, :public])
    Logger.info("BridgeDB created \n\n")
  end
end
