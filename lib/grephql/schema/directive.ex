defmodule Grephql.Schema.Directive do
  @moduledoc false
  use TypedStructor

  alias Grephql.Schema.InputValue

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
