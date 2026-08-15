defmodule TypedGql.Schema.Field do
  @moduledoc """
  A field an object or interface type exposes in a loaded schema.
  """
  use TypedStructor

  alias TypedGql.Schema.InputValue
  alias TypedGql.Schema.TypeRef

  typed_structor do
    field :name, String.t(), enforce: true
    field :description, String.t()
    field :type, TypeRef.t(), enforce: true
    field :args, %{String.t() => InputValue.t()}, default: %{}
    field :is_deprecated, boolean(), default: false
    field :deprecation_reason, String.t()
  end
end
