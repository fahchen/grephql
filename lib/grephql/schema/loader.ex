defmodule Grephql.Schema.Loader do
  @moduledoc false

  alias Grephql.Schema

  @spec load(String.t()) :: {:ok, Schema.t()} | {:error, String.t()}
  def load(source) when is_binary(source) do
    if json_content?(source) do
      Schema.Parser.parse(source)
    else
      load_file(source)
    end
  end

  @spec load!(String.t()) :: Schema.t()
  def load!(source) when is_binary(source) do
    case load(source) do
      {:ok, schema} -> schema
      {:error, reason} -> raise reason
    end
  end

  @doc false
  @spec json_content?(String.t()) :: boolean()
  def json_content?(source) do
    source |> String.trim_leading() |> String.starts_with?("{")
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, contents} -> Schema.Parser.parse(contents)
      {:error, reason} -> {:error, "failed to read #{path}: #{:file.format_error(reason)}"}
    end
  end
end
