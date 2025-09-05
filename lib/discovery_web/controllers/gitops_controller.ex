defmodule DiscoveryWeb.GitOpsController do
  use DiscoveryWeb, :controller
  alias Discovery.GitOps.GitOpsManager

  @doc """
  Updates an app's image tag in the GitOps repository.
  """
  @spec update_image(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update_image(conn, params) do
    update_params = %{
      app_name: [type: :string, required: true],
      new_tag: [type: :string, required: true],
      environment: [type: :string, default: "production"]
    }

    with {:ok, params} <- Tarams.cast(params, update_params),
         {:ok, result} <-
           GitOpsManager.update_app_image(params.app_name, params.new_tag, params.environment) do
      json(conn, %{
        success: true,
        message: "Successfully updated #{params.app_name} to #{params.new_tag}",
        data: result
      })
    else
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Failed to update image: #{reason}"
        })
    end
  end

  @doc """
  Creates a new app in the GitOps repository.
  """
  @spec create_app(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_app(conn, params) do
    create_params = %{
      app_name: [type: :string, required: true],
      image_name: [type: :string, required: true],
      environment: [type: :string, default: "production"]
    }

    with {:ok, params} <- Tarams.cast(params, create_params),
         {:ok, result} <-
           GitOpsManager.create_app(params.app_name, params.image_name, params.environment) do
      json(conn, %{
        success: true,
        message: "Successfully created app #{params.app_name}",
        data: result
      })
    else
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Failed to create app: #{reason}"
        })
    end
  end

  @doc """
  Lists all apps in the GitOps repository.
  """
  @spec list_apps(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_apps(conn, _params) do
    case GitOpsManager.list_apps() do
      {:ok, apps} ->
        json(conn, %{
          success: true,
          data: %{apps: apps}
        })

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Failed to list apps: #{reason}"
        })
    end
  end

  @doc """
  Gets the current image tag for an app.
  """
  @spec get_image_tag(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get_image_tag(conn, params) do
    tag_params = %{
      app_name: [type: :string, required: true],
      environment: [type: :string, default: "production"]
    }

    with {:ok, params} <- Tarams.cast(params, tag_params),
         {:ok, tag} <- GitOpsManager.get_app_image_tag(params.app_name, params.environment) do
      json(conn, %{
        success: true,
        data: %{
          app_name: params.app_name,
          environment: params.environment,
          current_tag: tag
        }
      })
    else
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Failed to get image tag: #{reason}"
        })
    end
  end

  @doc """
  Syncs the entire Discovery state to the GitOps repository.
  """
  @spec sync_to_gitops(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sync_to_gitops(conn, params) do
    sync_params = %{
      commit_message: [type: :string, default: "Sync Discovery deployment state to GitOps"]
    }

    with {:ok, params} <- Tarams.cast(params, sync_params),
         {:ok, result} <- GitOpsManager.sync_to_gitops(params.commit_message) do
      json(conn, %{
        success: true,
        message: "Successfully synced to GitOps",
        data: result
      })
    else
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Failed to sync to GitOps: #{reason}"
        })
    end
  end

  @doc """
  Syncs a specific app's deployment to the GitOps repository.
  """
  @spec sync_app_to_gitops(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sync_app_to_gitops(conn, params) do
    sync_params = %{
      app_name: [type: :string, required: true],
      commit_message: [type: :string, default: nil]
    }

    with {:ok, params} <- Tarams.cast(params, sync_params),
         {:ok, result} <- GitOpsManager.sync_app_to_gitops(params.app_name, params.commit_message) do
      json(conn, %{
        success: true,
        message: "Successfully synced #{params.app_name} to GitOps",
        data: result
      })
    else
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Failed to sync app to GitOps: #{reason}"
        })
    end
  end

  @doc """
  Syncs the entire minikube/discovery folder to the GitOps repository.
  """
  @spec sync_from_discovery_to_gitops(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sync_from_discovery_to_gitops(conn, params) do
    sync_params = %{
      commit_message: [type: :string, default: "Sync Discovery state to GitOps"]
    }

    with {:ok, params} <- Tarams.cast(params, sync_params),
         {:ok, result} <- GitOpsManager.sync_from_discovery_to_gitops(params.commit_message) do
      json(conn, %{
        success: true,
        message: "Successfully synced Discovery state to GitOps",
        data: result
      })
    else
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Failed to sync from Discovery to GitOps: #{reason}"
        })
    end
  end

  @doc """
  Syncs a specific app from minikube/discovery to the GitOps repository.
  """
  @spec sync_app_from_discovery_to_gitops(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sync_app_from_discovery_to_gitops(conn, params) do
    sync_params = %{
      app_name: [type: :string, required: true],
      commit_message: [type: :string, default: nil]
    }

    with {:ok, params} <- Tarams.cast(params, sync_params),
         {:ok, result} <-
           GitOpsManager.sync_app_from_discovery_to_gitops(params.app_name, params.commit_message) do
      json(conn, %{
        success: true,
        message: "Successfully synced #{params.app_name} from Discovery to GitOps",
        data: result
      })
    else
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          success: false,
          error: "Failed to sync app from Discovery to GitOps: #{reason}"
        })
    end
  end
end
