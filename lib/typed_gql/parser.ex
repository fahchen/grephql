# Adapted from Absinthe's parser (https://github.com/absinthe-graphql/absinthe)
# Original work Copyright (c) 2015 CargoSense, LLC — MIT License
# See NOTICE file for attribution details.
defmodule TypedGql.Parser do
  @moduledoc false

  alias TypedGql.Language.Document

  @spec parse(String.t()) :: {:ok, Document.t()} | {:error, String.t()}
  def parse(input) when is_binary(input) do
    with {:ok, tokens} <- tokenize(input) do
      do_parse(tokens)
    end
  end

  @spec tokenize(String.t()) ::
          {:ok, [tuple()]} | {:error, String.t()}
  defp tokenize(input) do
    case TypedGql.Lexer.tokenize(input) do
      {:ok, tokens} ->
        {:ok, tokens}

      {:error, rest, location} ->
        {:error, format_error(:lexer, rest, location)}

      {:error, :exceeded_token_limit} ->
        {:error, "token limit exceeded"}

      {:error, :unsupported_escape} ->
        {:error, "surrogate pair escapes are not supported (see BDR-0008)"}
    end
  end

  @spec do_parse([tuple()]) :: {:ok, Document.t()} | {:error, String.t()}
  defp do_parse(tokens) do
    case :typed_gql_parser.parse(tokens) do
      {:ok, document} ->
        {:ok, document}

      {:error, {location, :typed_gql_parser, messages}} ->
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
