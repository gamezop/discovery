defmodule Discovery.Bridge.BridgeUtils do
  @moduledoc """
  Manages the communications of liveview with the backend.
  """
  alias Discovery.Controller.DeploymentController
  alias Discovery.Deploy.DeployManager
  alias Discovery.Deploy.DeployUtils

  @doc """
  Fetches the deployment data of an app from metadatadb ets

  Returns list()
  """
  @spec get_deployment_data(String.t()) :: list
  def get_deployment_data(app_name) do
    app_name
    |> DeploymentController.get_deployment_data()
    |> Enum.map(fn {name, value} -> Map.put(value, "name", name) end)
    |> Enum.sort(fn dep1, dep2 ->
      DateTime.compare(dep1["last_updated"], dep2["last_updated"]) === :gt
    end)
  end

  @doc """
  Fetches list of all apps deleted so far from bridgedb ets

  Returns list()
  """
  @spec get_apps :: list
  def get_apps do
    DeploymentController.get_apps()
    |> Enum.map(fn app_name ->
      deployment_count =
        app_name
        |> get_deployment_data()
        |> Enum.count()

      %{
        app_name: app_name,
        deployments: deployment_count,
        url: "#{Application.get_env(:discovery, :base_url)}/api/get-endpoint?app_name=#{app_name}"
      }
    end)
  end

  @doc """
  Inserts the app name into bridgedb ets

  Returns {:ok, :app_inserted} | {:error, :app_present}
  """
  @spec create_app(String.t()) :: {:ok, :app_inserted} | {:error, :app_present}
  def create_app(app_name) do
    app_name
    |> DeploymentController.insert_app()
  end

  @doc """
  Deletes
  - app name from bridgedb ets
  - app from metadatadb ets
  - deletes k8s resources
  - deletes app folder in minikube/namespace
  """
  @spec delete_app(String.t()) :: {:ok, list()} | {:error, binary(), any()}
  def delete_app(app_name) do
    app_name
    |> DeploymentController.delete_app()
  end

  @doc """
  Creates or updates an app deployment

  Returns {:ok, term} | {:error, reason}
  """
  @spec create_deployment(DeployUtils.t()) :: {:ok, term()} | {:error, term()}
  def create_deployment(deployment_details) do
    deployment_details
    |> DeployManager.create()
  end

  @doc """
  Deletes an app deployment

  Returns {:ok, term} | {:error, reason}
  """
  @spec delete_deployment(String.t()) :: {:ok, term()} | {:error, term()}
  def delete_deployment(deployment_name) do
    [app_name, uid] =
      deployment_name
      |> String.split("-")

    DeployManager.delete(%{app_name: app_name, uid: uid})
  end
end
