defmodule TypedGql.Types.DateTime do
  @moduledoc """
  Ecto Type for GraphQL DateTime custom scalar.

  Handles ISO 8601 datetime strings, converting between
  Elixir `DateTime` structs and ISO 8601 string representation.
  """

  use Ecto.Type

  @type t() :: DateTime.t()

  @impl Ecto.Type
  def type, do: :utc_datetime_usec

  # Without this, `Ecto.embedded_dump/2` would hand the `%DateTime{}` straight
  # to the JSON encoder and `dump/1` would never run — the wire format would
  # depend on the encoder having an implementation for it rather than on this
  # module. See `guides/mapping-custom-scalars.md`.
  @impl Ecto.Type
  def embed_as(_format), do: :dump

  @impl Ecto.Type
  def cast(%DateTime{} = dt), do: {:ok, dt}
  def cast(string) when is_binary(string), do: parse(string)
  def cast(_other), do: :error

  @impl Ecto.Type
  def dump(%DateTime{} = dt), do: {:ok, DateTime.to_iso8601(dt)}
  def dump(_other), do: :error

  @impl Ecto.Type
  def load(string) when is_binary(string), do: parse(string)
  def load(%DateTime{} = dt), do: {:ok, dt}
  def load(_other), do: :error

  defp parse(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _reason} -> :error
    end
  end
end
