defmodule Grephql.Validator.Error do
  @moduledoc false
  use TypedStructor

  @type severity() :: :error | :warning

  typed_structor do
    field :message, String.t(), enforce: true
    field :line, non_neg_integer()
    field :severity, severity(), default: :error
  end
end
