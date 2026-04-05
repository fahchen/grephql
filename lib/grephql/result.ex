defmodule Grephql.Result do
  @moduledoc """
  Represents a GraphQL response.

  Contains the decoded `data` (typed per-query) and any `errors`
  returned by the server. The type parameter `data_type` allows
  `defgql`-generated functions to specify the concrete result type.

  ## Examples

      {:ok, %Grephql.Result{data: %MyClient.GetUser.Result.User{name: "Alice"}, errors: []}}
      {:ok, %Grephql.Result{data: nil, errors: [%Grephql.Error{message: "Not found"}]}}
  """

  use TypedStructor

  alias Grephql.Error

  typed_structor do
    parameter :data_type

    field :data, data_type | nil
    field :errors, [Error.t()], default: []
  end

  @type t() :: t(struct())
end
