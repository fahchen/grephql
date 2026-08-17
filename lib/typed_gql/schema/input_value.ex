defmodule TypedGql.Schema.InputValue do
  @moduledoc """
  An input position in a loaded schema: a field argument, a directive argument
  or an input object field.
  """
  use TypedStructor

  alias TypedGql.Schema.TypeRef

  typed_structor do
    field :name, String.t(), enforce: true
    field :description, String.t()
    field :type, TypeRef.t(), enforce: true
    field :default_value, String.t()
    field :is_deprecated, boolean(), default: false
    field :deprecation_reason, String.t()
  end
end
