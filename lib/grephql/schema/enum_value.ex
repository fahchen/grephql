defmodule Grephql.Schema.EnumValue do
  @moduledoc false
  use TypedStructor

  typed_structor do
    field :name, String.t(), enforce: true
    field :description, String.t()
    field :is_deprecated, boolean(), default: false
    field :deprecation_reason, String.t()
  end
end
