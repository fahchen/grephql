defmodule TypedGql.Schema.TypeRef do
  @moduledoc """
  A reference to a type in a loaded schema, wrapping a named type in the list
  and non-null modifiers that apply to it.
  """
  use TypedStructor

  @type kind() ::
          :scalar
          | :object
          | :interface
          | :union
          | :enum
          | :input_object
          | :list
          | :non_null

  typed_structor do
    field :kind, kind(), enforce: true
    field :name, String.t()
    field :of_type, t()
  end
end
