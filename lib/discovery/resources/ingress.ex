defmodule Discovery.Resources.Ingress do
  @moduledoc """
  Ingress related K8s operations
  """

  alias Discovery.Deploy.DeployUtils
  alias Discovery.Engine.Builder
  alias Discovery.Utils

  @spec fetch_configuration(DeployUtils.app() | DeployUtils.del_deployment()) ::
          {:error, any()} | {:ok, {atom(), map()}}
  def fetch_configuration(app) do
    File.exists?("minikube/discovery/#{app.app_name}/ingress.yml")
    |> if do
      current_ingress_configuration(app.app_name)
    else
      create_ingress_configuration(app)
    end
  end

  @spec add_ingress_path(map, DeployUtils.app()) :: map
  def add_ingress_path(current_ingress_map, app) do
    new_path = %{
      "path" => "/#{app.uid}(/|$)(.*)",
      "backend" => %{
        "serviceName" => "#{app.app_name}-#{app.uid}",
        "servicePort" => 80
      }
    }

    rules = current_ingress_map["spec"]["rules"] |> hd
    all_paths = rules["http"]["paths"] -- [nil]
    new_path_list = all_paths ++ [new_path]

    map =
      put_in(rules["http"]["paths"], new_path_list)
      |> then(fn paths -> put_in(current_ingress_map["spec"]["rules"], [paths]) end)

    map
  end

  @spec remove_ingress_path(map, DeployUtils.del_deployment()) :: map
  def remove_ingress_path(current_ingress_map, app) do
    rules = current_ingress_map["spec"]["rules"] |> hd
    all_paths = rules["http"]["paths"]

    new_path_list =
      all_paths
      |> Enum.filter(fn path_details ->
        path_details["backend"]["serviceName"] != "#{app.app_name}-#{app.uid}"
      end)

    map =
      put_in(rules["http"]["paths"], new_path_list)
      |> then(fn paths -> put_in(current_ingress_map["spec"]["rules"], [paths]) end)

    map
  end

  @spec write_to_file(map, String.t()) :: :ok
  def write_to_file(map, location) do
    Utils.to_yml(map, location)
  end

  @spec resource_file(DeployUtils.app() | DeployUtils.del_deployment()) ::
          {:ok, String.t()} | {:error, String.t()}
  def resource_file(app) do
    case File.cwd() do
      {:ok, cwd} -> {:ok, cwd <> "/minikube/discovery/#{app.app_name}/ingress.yml"}
      _ -> {:error, "no read permission"}
    end
  end

  @doc """
  - Checks k8s for the presence of ingress.
  - Not used in the project, but should figure out a way to use this for checking ingress

  Discrepancies happen when
  - we delete app folder with ingress file, but ingress present in k8s
  - we delete ingress from k8s but ingress file present in app folder
  """
  @spec current_k8s_ingress_configuration(String.t()) ::
          {:ok, map()} | {:error, any()}
  def current_k8s_ingress_configuration(app_name) do
    conn = Builder.get_conn()
    operation = K8s.Client.get(api_version(), :ingress, namespace: namespace(), name: app_name)
    K8s.Client.run(conn, operation)
  end

  @spec delete_operation(String.t()) :: K8s.Operation.t()
  def delete_operation(name) do
    K8s.Client.delete(api_version(), "Ingress", namespace: "discovery", name: name)
  end

  @spec current_ingress_configuration(String.t()) :: {:ok, {atom(), map()}} | {:error, String.t()}
  defp current_ingress_configuration(app_name) do
    "minikube/discovery/#{app_name}/ingress.yml"
    |> YamlElixir.read_from_file(atoms: false)
    |> case do
      {:ok, ingress} -> {:ok, {:old_ingress, ingress}}
      {:error, _} -> {:error, "error in reading from yml"}
    end
  end

  @spec create_ingress_configuration(DeployUtils.app()) ::
          {:error, any()} | {:ok, {atom(), map()}}
  defp create_ingress_configuration(app) do
    with {:ok, map} <-
           "#{:code.priv_dir(:discovery)}/templates/ingress.yml"
           |> YamlElixir.read_from_file(atoms: false),
         map <- put_in(map["apiVersion"], api_version()),
         map <- put_in(map["metadata"]["name"], app.app_name) do
      rules = map["spec"]["rules"] |> hd
      rules = put_in(rules["host"], app.app_host)
      map = put_in(map["spec"]["rules"], [rules])
      {:ok, {:new_ingress, map}}
    else
      {:error, _} -> {:error, "error in setting barebones ingress file"}
    end
  end

  defp api_version do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:ingress)
  end

  defp namespace do
    Application.get_env(:discovery, :namespace)
  end
end
