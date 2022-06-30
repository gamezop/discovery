defmodule Discovery.Deploy.DeployUtils do
  @moduledoc """
  Includes handles all the utilities for CRUD operations of app deployments
  """
  alias Discovery.Deploy.DeployUtils
  alias Discovery.Engine.Builder
  alias Discovery.Utils

  alias Discovery.Resources.{
    ConfigMap,
    Deployment,
    Ingress,
    Service
  }

  require Logger

  @root_dir "minikube/discovery/"

  @type t :: %DeployUtils{
          app_name: String.t(),
          app_image: String.t(),
          config_map: map(),
          app_host: String.t(),
          app_target_port: number(),
          app_container_port: number()
        }

  @type app :: %{
          app_name: String.t(),
          app_image: String.t(),
          uid: String.t(),
          config_map: map(),
          app_host: String.t(),
          app_target_port: number(),
          app_container_port: number()
        }

  defstruct(
    app_name: "",
    app_image: "",
    app_host: "",
    config_map: %{},
    app_target_port: 4000,
    app_container_port: 4000
  )

  @doc """
  Creates or updates an app deployment

  Returns :ok | {:error, reason}
  """
  @spec create(DeployUtils.t()) :: {:ok, term()} | {:error, term()}
  def create(deployment_details) do
    uid = Utils.get_uid()

    app_details = %{
      app_name: deployment_details.app_name,
      app_image: deployment_details.app_image,
      uid: uid,
      config_map: deployment_details.config_map,
      app_host: deployment_details.app_host,
      app_target_port: deployment_details.app_target_port,
      app_container_port: deployment_details.app_container_port
    }

    with :ok <- create_app_folder(app_details.app_name),
         {:ok, _ingress} <- create_ingress(app_details),
         :ok <- create_app_version_folder(app_details),
         {:ok, _configmap} <- create_configmap(app_details),
         {:ok, _deployment} <- create_deployment(app_details),
         {:ok, _service} <- create_service(app_details) do
      Utils.puts_success("SUCCESFULLY DEPLOYED: #{app_details.app_image}")

      {:ok,
       %{
         deployment: "#{app_details.app_name}-#{app_details.uid}",
         image: "#{app_details.app_image}"
       }}
    end
  end

  @spec create_namespace_directory :: :ok
  def create_namespace_directory do
    if File.exists?("minikube/discovery/namespace.yml") do
      Utils.puts_warn("NAMESPACE DIRECTORY EXISTS")
    else
      File.mkdir_p!(Path.dirname("minikube/discovery/namespace.yml"))
      namespace_template = File.read!("#{:code.priv_dir(:discovery)}/templates/namespace.yml")
      File.write!("minikube/discovery/namespace.yml", namespace_template)
      Utils.puts_warn("RUNNING NAMESPACE: discovery")
    end
  end

  @spec create_app_folder(String.t()) :: :ok | {:error, term()}
  defp create_app_folder(app_name) do
    if File.dir?(@root_dir <> app_name) do
      :ok
    else
      File.mkdir("minikube/discovery/#{app_name}")
    end
  end

  @spec create_app_folder(app()) :: :ok | {:error, term()}
  defp create_app_version_folder(app) do
    File.mkdir("minikube/discovery/#{app.app_name}/#{app.app_name}-#{app.uid}")
  end

  @spec create_ingress(app()) :: {:ok, map()} | {:error, term()}
  defp create_ingress(app) do
    with {:ok, {ingress_status, ingress}} <- Ingress.fetch_configuration(app),
         updated_ingress <- Ingress.add_ingress_path(ingress, app),
         {:ok, resource_location} <- Ingress.resource_file(app),
         :ok <- Ingress.write_to_file(updated_ingress, resource_location),
         :ok <- apply_ingress(ingress_status, resource_location) do
      {:ok, updated_ingress}
    end
  end

  defp apply_ingress(:new_ingress, resource_location) do
    run_resource(resource_location)
  end

  defp apply_ingress(:old_ingress, resource_location) do
    patch_resource(resource_location)
  end

  @spec create_configmap(app()) :: {:ok, map()} | {:error, term()}
  defp create_configmap(app) do
    with {:ok, config_map} <- ConfigMap.set_config_map(app),
         {:ok, resource_location} <- ConfigMap.resource_file(app),
         :ok <- ConfigMap.write_to_file(config_map, resource_location),
         :ok <- run_resource(resource_location) do
      {:ok, config_map}
    end
  end

  @spec create_deployment(app()) :: {:ok, map()} | {:error, term()}
  defp create_deployment(app) do
    with {:ok, deployment} <- Deployment.create_deployment(app),
         {:ok, resource_location} <- Deployment.resource_file(app),
         :ok <- Deployment.write_to_file(deployment, resource_location),
         :ok <- run_resource(resource_location) do
      {:ok, deployment}
    end
  end

  @spec create_service(app()) :: {:ok, map()} | {:error, term()}
  defp create_service(app) do
    with {:ok, service} <- Service.create_service(app),
         {:ok, resource_location} <- Service.resource_file(app),
         :ok <- Service.write_to_file(service, resource_location),
         :ok <- run_resource(resource_location) do
      {:ok, service}
    end
  end

  @spec run_resource(String.t()) :: :ok | {:error, String.t()}
  defp run_resource(resource) do
    Utils.puts_warn("RUNNING RESOURCE: #{resource}")

    with conn when not is_nil(conn) <- Builder.get_conn(),
         {:ok, resource_map} <- K8s.Resource.from_file(resource),
         operation <- K8s.Client.create(resource_map),
         {:ok, _} <- K8s.Client.run(conn, operation) do
      Utils.puts_success("SUCCESS: #{resource}")
      :ok
    else
      nil ->
        Logger.error("no K8s connection found")
        Utils.puts_error("ERROR IN APPLYING RESOURCE: #{resource}")
        {:error, "error in applying #{resource}"}

      {:error, error} ->
        Logger.error(error)
        Utils.puts_error("ERROR IN APPLYING RESOURCE: #{resource}")
        {:error, "error in applying #{resource}"}
    end
  end

  @spec patch_resource(String.t()) :: :ok | {:error, String.t()}
  defp patch_resource(resource) do
    Utils.puts_warn("RUNNING RESOURCE: #{resource}")

    with conn when not is_nil(conn) <- Builder.get_conn(),
         {:ok, resource_map} <- K8s.Resource.from_file(resource),
         operation <- K8s.Client.patch(resource_map),
         {:ok, _} <- K8s.Client.run(conn, operation) do
      Utils.puts_success("SUCCESS: #{resource}")
      :ok
    else
      nil ->
        Logger.error("no K8s connection found")
        Utils.puts_error("ERROR IN APPLYING RESOURCE: #{resource}")
        {:error, "error in applying #{resource}"}

      {:error, error} ->
        Logger.error(error)
        Utils.puts_error("ERROR IN PATCHING RESOURCE: #{resource}")
        {:error, "error in patching #{resource}"}
    end
  end
end
