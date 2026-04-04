defmodule Grephql.Schema.Loader do
  @moduledoc false

  alias Grephql.Schema

  @spec load(String.t()) :: {:ok, Schema.t()} | {:error, String.t()}
  def load(source) when is_binary(source) do
    if json?(source) do
      Schema.Parser.parse(source)
    else
      load_file(source)
    end
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, contents} -> Schema.Parser.parse(contents)
      {:error, reason} -> {:error, "failed to read #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp json?(source) do
    trimmed = String.trim_leading(source)
    String.starts_with?(trimmed, "{")
  end
end
