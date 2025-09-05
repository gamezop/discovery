defmodule Discovery.GitOps.GitOpsManager do
  @moduledoc """
  Main GitOps manager that orchestrates Git operations, image updates and repository management.
  Acts as the primary interface for GitOps operations in Discovery.
  """

  use GenServer
  require Logger

  alias Discovery.GitOps.{GitAdapter, RepoLayout, ImageUpdater}

  ## Client functions

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Updates an app's image tag in the GitOps repository.
  """
  @spec update_app_image(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def update_app_image(app_name, new_tag, environment \\ "production") do
    GenServer.call(__MODULE__, {:update_app_image, app_name, new_tag, environment}, :infinity)
  end

  @doc """
  Creates a new app in the GitOps repository.
  """
  @spec create_app(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def create_app(app_name, image_name, environment \\ "production") do
    GenServer.call(__MODULE__, {:create_app, app_name, image_name, environment}, :infinity)
  end

  @doc """
  Lists all apps in the GitOps repository.
  """
  @spec list_apps() :: {:ok, [String.t()]} | {:error, String.t()}
  def list_apps do
    GenServer.call(__MODULE__, :list_apps, :infinity)
  end

  @doc """
  Gets the current image tag for an app.
  """
  @spec get_app_image_tag(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_app_image_tag(app_name, environment \\ "production") do
    GenServer.call(__MODULE__, {:get_app_image_tag, app_name, environment}, :infinity)
  end

  @doc """
  Syncs the local minikube/discovery folder to the GitOps repository.
  This replaces the S3 upload functionality.
  """
  @spec sync_to_gitops(String.t()) :: {:ok, map()} | {:error, String.t()}
  def sync_to_gitops(commit_message \\ "Sync Discovery deployment state to GitOps") do
    GenServer.call(__MODULE__, {:sync_to_gitops, commit_message}, :infinity)
  end

  @doc """
  Syncs a specific app's deployment to the GitOps repository.
  """
  @spec sync_app_to_gitops(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def sync_app_to_gitops(app_name, commit_message \\ nil) do
    message = commit_message || "Update #{app_name} deployment in GitOps"
    GenServer.call(__MODULE__, {:sync_app_to_gitops, app_name, message}, :infinity)
  end

  @doc """
  Syncs the entire minikube/discovery folder to the GitOps repository.
  This copies all files from minikube/discovery to /tmp/discovery-gitops and pushes to Git.
  """
  @spec sync_from_discovery_to_gitops(String.t()) :: {:ok, map()} | {:error, String.t()}
  def sync_from_discovery_to_gitops(commit_message \\ "Sync Discovery state to GitOps") do
    GenServer.call(__MODULE__, {:sync_from_discovery_to_gitops, commit_message}, :infinity)
  end

  @doc """
  Syncs a specific app from minikube/discovery to the GitOps repository.
  """
  @spec sync_app_from_discovery_to_gitops(String.t(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def sync_app_from_discovery_to_gitops(app_name, commit_message \\ nil) do
    message = commit_message || "Update #{app_name} from Discovery to GitOps"
    GenServer.call(__MODULE__, {:sync_app_from_discovery_to_gitops, app_name, message}, :infinity)
  end

  @doc """
  Automatically syncs an app after deployment.
  This can be called from the deployment workflow to ensure GitOps is always up to date.
  """
  @spec auto_sync_after_deployment(String.t()) :: {:ok, map()} | {:error, String.t()}
  def auto_sync_after_deployment(app_name) do
    commit_message = "Auto-sync: #{app_name} deployment updated"
    sync_app_from_discovery_to_gitops(app_name, commit_message)
  end

  @doc """
  CI-style deploy: generate uid, write manifests under /tmp working dir, commit and push.
  Params: app_name, image, environment, config_ref (git|artifact|reuse_last), idempotency_key(optional)
  """
  @spec ci_deploy(String.t(), String.t(), String.t(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def ci_deploy(app_name, image, environment, config_ref, idempotency_key \\ nil) do
    GenServer.call(
      __MODULE__,
      {:ci_deploy, app_name, image, environment, config_ref, idempotency_key},
      :infinity
    )
  end

  @doc """
  Returns basic status for a deployment by name (app-uid): presence of manifests.
  """
  @spec ci_status(String.t()) :: {:ok, map()} | {:error, String.t()}
  def ci_status(deployment_name) do
    GenServer.call(__MODULE__, {:ci_status, deployment_name}, :infinity)
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    git_access_token = Application.get_env(:discovery, :git_access_token)
    repo_url = Keyword.get(opts, :repo_url, "https://github.com/ghostdsb/gitops.git")
    token = Keyword.get(opts, :token, git_access_token)
    local_path = Keyword.get(opts, :local_path, "/tmp/discovery-gitops")
    use_pr = Keyword.get(opts, :use_pr, false)

    # New layout options
    # :apps_first | :env_first
    write_layout = Keyword.get(opts, :write_layout, :apps_first)

    env_root_map =
      Keyword.get(opts, :env_root_map, %{"dev" => "dev", "staging" => "staging", "prod" => "prod"})

    base_dir_name = Keyword.get(opts, :base_dir_name, "base")

    file_names =
      Keyword.get(opts, :file_names, %{
        deployment: "deployment.yml",
        configmap: "configmap.yml",
        secret: "secret.yml",
        service: "service.yml",
        ingress: "ingress.yml"
      })

    state = %{
      repo_url: repo_url,
      token: token,
      local_path: local_path,
      use_pr: use_pr,
      write_layout: write_layout,
      env_root_map: env_root_map,
      base_dir_name: base_dir_name,
      file_names: file_names
    }

    Logger.info("GitOpsManager initialized with repo: #{repo_url} at #{local_path}")

    # Initialize the local directory structure
    File.mkdir_p!(local_path)

    {:ok, state}
  end

  @impl true
  def handle_call({:update_app_image, app_name, new_tag, environment}, _from, state) do
    result = do_update_app_image(app_name, new_tag, environment, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_app, app_name, image_name, environment}, _from, state) do
    result = do_create_app(app_name, image_name, environment, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_apps, _from, state) do
    result = do_list_apps(state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_app_image_tag, app_name, environment}, _from, state) do
    result = do_get_app_image_tag(app_name, environment, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sync_to_gitops, commit_message}, _from, state) do
    result = do_sync_to_gitops(commit_message, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sync_app_to_gitops, app_name, commit_message}, _from, state) do
    result = do_sync_app_to_gitops(app_name, commit_message, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sync_from_discovery_to_gitops, commit_message}, _from, state) do
    result = do_sync_from_discovery_to_gitops(commit_message, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sync_app_from_discovery_to_gitops, app_name, commit_message}, _from, state) do
    result = do_sync_app_from_discovery_to_gitops(app_name, commit_message, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(
        {:ci_deploy, app_name, image, environment, config_ref, idempotency_key},
        _from,
        state
      ) do
    result = do_ci_deploy(app_name, image, environment, config_ref, idempotency_key, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:ci_status, deployment_name}, _from, state) do
    result = do_ci_status(deployment_name, state)
    {:reply, result, state}
  end

  # Private implementation functions

  defp do_update_app_image(app_name, new_tag, environment, state) do
    with {:ok, _} <- ensure_repo_cloned(state),
         {:ok, old_tag} <-
           ImageUpdater.get_current_image_tag(state.local_path, app_name, environment),
         {:ok, _} <-
           ImageUpdater.update_image_tag(state.local_path, app_name, new_tag, environment),
         {:ok, commit_result} <- commit_and_push_changes(app_name, old_tag, new_tag, state) do
      Logger.info("Successfully updated #{app_name} from #{old_tag} to #{new_tag}")

      {:ok,
       %{
         app_name: app_name,
         old_tag: old_tag,
         new_tag: new_tag,
         commit: commit_result
       }}
    else
      {:error, reason} ->
        Logger.error("Failed to update app image: #{reason}")
        {:error, reason}
    end
  end

  defp do_create_app(app_name, image_name, environment, state) do
    with {:ok, _} <- ensure_repo_cloned(state),
         {:ok, _} <-
           ImageUpdater.create_deployment_manifest(
             state.local_path,
             app_name,
             image_name,
             "latest",
             environment
           ),
         {:ok, commit_result} <- commit_and_push_changes(app_name, nil, "latest", state) do
      Logger.info("Successfully created app #{app_name}")

      {:ok,
       %{
         app_name: app_name,
         image_name: image_name,
         commit: commit_result
       }}
    else
      {:error, reason} ->
        Logger.error("Failed to create app: #{reason}")
        {:error, reason}
    end
  end

  defp do_list_apps(state) do
    with {:ok, _} <- ensure_repo_cloned(state) do
      apps = RepoLayout.list_apps(state.local_path)
      {:ok, apps}
    else
      {:error, reason} ->
        Logger.error("Failed to list apps: #{reason}")
        {:error, reason}
    end
  end

  defp do_get_app_image_tag(app_name, environment, state) do
    with {:ok, _} <- ensure_repo_cloned(state) do
      ImageUpdater.get_current_image_tag(state.local_path, app_name, environment)
    else
      {:error, reason} ->
        Logger.error("Failed to get app image tag: #{reason}")
        {:error, reason}
    end
  end

  defp do_sync_to_gitops(commit_message, state) do
    with {:ok, _} <- ensure_repo_cloned(state),
         {:ok, commit_result} <- commit_and_push_changes("all", nil, nil, state, commit_message) do
      Logger.info("Successfully synced entire Discovery state to GitOps")
      {:ok, %{message: "Full sync completed", commit: commit_result}}
    else
      {:error, reason} ->
        Logger.error("Failed to sync to GitOps: #{reason}")
        {:error, reason}
    end
  end

  defp do_sync_app_to_gitops(app_name, commit_message, state) do
    with {:ok, _} <- ensure_repo_cloned(state),
         {:ok, commit_result} <-
           commit_and_push_changes(app_name, nil, nil, state, commit_message) do
      Logger.info("Successfully synced #{app_name} to GitOps")
      {:ok, %{app_name: app_name, commit: commit_result}}
    else
      {:error, reason} ->
        Logger.error("Failed to sync #{app_name} to GitOps: #{reason}")
        {:error, reason}
    end
  end

  defp do_sync_from_discovery_to_gitops(commit_message, state) do
    discovery_path = "minikube/discovery"

    with :ok <- ensure_discovery_folder_exists(discovery_path),
         :ok <- copy_discovery_to_gitops(discovery_path, state.local_path),
         {:ok, _} <- ensure_repo_cloned(state),
         {:ok, commit_result} <- commit_and_push_changes("all", nil, nil, state, commit_message) do
      Logger.info("Successfully synced entire Discovery state to GitOps")
      {:ok, %{message: "Full sync completed", commit: commit_result}}
    else
      {:error, reason} ->
        Logger.error("Failed to sync from Discovery to GitOps: #{reason}")
        {:error, reason}
    end
  end

  defp do_sync_app_from_discovery_to_gitops(app_name, commit_message, state) do
    discovery_path = "minikube/discovery"
    app_discovery_path = Path.join(discovery_path, app_name)
    app_gitops_path = Path.join(state.local_path, app_name)

    with :ok <- ensure_discovery_folder_exists(discovery_path),
         :ok <- copy_app_folder(app_discovery_path, app_gitops_path),
         {:ok, _} <- ensure_repo_cloned(state),
         {:ok, commit_result} <-
           commit_and_push_changes(app_name, nil, nil, state, commit_message) do
      Logger.info("Successfully synced #{app_name} from Discovery to GitOps")
      {:ok, %{app_name: app_name, commit: commit_result}}
    else
      {:error, reason} ->
        Logger.error("Failed to sync #{app_name} from Discovery to GitOps: #{reason}")
        {:error, reason}
    end
  end

  defp do_ci_deploy(app_name, image, environment, config_ref, _idempotency_key, state) do
    uid = Discovery.Utils.get_uid()
    deployment_name = "#{app_name}-#{uid}"

    app_dir = output_app_dir(state, environment, app_name, deployment_name)
    File.mkdir_p!(app_dir)

    # Create app struct for Resource modules
    app = %{
      app_name: app_name,
      app_image: image,
      uid: uid,
      # Will be populated from config_ref
      config_map: %{},
      app_host: "#{app_name}.example.com",
      app_target_port: 80,
      app_container_port: 4000
    }

    with {:ok, _} <- ensure_repo_cloned(state),
         {:ok, config_data} <-
           Discovery.GitOps.ConfigFetcher.fetch(
             app_name,
             environment,
             config_ref,
             state.local_path
           ),
         app_with_config <- Map.put(app, :config_map, config_data),
         :ok <- write_configmap_using_resource(app_dir, app_with_config, state),
         :ok <- write_deployment_using_resource(app_dir, app_with_config, state),
         :ok <- write_service_using_resource(app_dir, app_with_config, state),
         :ok <- upsert_ingress_using_resource(environment, app_name, deployment_name, state),
         {:ok, commit_result} <-
           commit_and_push_changes(
             app_name,
             nil,
             nil,
             state,
             "feat(ci): deploy #{deployment_name} to #{environment}"
           ) do
      {:ok,
       %{
         deployment_name: deployment_name,
         app_name: app_name,
         environment: environment,
         image: image,
         git_paths: %{
           deployment:
             relative_from_root(state.local_path, Path.join(app_dir, state.file_names.deployment)),
           configmap:
             relative_from_root(state.local_path, Path.join(app_dir, state.file_names.configmap)),
           service:
             relative_from_root(state.local_path, Path.join(app_dir, state.file_names.service))
         },
         commit: commit_result
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_ci_status(deployment_name, state) do
    [app_name | _] = String.split(deployment_name, "-")
    app_dir = Path.join([state.local_path, "apps", app_name, deployment_name])
    dep = Path.join(app_dir, "deployment.yaml")
    cfg = Path.join(app_dir, "configmap.yaml")

    {:ok,
     %{
       exists: File.exists?(app_dir),
       files: %{
         deployment_yaml: File.exists?(dep),
         configmap_yaml: File.exists?(cfg)
       },
       paths: %{
         deployment: relative_from_root(state.local_path, dep),
         configmap: relative_from_root(state.local_path, cfg)
       }
     }}
  end

  defp write_configmap_using_resource(app_dir, app, state) do
    with {:ok, configmap} <- Discovery.Resources.ConfigMap.set_config_map(app),
         :ok <-
           Discovery.Resources.ConfigMap.write_to_file(
             configmap,
             Path.join(app_dir, state.file_names.configmap)
           ) do
      :ok
    else
      {:error, reason} -> {:error, "ConfigMap creation failed: #{inspect(reason)}"}
    end
  end

  defp write_deployment_using_resource(app_dir, app, state) do
    with {:ok, deployment} <- Discovery.Resources.Deployment.create_deployment(app),
         :ok <-
           Discovery.Resources.Deployment.write_to_file(
             deployment,
             Path.join(app_dir, state.file_names.deployment)
           ) do
      :ok
    else
      {:error, reason} -> {:error, "Deployment creation failed: #{inspect(reason)}"}
    end
  end

  defp write_service_using_resource(app_dir, app, state) do
    with {:ok, service} <- Discovery.Resources.Service.create_service(app),
         :ok <-
           Discovery.Resources.Service.write_to_file(
             service,
             Path.join(app_dir, state.file_names.service)
           ) do
      :ok
    else
      {:error, reason} -> {:error, "Service creation failed: #{inspect(reason)}"}
    end
  end

  defp upsert_ingress_using_resource(environment, app_name, deployment_name, state) do
    env_root = Map.get(state.env_root_map, environment, environment)
    app_root = Path.join([state.local_path, env_root, app_name])
    ingress_path = Path.join(app_root, state.file_names.ingress)

    # Create a minimal app struct for ingress operations
    app = %{
      app_name: app_name,
      uid: String.replace(deployment_name, "#{app_name}-", ""),
      app_host: "#{app_name}.example.com"
    }

    with {:ok, {_ingress_status, ingress}} <- fetch_or_create_ingress(ingress_path, app),
         updated_ingress <- add_ingress_path_for_deployment(ingress, deployment_name),
         :ok <- Discovery.Resources.Ingress.write_to_file(updated_ingress, ingress_path) do
      :ok
    else
      {:error, reason} -> {:error, "Ingress update failed: #{inspect(reason)}"}
    end
  end

  defp fetch_or_create_ingress(ingress_path, app) do
    case File.exists?(ingress_path) do
      true ->
        case YamlElixir.read_from_file(ingress_path, atoms: false) do
          {:ok, ingress} -> {:ok, {:old_ingress, ingress}}
          {:error, _} -> {:error, "Failed to read existing ingress"}
        end

      false ->
        # Create new ingress using the template
        with {:ok, map} <-
               YamlElixir.read_from_file("#{:code.priv_dir(:discovery)}/templates/ingress.yml",
                 atoms: false
               ),
             map <- put_in(map["metadata"]["name"], app.app_name),
             map <-
               put_in(map["spec"]["rules"], [
                 %{"host" => app.app_host, "http" => %{"paths" => []}}
               ]) do
          {:ok, {:new_ingress, map}}
        else
          {:error, _} -> {:error, "Failed to create new ingress"}
        end
    end
  end

  defp add_ingress_path_for_deployment(ingress, deployment_name) do
    new_path = %{
      "path" => "/#{deployment_name}(/|$)(.*)",
      "pathType" => "Prefix",
      "backend" => %{
        "service" => %{
          "name" => deployment_name,
          "port" => %{"number" => 80}
        }
      }
    }

    rules = get_in(ingress, ["spec", "rules"]) || []
    rule0 = rules |> List.first() || %{"http" => %{"paths" => []}}

    updated_paths =
      (get_in(rule0, ["http", "paths"]) || [])
      |> Enum.reject(fn p -> get_in(p, ["backend", "service", "name"]) == deployment_name end)
      |> Kernel.++([new_path])

    updated_rule = put_in(rule0, ["http", "paths"], updated_paths)

    put_in(ingress, ["spec", "rules"], [updated_rule])
  end

  defp output_app_dir(state, environment, app_name, deployment_name) do
    case state.write_layout do
      :env_first ->
        env_root = Map.get(state.env_root_map, environment, environment)
        Path.join([state.local_path, env_root, app_name, deployment_name])

      _ ->
        Path.join([state.local_path, "apps", app_name, deployment_name])
    end
  end

  defp relative_from_root(root, full) do
    case String.replace_prefix(full, root <> "/", "") do
      ^full -> full
      rel -> rel
    end
  end

  defp ensure_repo_cloned(state) do
    case File.exists?(state.local_path) do
      true ->
        # Pull latest changes
        case GitAdapter.run_git_cmd(state.local_path, ["pull", "origin", "main"]) do
          {:ok, _} ->
            {:ok, :already_cloned}

          {:error, reason} ->
            Logger.warn("Failed to pull latest changes: #{reason}")
            # Continue anyway
            {:ok, :already_cloned}
        end

      false ->
        GitAdapter.clone_repo(state.repo_url, state.local_path, state.token)
    end
  end

  defp ensure_discovery_folder_exists(discovery_path) do
    if File.exists?(discovery_path) do
      :ok
    else
      Logger.warn("Discovery folder #{discovery_path} does not exist")
      {:error, "Discovery folder not found: #{discovery_path}"}
    end
  end

  defp copy_discovery_to_gitops(discovery_path, gitops_path) do
    # Remove existing gitops folder and recreate
    File.rm_rf(gitops_path)
    File.mkdir_p!(gitops_path)

    # Copy all files and folders from discovery to gitops
    copy_directory_contents(discovery_path, gitops_path)
    :ok
  end

  defp copy_app_folder(app_discovery_path, app_gitops_path) do
    # Remove existing app folder in gitops and recreate
    File.rm_rf(app_gitops_path)
    File.mkdir_p!(app_gitops_path)

    # Copy app folder contents
    copy_directory_contents(app_discovery_path, app_gitops_path)
    :ok
  end

  defp copy_directory_contents(source, destination) do
    case File.ls(source) do
      {:ok, items} ->
        Enum.each(items, fn item ->
          source_path = Path.join(source, item)
          dest_path = Path.join(destination, item)

          if File.dir?(source_path) do
            # Copy directory recursively
            File.mkdir_p!(dest_path)
            copy_directory_contents(source_path, dest_path)
          else
            # Copy file
            File.cp!(source_path, dest_path)
          end
        end)

      {:error, reason} ->
        Logger.error("Failed to list directory #{source}: #{reason}")
        {:error, "Failed to list directory: #{reason}"}
    end
  end

  defp commit_and_push_changes(app_name, old_tag, new_tag, state, custom_message \\ nil) do
    message =
      custom_message || RepoLayout.get_commit_message(app_name, old_tag || "none", new_tag)

    if state.use_pr do
      # Create PR workflow
      branch_name = "update-#{app_name}-#{new_tag}-#{:rand.uniform(10000)}"

      with {:ok, _} <- GitAdapter.create_branch(state.local_path, branch_name),
           {:ok, _} <- GitAdapter.commit_changes(state.local_path, message),
           {:ok, _} <- GitAdapter.push_changes(state.local_path, branch_name, state.token),
           {:ok, pr_result} <-
             GitAdapter.create_pull_request(
               state.repo_url,
               state.token,
               RepoLayout.get_pr_title(app_name, new_tag),
               RepoLayout.get_pr_body(app_name, old_tag || "none", new_tag),
               branch_name
             ) do
        {:ok, %{type: :pr, pr: pr_result}}
      end
    else
      # Direct push to main
      with {:ok, _} <- GitAdapter.commit_changes(state.local_path, message),
           {:ok, _} <- GitAdapter.push_changes(state.local_path, "main", state.token) do
        {:ok, %{type: :commit, message: message}}
      end
    end
  end
end
