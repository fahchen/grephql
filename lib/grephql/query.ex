defmodule Grephql.Query do
  @moduledoc """
  Represents a compiled GraphQL operation ready for execution.

  Created at compile time by `defgql`/`defgqlp`.
  Contains the query string, operation metadata, and references to
  generated type modules.
  """

  use TypedStructor

  typed_structor do
    field :document, String.t(), enforce: true
    field :operation_name, String.t()
    field :result_module, module(), enforce: true
    field :variables_module, module()
    field :input_modules, [module()], default: []
    field :client_module, module(), enforce: true
    field :has_variables?, boolean(), default: false
  end
end
