defmodule Grephql.Types.PathSegment do
  @moduledoc """
  Ecto Type for GraphQL error path segments.

  A path segment can be either a string (field name) or an integer
  (list index), as defined by the GraphQL spec for error paths.
  """

  use Ecto.Type

  @type t() :: String.t() | integer()

  @impl Ecto.Type
  def type, do: :any

  @impl Ecto.Type
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(value) when is_integer(value), do: {:ok, value}
  def cast(_other), do: :error

  @impl Ecto.Type
  defdelegate dump(value), to: __MODULE__, as: :cast

  @impl Ecto.Type
  defdelegate load(value), to: __MODULE__, as: :cast

  @impl Ecto.Type
  def embed_as(_format), do: :self
end
