defmodule Discovery.Resources.Deployment do
  @moduledoc """
  Deployment related K8s operations
  """
  alias Discovery.Deploy.DeployUtils
  alias Discovery.Utils

  import Discovery.K8Config

  @spec create_deployment(DeployUtils.app()) :: {:error, any()} | {:ok, map()}
  def create_deployment(app) do
    with {:ok, map} <-
           "#{:code.priv_dir(:discovery)}/templates/deploy.yml"
           |> YamlElixir.read_from_file(atoms: false),
         map <- put_in(map["apiVersion"], api_version(:deployment)),
         map <- put_in(map, ["metadata", "name"], "#{app.app_name}-#{app.uid}"),
         map <- put_in(map, ["metadata", "annotations", "app_id"], "#{app.app_name}"),
         map <- add_service_account(map),
         map <-
           put_in(map, ["spec", "selector", "matchLabels", "app"], "#{app.app_name}-#{app.uid}"),
         map <-
           put_in(map, ["spec", "template", "spec", "imagePullSecrets"], [
             %{"name" => Application.get_env(:discovery, :image_pull_secrets)}
           ]),
         map <-
           put_in(
             map,
             ["spec", "template", "metadata", "labels", "app"],
             "#{app.app_name}-#{app.uid}"
           ) do
      deployment_container = map["spec"]["template"]["spec"]["containers"] |> hd

      deployment_container =
        put_in(deployment_container["envFrom"], [
          %{
            "configMapRef" => %{"name" => "#{app.app_name}-#{app.uid}"}
          }
        ])

      deployment_container = put_in(deployment_container["image"], "#{app.app_image}")
      deployment_container = put_in(deployment_container["name"], "#{app.app_name}")

      deployment_container =
        put_in(deployment_container["ports"], [
          %{
            "containerPort" => app.app_container_port,
            "name" => "#{app.app_name}-port",
            "protocol" => "TCP"
          }
        ])

      deployment_container = put_in(deployment_container["resources"], resources())

      map = put_in(map["spec"]["template"]["spec"]["containers"], [deployment_container])

      {:ok, map}
    else
      {:error, _} -> {:error, "error in creating deployment config"}
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
        {:ok, cwd <> "/minikube/discovery/#{app.app_name}/#{app.app_name}-#{app.uid}/deploy.yml"}

      _ ->
        {:error, "no read permission"}
    end
  end

  @spec fetch_k8_deployments(K8s.Conn.t()) :: {:error, any()} | {:ok, map}
  def fetch_k8_deployments(conn) do
    operation = K8s.Client.list(api_version(:deployment), "Deployment", namespace: namespace())
    K8s.Client.run(conn, operation)
  end

  @spec delete_operation(String.t()) :: K8s.Operation.t()
  def delete_operation(name) do
    K8s.Client.delete(api_version(:deployment), "Deployment", namespace: namespace(), name: name)
  end

  @spec add_service_account(map()) :: map()
  defp add_service_account(map) do
    if Application.get_env(:discovery, :use_service_account) do
      put_in(map["spec"]["template"]["spec"]["serviceAccountName"], service_account())
    else
      spec = Map.delete(map["spec"]["template"]["spec"], "serviceAccountName")
      put_in(map["spec"]["template"]["spec"], spec)
    end
  end

  defp resources do
    Application.get_env(:discovery, :resources)
    |> stringify()
  end

  defp stringify(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> stringify()
    |> List.to_tuple()
  end

  defp stringify(list) when is_list(list) do
    list
    |> Enum.map(fn val -> stringify(val) end)
  end

  defp stringify(map) when is_map(map) do
    map
    |> Enum.map(fn {key, val} -> {stringify(key), stringify(val)} end)
    |> Map.new()
  end

  defp stringify(val), do: to_string(val)
end
