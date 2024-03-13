defmodule Discovery.Resources.Deployment do
  @moduledoc """
  Deployment related K8s operations
  """
  alias Discovery.Deploy.DeployUtils
  alias Discovery.Utils

  import Discovery.K8Config

  @template_path "#{:code.priv_dir(:discovery)}/templates/deploy.yml"

  @spec create_deployment(DeployUtils.app()) :: {:error, any()} | {:ok, map()}
  def create_deployment(app) do
    with {:ok, map} <- read_deployment_template(),
         updated_map <- update_deployment_map(map, app),
         {:ok, updated_map} <- update_container(updated_map, app),
         {:ok, final_map} <- update_labels(updated_map, app) do
      {:ok, final_map}
    else
      {:error, _} -> {:error, "error in creating deployment config"}
    end
  end

  defp read_deployment_template do
    "#{@template_path}"
    |> YamlElixir.read_from_file(atoms: false)
  end

  defp update_deployment_map(map, app) do
    map =
      map
      |> put_in(["apiVersion"], api_version(:deployment))
      |> put_in(["metadata", "name"], "#{app.app_name}-#{app.uid}")
      |> put_in(["metadata", "annotations", "app_id"], "#{app.app_name}")
      |> add_service_account()
      |> put_in(["spec", "selector", "matchLabels", "app"], "#{app.app_name}-#{app.uid}")
      |> put_in(["spec", "template", "spec", "nodeSelector"], %{
        "kubernetes.io/arch" => Application.get_env(:discovery, :kubernetes_arch)
      })
      |> put_in(["spec", "template", "spec", "imagePullSecrets"], [
        %{"name" => Application.get_env(:discovery, :image_pull_secrets)}
      ])

    {:ok, map}
  end

  defp update_container(map, app) do
    [deployment_container | _] = get_in(map, ["spec", "template", "spec", "containers"])

    deployment_container =
      deployment_container
      |> put_in(["envFrom"], [%{"configMapRef" => %{"name" => "#{app.app_name}-#{app.uid}"}}])
      |> put_in(["image"], "#{app.app_image}")
      |> put_in(["name"], "#{app.app_name}")
      |> put_in(["ports"], [
        %{
          "containerPort" => app.app_container_port,
          "name" => "#{app.app_name}-port",
          "protocol" => "TCP"
        }
      ])
      |> put_in(["resources"], resources())

    map |> put_in(["spec", "template", "spec", "containers"], [deployment_container])
  end

  defp update_labels(map, app) do
    map |> put_in(["spec", "template", "metadata", "labels", "app"], "#{app.app_name}-#{app.uid}")
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
