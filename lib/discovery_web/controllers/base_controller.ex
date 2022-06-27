defmodule DiscoveryWeb.BaseController do
  use DiscoveryWeb, :controller

  alias Discovery.Bridge.BridgeUtils

  def list_app(conn, _params) do
    app_list =
      BridgeUtils.get_apps()
      |> Enum.map(fn app ->
        Map.put(
          app,
          :url,
          "https://dev-discoveryk8.skillclash.com/api/get-endpoint?app_name=#{app[:app_name]}"
        )
      end)

    json(conn, %{apps: app_list})
  end

  def list_app_deployments(conn, %{"app" => app_name}) do
    deployment_data = BridgeUtils.get_deployment_data(app_name)
    json(conn, %{deployment_data: deployment_data})
  end

  def create_app(conn, params) do
    # params |> IO.inspect(label: "create_app params")
    json(conn, :ok)
  end

  def deploy_build(conn, params) do
    # params |> IO.inspect(label: "deploy_build params")
    json(conn, :ok)
  end

  def delete_app(conn, params) do
    # params |> IO.inspect(label: "delete_app params")
    json(conn, :ok)
  end

  def delete_deployment(conn, params) do
    # params |> IO.inspect(label: "delete_deployment params")
    json(conn, :ok)
  end
end
