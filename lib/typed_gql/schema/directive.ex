defmodule TypedGql.Schema.Directive do
  @moduledoc """
  A directive a loaded schema declares, along with the locations it may be
  applied to.
  """
  use TypedStructor

  alias TypedGql.Schema.InputValue

  @type location() ::
          :query
          | :mutation
          | :subscription
          | :field
          | :fragment_definition
          | :fragment_spread
          | :inline_fragment
          | :variable_definition
          | :schema
          | :scalar
          | :object
          | :field_definition
          | :argument_definition
          | :interface
          | :union
          | :enum
          | :enum_value
          | :input_object
          | :input_field_definition

  typed_structor do
    field :name, String.t(), enforce: true
    field :description, String.t()
    field :locations, [location()], default: []
    field :args, %{String.t() => InputValue.t()}, default: %{}
  end
end
