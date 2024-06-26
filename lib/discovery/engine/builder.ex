defmodule Discovery.Engine.Builder do
  @moduledoc """
  Polls k8 and process the deployment data from k8s and push to ETS, as a kv pair,
  where key will be the app id and value will be the metadata of app.
  """

  require Logger

  alias Discovery.Resources.{
    Deployment,
    Ingress
  }

  alias Discovery.Utils
  use GenServer

  @type t :: %__MODULE__{
          conn_ref: nil | map(),
          deployment_info: nil | map()
        }

  defstruct(
    conn_ref: nil,
    deployment_info: %{}
  )

  @k8_fetch_interval 5_000

  ## Client functions ##
  @spec start_link(any()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, "get-state")
  end

  def get_conn do
    GenServer.call(__MODULE__, "get-conn")
  end

  ## Server callbacks ##
  @impl true
  def init(_init_arg) do
    Logger.info("Engine builder started.")
    # create a k8 connection
    # Then start polling and building
    k8_conn_ref = connect_to_k8()
    state = __MODULE__.__struct__(conn_ref: k8_conn_ref)
    Logger.info("Initial Builder state => #{inspect(state)}")
    Process.send_after(self(), "fetch_deployment_data", @k8_fetch_interval - 2_000)
    {:ok, state}
  end

  @impl true
  def handle_call("get-state", _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call("get-conn", _from, state) do
    {:reply, state.conn_ref, state}
  end

  @impl true
  def handle_info("fetch_deployment_data", state) do
    state = %{state | deployment_info: %{}}
    updated_state = build_metadata(state)
    Process.send_after(self(), "fetch_deployment_data", @k8_fetch_interval)
    {:noreply, updated_state}
  end

  ## Utilities functions ##

  # Connects to Kubernetes
  @spec connect_to_k8() :: any()
  defp connect_to_k8 do
    Application.get_env(:discovery, :connection_method)
    |> generate_configuration()
    |> case do
      {:ok, conn_ref} ->
        Utils.puts_success("K8 connection success")
        Logger.info("K8 connection success")
        conn_ref

      {:error, reason} ->
        Utils.puts_error("Error while K8 conneciton due to #{inspect(reason)}")
        Logger.info("Error while K8 conneciton due to #{inspect(reason)}")
        # V2: Add connection retry for prod case
        nil
    end
  end

  @spec generate_configuration(String.t()) ::
          {:ok, any()} | {:error, :enoent | K8s.Conn.Error.t() | String.t()}
  defp generate_configuration(method) do
    case method do
      :service_account ->
        K8s.Conn.from_service_account()

      :kube_config ->
        K8s.Conn.from_file("~/.kube/config", context: "minikube")

      _ ->
        {:error, "connection method unavailable"}
    end
  end

  # By the end, metadata of apps will be updated in metadata_db (ETS).
  @spec build_metadata(__MODULE__.t()) :: any()
  defp build_metadata(%{conn_ref: nil} = state), do: state

  defp build_metadata(state) do
    fetch_deployment_list(state.conn_ref)
    |> update_metadata_db(state)
  end

  # Fetching the entire deployment data as a list for the namespace
  # [{Deployment_A, Deployment_B...., Deployment_N}]

  @spec fetch_deployment_list(K8s.Conn.t()) :: list(map())
  defp fetch_deployment_list(conn) do
    Deployment.fetch_k8_deployments(conn)
    |> case do
      {:ok, data} ->
        data["items"]

      {:error, reason} ->
        IO.puts("Error on fetching deployment, due to #{inspect(reason)}")
        nil
    end
  end

  # @docp """
  # Iterate through each deployment, and update the metadata for each app in metadata_db.
  # """

  @spec update_metadata_db(list(map()), __MODULE__.t()) :: __MODULE__.t()
  defp update_metadata_db([], state), do: state

  defp update_metadata_db([deployment | t], state) do
    app_id = deployment["metadata"]["annotations"]["app_id"]

    # discovery app is also deployed in the namespace hence skipping it
    deployment["metadata"]["name"]
    |> case do
      "discovery" ->
        update_metadata_db(t, state)

      _app ->
        # app |> IO.inspect()
        update_app_metadata(app_id, deployment, state)
        |> then(fn updated_state -> update_metadata_db(t, updated_state) end)
    end
  end

  # @docp """
  # Update an apps deployment info in state.deployment_info[app_id]
  # %{
  #   "app_id" => %{
  #     "app-a" => %{"last_updated" => "timestamp", "url" => "deployment url"}
  #   }
  #  }
  # """

  @spec update_app_metadata(String.t(), map(), __MODULE__.t()) :: __MODULE__.t()
  defp update_app_metadata(app_id, app_k8_data, state) do
    app_deployment_name = app_k8_data["metadata"]["name"]
    [container | _t] = app_k8_data["spec"]["template"]["spec"]["containers"]
    replicas = app_k8_data["status"]["replicas"]

    app_info =
      Map.get(state.deployment_info, app_id, %{})
      |> Map.put(
        app_deployment_name,
        %{
          "last_updated" => get_last_updated_time(app_k8_data["status"]),
          "url" => get_deployment_url(app_deployment_name, state.conn_ref),
          "image" => container["image"],
          "replicas" => replicas
        }
      )

    :ets.insert(Utils.metadata_db(), {app_id, app_info})
    state = put_in(state.deployment_info[app_id], app_info)
    # Logger.info(inspect(state.deployment_info))
    state
  end

  # @docp """
  # Returns the latest updated time of pod
  # """
  @spec get_last_updated_time(map()) :: any()
  defp get_last_updated_time(status) do
    status["conditions"]
    |> Enum.map(fn condition -> DateTime.from_iso8601(condition["lastUpdateTime"]) end)
    |> Enum.map(fn {:ok, date, _offset} -> date end)
    |> Enum.sort({:desc, DateTime})
    |> List.first()
  end

  @spec get_deployment_url(String.t(), K8s.Conn.t()) :: String.t()
  defp get_deployment_url(app_deployment_name, conn) do
    # app deployment names are always in a format [app_id]-[serial-id]
    case app_deployment_name |> String.split("-") do
      [app_id, path] ->
        Ingress.current_k8s_ingress_configuration(app_id, conn)
        |> case do
          {:ok, ingress_data} ->
            [rule | _rules] = ingress_data["spec"]["rules"]
            "#{rule["host"]}/#{path}"

          {:error, reason} ->
            IO.puts("Error on fetching ingress, due to #{inspect(reason)}")
            ""
        end

      _ ->
        ""
    end
  end
end
