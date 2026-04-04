defmodule Grephql.Schema.Field do
  @moduledoc false
  use TypedStructor

  alias Grephql.Schema.InputValue
  alias Grephql.Schema.TypeRef

  typed_structor do
    field :name, String.t(), enforce: true
    field :description, String.t()
    field :type, TypeRef.t(), enforce: true
    field :args, %{String.t() => InputValue.t()}, default: %{}
    field :is_deprecated, boolean(), default: false
    field :deprecation_reason, String.t()
  end
end
