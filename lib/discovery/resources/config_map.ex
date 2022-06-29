defmodule Discovery.Resources.ConfigMap do
  @moduledoc """
  ConfigMap related K8s operations
  """
  alias Discovery.Utils

  @spec set_config_map(map, map) :: {:error, any()} | {:ok, map()}
  def set_config_map(app, config_map) do
    with {:ok, map} <-
           "#{:code.priv_dir(:discovery)}/templates/configmap.yml.eex"
           |> YamlElixir.read_from_file(atoms: false),
         map <- put_in(map["apiVersion"], api_version()),
         map <- put_in(map["metadata"]["name"], "#{app.app_name}-#{app.uid}"),
         map <- put_in(map["data"], config_map) do
      {:ok, map}
    else
      {:error, _} -> {:error, "error in creating configmap"}
    end
  end

  @spec write_to_file(map) :: :ok
  def write_to_file(map) do
    Utils.to_yml(map, "priv/templates/configmap.yml")
  end

  defp api_version do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:config_map)
  end
end
