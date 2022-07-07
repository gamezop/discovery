defmodule Discovery.Engine.Reader do
  @moduledoc """
  MetadataDB read operations.
  """

  alias Discovery.Utils

  @doc """
  Returns the correct socket endpoint for given app name.
  """
  @spec get_endpoint(String.t()) :: String.t()
  def get_endpoint(app_name) do
    case :ets.lookup(Utils.metadata_db(), app_name) do
      [{_room_name, deploy_info} | _t] ->
        get_latest_deployment_url(deploy_info)

      _ ->
        ""
    end
  end

  @doc """
  Returns deployments for given app name.
  """
  @spec get_deployments(String.t()) :: list()
  def get_deployments(app_name) do
    case :ets.lookup(Utils.metadata_db(), app_name) do
      [{_room_name, deployments}] ->
        deployments
        |> sort_by_date()

      _ ->
        []
    end
  end

  @spec get_latest_deployment_url(map()) :: String.t()
  defp get_latest_deployment_url(nil), do: ""

  defp get_latest_deployment_url(game_deploy_info) do
    latest_deployment =
      Map.keys(game_deploy_info)
      |> get_latest_deployment(game_deploy_info)

    game_deploy_info[latest_deployment]["url"]
  end

  defp get_latest_deployment(deploy_list, game_deploy_info) do
    deploy_list
    |> Enum.sort(fn dep1, dep2 ->
      DateTime.compare(
        game_deploy_info[dep1]["last_updated"],
        game_deploy_info[dep2]["last_updated"]
      ) === :gt
    end)
    |> List.first()
  end

  defp sort_by_date(app_deployments) do
    app_deployments
    |> Enum.sort(fn {_k1, details_a}, {_k2, details_b} ->
      DateTime.compare(
        details_a["last_updated"],
        details_b["last_updated"]
      ) === :gt
    end)
  end
end
