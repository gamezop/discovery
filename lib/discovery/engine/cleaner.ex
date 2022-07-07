defmodule Discovery.Engine.Cleaner do
  @moduledoc """
  Deletes zombie deployments with lifespan more than 1hr from latest
  deployment at an interval of 1 day
  """
  alias Discovery.Bridge.BridgeUtils
  alias Discovery.Controller.DeploymentController
  alias Discovery.Engine.Reader

  require Logger

  @doc """
    get all apps
    - get all deployments
    - sort by time
    - check tail
    - delete if lifespan more than X
  """
  @spec execute :: :ok
  def execute do
    DeploymentController.get_apps()
    |> Enum.each(fn app_name ->
      app_name
      |> Reader.get_deployments()
      |> kill_zombies()
    end)
  end

  defp kill_zombies([_latest | rest] = _deployments) do
    rest
    |> Enum.each(fn {deployment_name, deployment_details} ->
      DateTime.utc_now()
      |> DateTime.diff(deployment_details["last_updated"])
      |> case do
        lifespan when lifespan > 60 * 60 ->
          Logger.info(
            "DELETED STALE DEPLOYMENT #{deployment_name}, lifespan #{lifespan / 60} mins"
          )

          BridgeUtils.delete_deployment(deployment_name)

        _ ->
          :ok
      end
    end)
  end
end
