defmodule Discovery.GitOps.ImageUpdater do
  @moduledoc """
  Updates Docker image tags in Kubernetes deployment manifests.
  Handles YAML parsing, image tag replacement, and validation.
  """

  require Logger
  alias Discovery.GitOps.RepoLayout
  alias Discovery.Utils

  @type update_result :: {:ok, map()} | {:error, String.t()}

  @doc """
  Updates the image tag in a deployment manifest.
  """
  @spec update_image_tag(String.t(), String.t(), String.t(), String.t()) :: update_result
  def update_image_tag(repo_path, app_name, new_tag, environment \\ "production") do
    config = RepoLayout.get_app_config(app_name, environment)

    with {:ok, content} <- read_deployment_file(repo_path, config.deployment_file),
         {:ok, updated_content} <- replace_image_tag(content, new_tag),
         :ok <- validate_yaml(updated_content),
         :ok <- write_deployment_file(repo_path, config.deployment_file, updated_content) do
      Logger.info("Successfully updated #{app_name} image to #{new_tag}")
      {:ok, %{app_name: app_name, new_tag: new_tag, file: config.deployment_file}}
    end
  end

  @doc """
  Gets the current image tag from a deployment manifest.
  """
  @spec get_current_image_tag(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def get_current_image_tag(repo_path, app_name, environment \\ "production") do
    config = RepoLayout.get_app_config(app_name, environment)

    with {:ok, content} <- read_deployment_file(repo_path, config.deployment_file),
         {:ok, parsed} <- parse_yaml(content),
         {:ok, tag} <- extract_image_tag(parsed) do
      {:ok, tag}
    end
  end

  @doc """
  Creates a new deployment manifest for an app.
  """
  @spec create_deployment_manifest(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          update_result
  def create_deployment_manifest(
        repo_path,
        app_name,
        image_name,
        tag,
        environment \\ "production"
      ) do
    config = RepoLayout.get_app_config(app_name, environment)
    namespace = RepoLayout.get_namespace(app_name, environment)

    manifest = generate_deployment_manifest(app_name, image_name, tag, namespace)

    with :ok <- validate_yaml(manifest),
         :ok <- write_deployment_file(repo_path, config.deployment_file, manifest) do
      Logger.info("Successfully created deployment manifest for #{app_name}")
      {:ok, %{app_name: app_name, file: config.deployment_file}}
    end
  end

  # Private helper functions

  defp read_deployment_file(repo_path, file_path) do
    full_path = Path.join(repo_path, file_path)

    case File.read(full_path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, "Deployment file not found: #{file_path}"}
      {:error, reason} -> {:error, "Failed to read deployment file: #{inspect(reason)}"}
    end
  end

  defp write_deployment_file(repo_path, file_path, content) do
    full_path = Path.join(repo_path, file_path)

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(full_path))

    case File.write(full_path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to write deployment file: #{inspect(reason)}"}
    end
  end

  defp replace_image_tag(content, new_tag) do
    with {:ok, parsed} <- parse_yaml(content),
         {:ok, updated} <- update_image_in_parsed(parsed, new_tag),
         {:ok, updated_content} <- encode_yaml(updated) do
      {:ok, updated_content}
    end
  end

  defp update_image_in_parsed(parsed, new_tag) do
    case get_in(parsed, ["spec", "template", "spec", "containers"]) do
      nil ->
        {:error, "No containers found in deployment"}

      containers when is_list(containers) ->
        updated_containers =
          Enum.map(containers, fn container ->
            case container["image"] do
              nil ->
                container

              current_image ->
                # Extract image name without tag
                image_name = String.split(current_image, ":") |> List.first()
                Map.put(container, "image", "#{image_name}:#{new_tag}")
            end
          end)

        updated_parsed =
          put_in(parsed, ["spec", "template", "spec", "containers"], updated_containers)

        {:ok, updated_parsed}

      _ ->
        {:error, "Invalid containers format"}
    end
  end

  defp extract_image_tag(parsed) do
    case get_in(parsed, ["spec", "template", "spec", "containers"]) do
      [container | _] ->
        case container["image"] do
          nil ->
            {:error, "No image found in container"}

          image ->
            case String.split(image, ":") do
              [_image_name, tag] -> {:ok, tag}
              _ -> {:error, "No tag found in image: #{image}"}
            end
        end

      _ ->
        {:error, "No containers found in deployment"}
    end
  end

  defp generate_deployment_manifest(app_name, image_name, tag, namespace) do
    """
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: #{app_name}
      namespace: #{namespace}
      labels:
        app: #{app_name}
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: #{app_name}
      template:
        metadata:
          labels:
            app: #{app_name}
        spec:
          containers:
          - name: #{app_name}
            image: #{image_name}:#{tag}
            ports:
            - containerPort: 3000
            env:
            - name: NODE_ENV
              value: "production"
            resources:
              requests:
                memory: "256Mi"
                cpu: "250m"
              limits:
                memory: "512Mi"
                cpu: "500m"
            livenessProbe:
              httpGet:
                path: /health
                port: 3000
              initialDelaySeconds: 30
              periodSeconds: 10
            readinessProbe:
              httpGet:
                path: /ready
                port: 3000
              initialDelaySeconds: 5
              periodSeconds: 5
    """
  end

  defp parse_yaml(content) do
    case YamlElixir.read_from_string(content, atoms: false) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, "YAML parse error: #{inspect(reason)}"}
    end
  end

  defp encode_yaml(parsed) do
    # Use the existing Utils.to_yml function
    temp_file = "/tmp/temp_manifest_#{:rand.uniform(10000)}.yml"

    case Utils.to_yml(parsed, temp_file) do
      :ok ->
        case File.read(temp_file) do
          {:ok, content} ->
            File.rm(temp_file)
            {:ok, content}

          {:error, reason} ->
            File.rm(temp_file)
            {:error, "Failed to read temp file: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "YAML encode error: #{inspect(reason)}"}
    end
  end

  defp validate_yaml(content) do
    case parse_yaml(content) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Invalid YAML: #{inspect(reason)}"}
    end
  end
end
