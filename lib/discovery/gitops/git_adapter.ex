defmodule Discovery.GitOps.GitAdapter do
  @moduledoc """
  Git operations for GitOps repository management.
  Handles cloning, branching, committing, and pushing to GitOps repos.
  """

  require Logger

  @type git_operation :: :clone | :branch | :commit | :push | :pr
  @type git_result :: {:ok, map()} | {:error, String.t()}

  @doc """
  Clones a GitOps repository to a local directory.
  """
  @spec clone_repo(String.t(), String.t(), String.t()) :: git_result
  def clone_repo(repo_url, local_path, token) do
    # Remove existing directory if it exists
    File.rm_rf(local_path)
    File.mkdir_p!(Path.dirname(local_path))

    # Clone with token authentication
    auth_url = add_token_to_url(repo_url, token)

    case System.cmd("git", ["clone", auth_url, local_path], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("Successfully cloned repo to #{local_path}")
        {:ok, %{path: local_path, output: output}}

      {error_output, _exit_code} ->
        Logger.error("Failed to clone repo: #{error_output}")
        {:error, "Clone failed: #{error_output}"}
    end
  end

  @doc """
  Creates a new branch for changes.
  """
  @spec create_branch(String.t(), String.t()) :: git_result
  def create_branch(repo_path, branch_name) do
    with {:ok, _} <- run_git_cmd(repo_path, ["checkout", "-b", branch_name]),
         {:ok, _} <- run_git_cmd(repo_path, ["config", "user.email", "discovery@gitops.local"]),
         {:ok, _} <- run_git_cmd(repo_path, ["config", "user.name", "Discovery"]) do
      {:ok, %{branch: branch_name}}
    end
  end

  @doc """
  Commits changes with a message.
  """
  @spec commit_changes(String.t(), String.t()) :: git_result
  def commit_changes(repo_path, message) do
    with {:ok, _} <- run_git_cmd(repo_path, ["add", "."]),
         {:ok, output} <- run_git_cmd(repo_path, ["commit", "-m", message]) do
      {:ok, %{message: message, output: output}}
    end
  end

  @doc """
  Pushes changes to the remote repository.
  """
  @spec push_changes(String.t(), String.t(), String.t()) :: git_result
  def push_changes(repo_path, branch, token) do
    auth_url = add_token_to_url(get_remote_url(repo_path), token)

    # Set remote URL with token
    with {:ok, _} <- run_git_cmd(repo_path, ["remote", "set-url", "origin", auth_url]),
         {:ok, output} <- run_git_cmd(repo_path, ["push", "origin", branch]) do
      {:ok, %{branch: branch, output: output}}
    end
  end

  @doc """
  Creates a pull request (GitHub API).
  """
  @spec create_pull_request(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          git_result
  def create_pull_request(repo_url, token, title, body, branch) do
    [owner, repo] = extract_owner_repo(repo_url)

    payload =
      %{
        title: title,
        body: body,
        head: branch,
        base: "main"
      }
      |> Jason.encode!()

    headers = [
      {"Authorization", "token #{token}"},
      {"Accept", "application/vnd.github.v3+json"},
      {"Content-Type", "application/json"}
    ]

    url = "https://api.github.com/repos/#{owner}/#{repo}/pulls"

    case HTTPoison.post(url, payload, headers) do
      {:ok, %HTTPoison.Response{status_code: 201, body: body}} ->
        pr_data = Jason.decode!(body)
        {:ok, %{pr_number: pr_data["number"], pr_url: pr_data["html_url"]}}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("Failed to create PR: #{status} - #{body}")
        {:error, "PR creation failed: #{body}"}

      {:error, reason} ->
        Logger.error("HTTP error creating PR: #{inspect(reason)}")
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  @doc """
  Updates a file in the repository.
  """
  @spec update_file(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def update_file(repo_path, file_path, content) do
    full_path = Path.join(repo_path, file_path)

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(full_path))

    case File.write(full_path, content) do
      :ok ->
        Logger.info("Updated file: #{file_path}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to write file #{file_path}: #{inspect(reason)}")
        {:error, "File write failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Reads a file from the repository.
  """
  @spec read_file(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def read_file(repo_path, file_path) do
    full_path = Path.join(repo_path, file_path)

    case File.read(full_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "File read failed: #{inspect(reason)}"}
    end
  end

  # Private helper functions

  defp add_token_to_url(url, token) do
    case String.contains?(url, "github.com") do
      true -> String.replace(url, "https://github.com/", "https://#{token}@github.com/")
      false -> url
    end
  end

  defp get_remote_url(repo_path) do
    case System.cmd("git", ["remote", "get-url", "origin"], cd: repo_path) do
      {url, 0} -> String.trim(url)
      _ -> ""
    end
  end

  defp extract_owner_repo(repo_url) do
    repo_url
    |> String.replace("https://github.com/", "")
    |> String.replace(".git", "")
    |> String.split("/")
  end

  def run_git_cmd(repo_path, args) do
    case System.cmd("git", args, cd: repo_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error_output, _exit_code} -> {:error, String.trim(error_output)}
    end
  end
end
