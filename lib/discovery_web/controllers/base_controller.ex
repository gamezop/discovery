defmodule DiscoveryWeb.BaseController do
  use DiscoveryWeb, :controller

  alias Discovery.Bridge.BridgeUtils

  @spec list_app(Plug.Conn.t(), any) :: Plug.Conn.t()
  def list_app(conn, _params) do
    app_list = BridgeUtils.get_apps()
    json(conn, %{apps: app_list})
  end

  @list_app_deployments_params %{
    app_name: [type: :string, required: true]
  }
  @spec list_app_deployments(any, map) :: Plug.Conn.t()
  def list_app_deployments(conn, params) do
    with {:ok, params} <- Tarams.cast(params, @list_app_deployments_params),
         deployment_data <- BridgeUtils.get_deployment_data(params.app_name) do
      json(conn, %{deployment_data: deployment_data})
    else
      {:error, _} -> json(put_status(conn, 400), "error")
    end
  end

  @create_app_params %{
    app_name: [type: :string, required: true]
  }
  @spec create_app(Plug.Conn.t(), map) :: Plug.Conn.t()
  def create_app(conn, params) do
    with {:ok, params} <- Tarams.cast(params, @create_app_params),
         {:ok, :app_inserted} <- BridgeUtils.create_app(params.app_name) do
      json(conn, params)
    else
      {:error, reason} -> json(put_status(conn, 400), reason)
    end
  end

  @deploy_build_params %{
    app_name: [type: :string, required: true],
    app_image: [type: :string, required: true],
    config_map: [type: :map, required: true],
    app_host: [type: :string, required: true],
    app_target_port: [type: :integer, default: 4000],
    app_container_port: [type: :integer, default: 4000]
  }
  @spec deploy_build(Plug.Conn.t(), map) :: Plug.Conn.t()
  def deploy_build(conn, params) do
    with {:ok, params} <- Tarams.cast(params, @deploy_build_params),
         {:ok, response} <- BridgeUtils.create_deployment(params) do
      json(conn, response)
    else
      {:error, reason} -> json(put_status(conn, 400), reason)
    end
  end

  @delete_app_params %{
    app_name: [type: :string, required: true]
  }
  @spec delete_app(Plug.Conn.t(), map) :: Plug.Conn.t()
  def delete_app(conn, params) do
    with {:ok, params} <- Tarams.cast(params, @delete_app_params) do
      json(conn, params)
    else
      {:error, _} -> json(put_status(conn, 400), "error")
    end
  end

  @delete_deployment_params %{
    deployment_name: [type: :string, required: true]
  }
  @spec delete_deployment(Plug.Conn.t(), map) :: Plug.Conn.t()
  def delete_deployment(conn, params) do
    with {:ok, params} <- Tarams.cast(params, @delete_deployment_params) do
      json(conn, params)
    else
      {:error, _} -> json(put_status(conn, 400), "error")
    end
  end
end
