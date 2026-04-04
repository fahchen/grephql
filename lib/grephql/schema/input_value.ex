defmodule Grephql.Schema.InputValue do
  @moduledoc false
  use TypedStructor

  alias Grephql.Schema.TypeRef

  typed_structor do
    field :name, String.t(), enforce: true
    field :description, String.t()
    field :type, TypeRef.t(), enforce: true
    field :default_value, String.t()
  end
end
