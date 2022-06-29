defmodule Discovery.Resources.Ingress do
  @moduledoc """
  Ingress related K8s operations
  """

  alias Discovery.Utils

  @spec get_current_ingress(any, String.t(), :all | String.t()) :: {:ok, map()} | {:error, any()}
  def get_current_ingress(conn, app_name, namespace \\ "discovery") do
    operation = K8s.Client.get(api_version(), :ingress, namespace: namespace, name: app_name)
    K8s.Client.run(conn, operation)
  end

  @spec get_current_ingress(String.t()) :: {:ok, map()} | {:error, any()}
  def get_current_ingress(app_name) do
    "minikube/discovery/#{app_name}/ingress.yml"
    |> YamlElixir.read_from_file(atoms: false)
  end

  @spec create_ingress(map()) :: {:error, any()} | {:ok, map()}
  def create_ingress(app) do
    with {:ok, map} <-
           "#{:code.priv_dir(:discovery)}/templates/ingress.yml.eex"
           |> YamlElixir.read_from_file(atoms: false),
         map <- put_in(map["apiVersion"], api_version()),
         map <- put_in(map["metadata"]["name"], app.app_name) do
      rules = map["spec"]["rules"] |> hd
      rules = put_in(rules["host"], app.app_host)
      map = put_in(map["spec"]["rules"], [rules])
      {:ok, map}
    else
      {:error, _} -> {:error, "error in setting barebones ingress file"}
    end
  end

  @spec remove_ingress_path(map, String.t()) :: map
  def remove_ingress_path(current_ingress_map, ingress_path_name) do
    rules = current_ingress_map["spec"]["rules"] |> hd
    all_paths = rules["http"]["paths"]

    new_path_list =
      all_paths
      |> Enum.filter(fn path_details ->
        path_details["backend"]["serviceName"] != ingress_path_name
      end)

    map =
      put_in(rules["http"]["paths"], new_path_list)
      |> then(fn paths -> put_in(current_ingress_map["spec"]["rules"], [paths]) end)

    map
  end

  @spec add_ingress_path(map, %{:app_name => any, :uid => any}) :: map
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

  @spec write_to_file(map) :: :ok
  def write_to_file(map) do
    Utils.to_yml(map, "priv/templates/ingress.yml")
  end

  defp api_version do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:ingress)
  end
end
