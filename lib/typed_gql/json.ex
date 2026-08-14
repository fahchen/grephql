defmodule TypedGql.JSON do
  @moduledoc """
  Behaviour for JSON encoding/decoding.

  By default, uses Elixir's built-in `JSON` module (available since Elixir 1.18)
  when present, falling back to `Jason`. If neither is available, raises at runtime.

  To override the auto-detected default:

      config :typed_gql, :json_library, Jason

  A custom implementation must export `encode!/1` and `decode/1`
  (see `@callback` definitions below).
  """

  @callback encode!(term()) :: String.t()
  @callback decode(String.t()) :: {:ok, term()} | {:error, term()}

  @doc """
  Encodes a term to a JSON string. Raises on failure.
  """
  @spec encode!(term()) :: String.t()
  def encode!(term), do: library().encode!(term)

  @doc """
  Normalizes a decode error to an exception.

  The configured library decides the error shape: Jason returns an exception
  struct, Elixir's JSON a plain tuple, and a custom one anything at all.
  """
  @spec normalize_error(term()) :: Exception.t()
  def normalize_error(reason) when is_exception(reason), do: reason
  def normalize_error(reason), do: RuntimeError.exception(inspect(reason))

  @doc """
  Decodes a JSON string. Returns `{:ok, term}` or `{:error, reason}`.
  """
  @spec decode(String.t()) :: {:ok, term()} | {:error, term()}
  def decode(string), do: library().decode(string)

  @doc """
  Returns the configured JSON library module.
  """
  @spec library() :: module()
  def library do
    Application.get_env(:typed_gql, :json_library) || default_library()
  end

  defp default_library do
    cond do
      Code.ensure_loaded?(JSON) ->
        JSON

      Code.ensure_loaded?(Jason) ->
        Jason

      true ->
        raise "No JSON library found. Add {:jason, \"~> 1.4\"} to your deps or use Elixir 1.18+."
    end
  end
end
