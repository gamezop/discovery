defmodule Discovery.K8Config do
  @moduledoc """
  For getting common K8 configs
  """

  @spec namespace :: String.t()
  def namespace do
    Application.get_env(:discovery, :namespace)
  end

  @spec service_account :: String.t()
  def service_account do
    Application.get_env(:discovery, :service_account)
  end

  @spec api_version(:config_map | :deployment | :ingress | :namespace | :service) :: String.t()
  def api_version(:service) do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:service)
  end

  def api_version(:ingress) do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:ingress)
  end

  def api_version(:deployment) do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:deployment)
  end

  def api_version(:config_map) do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:config_map)
  end

  def api_version(:namespace) do
    Application.get_env(:discovery, :api_version)
    |> Keyword.get(:namespace)
  end
end
