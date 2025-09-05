defmodule Discovery.GitOps.RepoLayout do
  @moduledoc """
  Manages GitOps repository layout and file path conventions.
  Handles app-specific paths, environment overlays, and file naming.
  """

  @type app_config :: %{
          app_name: String.t(),
          environment: String.t(),
          base_path: String.t(),
          deployment_file: String.t(),
          service_file: String.t(),
          ingress_file: String.t(),
          configmap_file: String.t()
        }

  @doc """
  Gets the repository layout configuration for an app and environment.
  """
  @spec get_app_config(String.t(), String.t()) :: app_config
  def get_app_config(app_name, environment \\ "production") do
    base_path = "apps/#{app_name}"

    %{
      app_name: app_name,
      environment: environment,
      base_path: base_path,
      deployment_file: "#{base_path}/deployment.yaml",
      service_file: "#{base_path}/service.yaml",
      ingress_file: "#{base_path}/ingress.yaml",
      configmap_file: "#{base_path}/configmap.yaml"
    }
  end

  @doc """
  Gets the namespace for an app and environment.
  """
  @spec get_namespace(String.t(), String.t()) :: String.t()
  def get_namespace(app_name, environment \\ "production") do
    case environment do
      "production" -> app_name
      env -> "#{app_name}-#{env}"
    end
  end

  @doc """
  Gets the image name pattern for an app.
  """
  @spec get_image_pattern(String.t()) :: String.t()
  def get_image_pattern(app_name) do
    # Default pattern - can be configured per app
    "ghcr.io/your-org/#{app_name}"
  end

  @doc """
  Gets the commit message for an image update.
  """
  @spec get_commit_message(String.t(), String.t(), String.t()) :: String.t()
  def get_commit_message(app_name, old_tag, new_tag) do
    "feat: update #{app_name} image from #{old_tag} to #{new_tag}"
  end

  @doc """
  Gets the PR title for an image update.
  """
  @spec get_pr_title(String.t(), String.t()) :: String.t()
  def get_pr_title(app_name, new_tag) do
    "Update #{app_name} to #{new_tag}"
  end

  @doc """
  Gets the PR body for an image update.
  """
  @spec get_pr_body(String.t(), String.t(), String.t()) :: String.t()
  def get_pr_body(app_name, old_tag, new_tag) do
    """
    ## Image Update

    **App:** #{app_name}
    **Previous:** #{old_tag}
    **New:** #{new_tag}

    This PR updates the Docker image for #{app_name} to version #{new_tag}.

    ### Changes
    - Updated deployment manifest with new image tag
    - No other configuration changes

    ### Testing
    - [ ] Image builds successfully
    - [ ] Deployment is healthy
    - [ ] No breaking changes detected
    """
  end

  @doc """
  Validates if a file path is within the allowed app structure.
  """
  @spec validate_file_path(String.t(), String.t()) :: :ok | {:error, String.t()}
  def validate_file_path(app_name, file_path) do
    expected_base = "apps/#{app_name}/"

    case String.starts_with?(file_path, expected_base) do
      true -> :ok
      false -> {:error, "File path #{file_path} is not within app directory #{expected_base}"}
    end
  end

  @doc """
  Gets all file paths for an app.
  """
  @spec get_app_files(String.t()) :: [String.t()]
  def get_app_files(app_name) do
    config = get_app_config(app_name)

    [
      config.deployment_file,
      config.service_file,
      config.ingress_file,
      config.configmap_file
    ]
  end

  @doc """
  Gets the directory path for an app.
  """
  @spec get_app_directory(String.t()) :: String.t()
  def get_app_directory(app_name) do
    "apps/#{app_name}"
  end

  @doc """
  Checks if an app directory exists in the repository.
  """
  @spec app_exists?(String.t(), String.t()) :: boolean()
  def app_exists?(repo_path, app_name) do
    app_dir = Path.join(repo_path, get_app_directory(app_name))
    File.exists?(app_dir) and File.dir?(app_dir)
  end

  @doc """
  Lists all apps in the repository.
  """
  @spec list_apps(String.t()) :: [String.t()]
  def list_apps(repo_path) do
    apps_dir = Path.join(repo_path, "apps")

    case File.exists?(apps_dir) do
      true ->
        apps_dir
        |> File.ls!()
        |> Enum.filter(&File.dir?(Path.join(apps_dir, &1)))

      false ->
        []
    end
  end
end
