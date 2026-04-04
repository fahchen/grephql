# Adapted from Absinthe's parser (https://github.com/absinthe-graphql/absinthe)
# Original work Copyright (c) 2015 CargoSense, LLC — MIT License
# See NOTICE file for attribution details.
defmodule Grephql.Parser do
  @moduledoc false

  alias Grephql.Language.Document

  @spec parse(String.t()) :: {:ok, Document.t()} | {:error, String.t()}
  def parse(input) when is_binary(input) do
    with {:ok, tokens} <- tokenize(input) do
      do_parse(tokens)
    end
  end

  @spec tokenize(String.t()) ::
          {:ok, [tuple()]} | {:error, String.t()}
  defp tokenize(input) do
    case Grephql.Lexer.tokenize(input) do
      {:ok, tokens} ->
        {:ok, tokens}

      {:error, rest, location} ->
        {:error, format_error(:lexer, rest, location)}

      {:error, :exceeded_token_limit} ->
        {:error, "token limit exceeded"}
    end
  end

  @spec do_parse([tuple()]) :: {:ok, Document.t()} | {:error, String.t()}
  defp do_parse(tokens) do
    case :grephql_parser.parse(tokens) do
      {:ok, document} ->
        {:ok, document}

      {:error, {location, :grephql_parser, messages}} ->
        {:error, format_error(:parser, messages, location)}
    end
  end

  @spec format_error(:lexer | :parser, String.t() | [charlist()], {integer(), integer()}) ::
          String.t()
  defp format_error(:lexer, rest, {line, column}) do
    "Syntax error at line #{line}, column #{column}: unexpected character #{inspect(String.first(rest))}"
  end

  defp format_error(:parser, messages, {line, column}) do
    message = messages |> Enum.map(&to_string/1) |> Enum.join()
    "Parse error at line #{line}, column #{column}: #{message}"
  end
end
