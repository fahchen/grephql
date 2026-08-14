defmodule TypedGql.DecodeError do
  @moduledoc """
  Returned — never raised — when a 2xx GraphQL response carries data the
  generated result schema cannot load: an unknown union `__typename`, an
  enum value outside the schema, or a scalar of the wrong type.

  Surfaces as `{:error, %TypedGql.DecodeError{}}` from the generated query
  functions, alongside the other transport-level error tuples.
  """

  defexception [:message]
end
