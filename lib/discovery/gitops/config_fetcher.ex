defmodule Discovery.GitOps.ConfigFetcher do
  @moduledoc """
  Fetches ConfigMap data for CI deploys from different sources:
  - git: %{repo, path, rev}
  - artifact: %{url}
  - reuse_last: true
  Returns {:ok, map()} config data suitable for writing as a ConfigMap data section.
  Supports env-first layouts: if path points to {env}/{app}, merges {env}/{app}/base/*.yml
  and optionally merges {env}/{app}/{app-uid}/configmap.yml when provided via override_path.
  """

  require Logger

  @type config_ref :: %{
          optional(:git) => map(),
          optional(:artifact) => map(),
          optional(:reuse_last) => boolean()
        }

  @spec fetch(String.t(), String.t(), config_ref, String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def fetch(app_name, _environment, config_ref, working_dir) do
    cond do
      is_map(config_ref) and Map.has_key?(config_ref, :git) ->
        fetch_from_git(config_ref.git, working_dir)

      is_map(config_ref) and Map.has_key?(config_ref, "git") ->
        fetch_from_git(config_ref["git"], working_dir)

      is_map(config_ref) and Map.has_key?(config_ref, :artifact) ->
        fetch_from_artifact(config_ref.artifact)

      is_map(config_ref) and Map.has_key?(config_ref, "artifact") ->
        fetch_from_artifact(config_ref["artifact"])

      is_map(config_ref) and (config_ref[:reuse_last] || config_ref["reuse_last"]) ->
        reuse_last(app_name, working_dir)

      true ->
        {:error, "invalid config_ref"}
    end
  end

  defp fetch_from_git(%{"repo" => repo, "path" => path, "rev" => rev} = m, working_dir) do
    fetch_from_git(
      %{repo: repo, path: path, rev: rev, override_path: m["override_path"]},
      working_dir
    )
  end

  defp fetch_from_git(%{repo: repo, path: path, rev: rev} = m, working_dir) do
    tmp_dir =
      Path.join([
        working_dir,
        ".cfgsrc",
        :erlang.unique_integer([:positive]) |> Integer.to_string()
      ])

    File.rm_rf(tmp_dir)
    File.mkdir_p!(tmp_dir)

    case System.cmd("git", ["clone", "--no-checkout", repo, tmp_dir], stderr_to_stdout: true) do
      {_out, 0} ->
        _ =
          System.cmd("git", ["-C", tmp_dir, "fetch", "--depth", "1", "origin", rev],
            stderr_to_stdout: true
          )

        _ = System.cmd("git", ["-C", tmp_dir, "checkout", "FETCH_HEAD"], stderr_to_stdout: true)

        full = Path.join(tmp_dir, path)

        cond do
          File.dir?(full) ->
            # Try env-first base merge: {path}/base/*.yml
            base_dir = Path.join(full, "base")

            base_maps =
              if File.dir?(base_dir) do
                base_dir
                |> File.ls!()
                |> Enum.filter(&String.ends_with?(&1, [".yml", ".yaml"]))
                |> Enum.map(&Path.join(base_dir, &1))
                |> Enum.map(&read_yaml_map/1)
                |> Enum.filter(&match?({:ok, _}, &1))
                |> Enum.map(fn {:ok, m} -> m end)
              else
                []
              end

            data = deep_merge_all(base_maps)

            # If there is an override_path (e.g., {env}/{app}/{app-uid}/configmap.yml), merge it on top
            data =
              case m[:override_path] || m["override_path"] do
                nil ->
                  data

                o when is_binary(o) ->
                  override_full = Path.join(tmp_dir, o)

                  case read_yaml_map(override_full) do
                    {:ok, om} -> deep_merge(data, om)
                    _ -> data
                  end
              end

            {:ok, data}

          true ->
            # File path; if it is a ConfigMap, extract data; else treat as data map
            read_config_yaml(full)
        end

      {err, _} ->
        Logger.error("config git clone failed: #{err}")
        {:error, "git clone failed"}
    end
  end

  defp fetch_from_artifact(%{"url" => url}), do: fetch_from_artifact(%{url: url})

  defp fetch_from_artifact(%{url: url}) do
    headers = [{"Accept", "application/yaml"}]

    case HTTPoison.get(url, headers, follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        decode_yaml(body)

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        {:error, "artifact http #{code}: #{String.slice(to_string(body), 0, 200)}"}

      {:error, reason} ->
        {:error, "artifact fetch error: #{inspect(reason)}"}
    end
  end

  defp reuse_last(app_name, working_dir) do
    app_dir = Path.join([working_dir, "apps", app_name])

    with true <- File.dir?(app_dir),
         {:ok, entries} <- File.ls(app_dir),
         [latest | _] <-
           entries |> Enum.filter(&String.contains?(&1, "#{app_name}-")) |> Enum.sort(:desc),
         cfg_path <- Path.join([app_dir, latest, "configmap.yaml"]),
         true <- File.exists?(cfg_path),
         {:ok, content} <- File.read(cfg_path),
         {:ok, map} <- YamlElixir.read_from_string(content, atoms: false) do
      data = map["data"] || %{}
      {:ok, data}
    else
      false -> {:error, "no previous deployments for #{app_name}"}
      {:error, reason} -> {:error, "read previous config error: #{inspect(reason)}"}
      _ -> {:error, "no previous config found"}
    end
  end

  defp read_yaml_map(path) do
    case File.read(path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content, atoms: false) do
          {:ok, m} when is_map(m) ->
            # If full ConfigMap, extract data field
            {:ok,
             if Map.get(m, "kind") == "ConfigMap" and is_map(m["data"]) do
               m["data"]
             else
               m
             end}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_config_yaml(path) do
    case File.read(path) do
      {:ok, content} -> decode_yaml(content)
      {:error, :enoent} -> {:error, "read config error: :enoent (#{path})"}
      {:error, reason} -> {:error, "read config error: #{inspect(reason)}"}
    end
  end

  defp decode_yaml(content) do
    case YamlElixir.read_from_string(content, atoms: false) do
      {:ok, map} when is_map(map) ->
        cond do
          Map.get(map, "kind") == "ConfigMap" and is_map(map["data"]) -> {:ok, map["data"]}
          true -> {:ok, map}
        end

      {:error, reason} ->
        {:error, "yaml parse error: #{inspect(reason)}"}
    end
  end

  defp deep_merge_all([]), do: %{}
  defp deep_merge_all([m | rest]), do: Enum.reduce(rest, m, &deep_merge/2)

  defp deep_merge(a, b) when is_map(a) and is_map(b) do
    Map.merge(a, b, fn _k, v1, v2 -> deep_merge(v1, v2) end)
  end

  defp deep_merge(_a, b), do: b
end
