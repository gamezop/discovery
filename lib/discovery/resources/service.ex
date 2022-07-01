defmodule Discovery.Resources.Service do
  @moduledoc """
  Service related K8s operations
  """
  alias Discovery.Deploy.DeployUtils
  alias Discovery.Utils

  import Discovery.K8Config

  @spec create_service(DeployUtils.app()) :: {:error, any()} | {:ok, map()}
  def create_service(app) do
    with {:ok, map} <-
           "#{:code.priv_dir(:discovery)}/templates/service.yml"
           |> YamlElixir.read_from_file(atoms: false),
         map <- put_in(map["apiVersion"], api_version(:service)),
         map <- put_in(map, ["metadata", "name"], "#{app.app_name}-#{app.uid}"),
         map <- put_in(map, ["spec", "selector", "app"], "#{app.app_name}-#{app.uid}") do
      port_data = map["spec"]["ports"] |> hd
      port_data = put_in(port_data["name"], "#{app.app_name}-service-port")
      port_data = put_in(port_data["targetPort"], app.app_target_port)

      map = put_in(map, ["spec", "ports"], [port_data])
      {:ok, map}
    else
      {:error, _} -> {:error, "error in creating service config"}
    end
  end

  @spec write_to_file(map, String.t()) :: :ok
  def write_to_file(map, location) do
    Utils.to_yml(map, location)
  end

  @spec resource_file(DeployUtils.app() | DeployUtils.del_deployment()) ::
          {:ok, String.t()} | {:error, String.t()}
  def resource_file(app) do
    case File.cwd() do
      {:ok, cwd} ->
        {:ok, cwd <> "/minikube/discovery/#{app.app_name}/#{app.app_name}-#{app.uid}/service.yml"}

      _ ->
        {:error, "no read permission"}
    end
  end

  @spec delete_operation(String.t()) :: K8s.Operation.t()
  def delete_operation(name) do
    K8s.Client.delete(api_version(:service), "Service", namespace: namespace(), name: name)
  end
end
