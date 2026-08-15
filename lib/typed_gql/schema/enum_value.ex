defmodule TypedGql.Schema.EnumValue do
  @moduledoc """
  One member of an enum type in a loaded schema.
  """
  use TypedStructor

  typed_structor do
    field :name, String.t(), enforce: true
    field :description, String.t()
    field :is_deprecated, boolean(), default: false
    field :deprecation_reason, String.t()
  end
end
