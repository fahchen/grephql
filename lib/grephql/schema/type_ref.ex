defmodule Grephql.Schema.TypeRef do
  @moduledoc false
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
