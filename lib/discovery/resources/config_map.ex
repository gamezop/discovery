defmodule Discovery.Resources.ConfigMap do
  @moduledoc """
  ConfigMap related K8s operations
  """
  alias Discovery.Deploy.DeployUtils
  alias Discovery.Utils

  import Discovery.K8Config

  @spec set_config_map(DeployUtils.app()) :: {:error, any()} | {:ok, map()}
  def set_config_map(app) do
    with {:ok, map} <-
           "#{:code.priv_dir(:discovery)}/templates/configmap.yml"
           |> YamlElixir.read_from_file(atoms: false),
         map <- put_in(map["apiVersion"], api_version(:config_map)),
         map <- put_in(map, ["metadata", "name"], "#{app.app_name}-#{app.uid}"),
         map <- put_in(map["data"], stringify(app.config_map)) do
      {:ok, map}
    else
      {:error, _} -> {:error, "error in creating configmap"}
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
        {:ok,
         cwd <> "/minikube/discovery/#{app.app_name}/#{app.app_name}-#{app.uid}/configmap.yml"}

      _ ->
        {:error, "no read permission"}
    end
  end

  @spec delete_operation(String.t()) :: K8s.Operation.t()
  def delete_operation(name) do
    K8s.Client.delete(api_version(:config_map), "ConfigMap", namespace: namespace(), name: name)
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
    |> Enum.map(fn {key, val} -> {key, stringify(val)} end)
    |> Map.new()
  end

  defp stringify(val) when is_bitstring(val), do: "\"#{val}\""
  defp stringify(val), do: to_string(val)
end
