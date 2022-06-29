defmodule Discovery.Resources.Deployment do
  @moduledoc """
  Deployment related K8s operations
  """

  alias Discovery.Utils

  @spec create_deployment(map) :: {:error, any()} | {:ok, map()}
  def create_deployment(app) do
    with {:ok, map} <-
           "#{:code.priv_dir(:discovery)}/templates/deploy.yml.eex"
           |> YamlElixir.read_from_file(atoms: false),
         map <- put_in(map["apiVersion"], api_version()),
         map <- put_in(map["metadata"]["name"], "#{app.app_name}-#{app.uid}"),
         map <- put_in(map["metadata"]["annotations"]["app_id"], "#{app.app_name}"),
         map <-
           put_in(map["spec"]["selector"]["matchLabels"]["app"], "#{app.app_name}-#{app.uid}"),
         map <-
           put_in(
             map["spec"]["template"]["metadata"]["labels"]["app"],
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

  @spec write_to_file(map) :: :ok
  def write_to_file(map) do
    Utils.to_yml(map, "priv/templates/configmap.yml")
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

  defp api_version do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:deployment)
  end
end