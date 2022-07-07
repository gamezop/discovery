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

  @type del_deployment :: %{
          app_name: String.t(),
          uid: String.t()
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
         {:ok, _ing_map} <- create_ingress(app_details),
         :ok <- create_app_version_folder(app_details),
         {:ok, _cfg_map} <- create_configmap(app_details),
         {:ok, _dpl_map} <- create_deployment(app_details),
         {:ok, _svc_map} <- create_service(app_details) do
      Utils.puts_success("SUCCESFULLY DEPLOYED: #{app_details.app_image}")

      {:ok,
       %{
         deployment: "#{app_details.app_name}-#{app_details.uid}",
         image: "#{app_details.app_image}"
       }}
    end
  end

  @spec delete_app_deployment(del_deployment()) :: {:ok, term()} | {:error, term()}
  def delete_app_deployment(app_details) do
    name = "#{app_details.app_name}-#{app_details.uid}"

    with {:ok, _} <- delete_service(name),
         {:ok, _} <- delete_deployment(name),
         {:ok, _} <- delete_configmap(name),
         {:ok, _} <- delete_app_version_folder(app_details),
         {:ok, _} <- delete_path_from_ingress(app_details) do
      Utils.puts_success("SUCCESFULLY DELETED: #{name}")
      {:ok, %{deleted: "#{name}"}}
    end
  end

  # TO-DO REFACTOR ME
  @spec delete_app(binary) :: {:ok, [binary]} | {:error, atom, binary}
  def delete_app(app_name) do
    conn = Builder.get_conn()

    Ingress.get_ingress_services(conn, app_name)
    |> Enum.each(fn app ->
      delete_service(app)
      delete_deployment(app)
      delete_configmap(app)
    end)

    Ingress.delete_operation(app_name)
    |> delete_resource(app_name)

    File.rm_rf("minikube/discovery/#{app_name}")
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

  @spec delete_app_version_folder(del_deployment()) :: {:ok, list()} | {:error, String.t()}
  defp delete_app_version_folder(app) do
    File.rm_rf("minikube/discovery/#{app.app_name}/#{app.app_name}-#{app.uid}")
    |> case do
      {:ok, list} ->
        {:ok, list}

      {:error, reason, _} ->
        {:error, "error in deleting folder #{app.app_name}-#{app.uid}: #{reason}"}
    end
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

  @spec delete_path_from_ingress(del_deployment()) :: {:ok, map()} | {:error, term()}
  defp delete_path_from_ingress(app) do
    with {:ok, {ingress_status, ingress}} <- Ingress.fetch_configuration(app),
         updated_ingress <- Ingress.remove_ingress_path(ingress, app),
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

  @spec delete_configmap(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp delete_configmap(name) do
    with operation <- ConfigMap.delete_operation(name),
         :ok <- delete_resource(operation, name) do
      {:ok, "configmap #{name} deleted"}
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

  @spec delete_deployment(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp delete_deployment(name) do
    with operation <- Deployment.delete_operation(name),
         :ok <- delete_resource(operation, name) do
      {:ok, "deployment #{name} deleted"}
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

  @spec delete_service(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp delete_service(name) do
    with operation <- Service.delete_operation(name),
         :ok <- delete_resource(operation, name) do
      {:ok, "service #{name} deleted"}
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

  @spec delete_resource(K8s.Operation.t(), String.t()) :: :ok | {:error, String.t()}
  defp delete_resource(del_operation, name) do
    Utils.puts_warn("DELETING RESOURCE: #{name}")

    with conn when not is_nil(conn) <- Builder.get_conn(),
         {:ok, _} <- K8s.Client.run(conn, del_operation) do
      Utils.puts_success("DELETED: #{name}")
      :ok
    else
      nil ->
        Logger.error("no K8s connection found")
        Utils.puts_error("ERROR IN DELETING RESOURCE: #{name}")
        {:error, "error in deleting #{name}"}

      {:error, error} ->
        Logger.error(error)
        Utils.puts_error("ERROR IN DELETING RESOURCE: #{name}")
        {:error, "error in deleting #{name}"}
    end
  end
end
