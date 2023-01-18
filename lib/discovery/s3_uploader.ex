defmodule Discovery.S3Uploader do
  @moduledoc """
    Module for S3 related functions
  """

  require Logger

  @doc """
  Uploads file to S3 bucket

  Expects:
  - local path of the file
  - bucket name
  - filename_file_path: path to be saved in bucket
  """
  @spec upload_file(String.t(), String.t(), String.t()) ::
          :ok | {:error, String.t()}
  def upload_file(path, bucket, upload_file_path) do
    with {:ok, file} <- File.read(path),
         operation <-
           ExAws.S3.put_object(bucket, upload_file_path, file),
         {:ok, _resp} <- ExAws.request(operation) do
      :ok
    else
      {:error, reason} ->
        Logger.error("error in uploading to S3 #{inspect(reason)}")
        {:error, "error in uploading to S3 #{inspect(reason)}"}
    end
  end

  def download_contents(bucket) do
    {:ok, %{body: %{contents: contents}}} = ExAws.S3.list_objects(bucket) |> ExAws.request()

    contents
    |> Enum.each(fn content ->
      data = download(bucket, content.key)

      Path.dirname(content.key)
      |> File.mkdir_p()

      {:ok, file} = File.open(content.key, [:write, :utf8, :binary])
      IO.write(file, data)
    end)
  end

  def delete_content(bucket, object) do
    with operation <- ExAws.S3.list_objects(bucket, prefix: object),
         {:ok, %{body: %{contents: contents}}} <- ExAws.request(operation),
         objects_list <- contents |> Enum.reduce([], fn x, acc -> [x.key | acc] end),
         operation <- ExAws.S3.delete_multiple_objects(bucket, objects_list),
         {:ok, resp} <- ExAws.request(operation) do
      resp
    end
  end

  @doc """
  Tags the object for bucket level customisations
  """
  @spec tag_object(String.t(), String.t(), map()) :: :ok | {:error, String.t()}
  def tag_object(bucket, upload_file_path, tags) do
    with operation <-
           ExAws.S3.put_object_tagging(bucket, upload_file_path, tags),
         {:ok, _resp} <- ExAws.request(operation) do
      :ok
    else
      {:error, reason} ->
        Logger.error("error in object tagging in #{bucket} #{inspect(reason)}")
        {:error, "error in object tagging in #{bucket} #{inspect(reason)}"}
    end
  end

  def download(bucket, file_path) do
    ExAws.S3.download_file(bucket, file_path, :memory)
    |> ExAws.stream!()
    |> Enum.map(& &1)
    |> List.first()
  end
end
