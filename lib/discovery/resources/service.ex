defmodule Discovery.Resources.Service do
  @moduledoc """
  Service related K8s operations
  """

  @spec create_service(map) :: {:error, any()} | {:ok, map()}
  def create_service(app) do
    with {:ok, map} <-
           "#{:code.priv_dir(:discovery)}/templates/service.yml.eex"
           |> YamlElixir.read_from_file(atoms: false),
         map <- put_in(map["apiVersion"], api_version()),
         map <- put_in(map["metadata"]["name"], "#{app.app_name}-#{app.uid}"),
         map <- put_in(map["spec"]["selector"]["app"], "#{app.app_name}-#{app.uid}") do
      port_data = map["spec"]["ports"] |> hd
      port_data = put_in(port_data["name"], "#{app.app_name}-service-port")
      port_data = put_in(port_data["targetPort"], app.app_target_port)

      map = put_in(map["spec"]["ports"], [port_data])
      {:ok, map}
    else
      {:error, _} -> {:error, "error in creating service config"}
    end
  end

  defp api_version do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:service)
  end
end
