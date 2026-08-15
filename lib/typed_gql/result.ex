defmodule TypedGql.Result do
  @moduledoc """
  Represents a GraphQL response.

  Contains the decoded `data` (typed per-query), any `errors`
  returned by the server, and an `assigns` map for user-defined
  metadata populated via Req response steps.

  ## Examples

      {:ok, %TypedGql.Result{data: %MyClient.GetUser.Result.User{name: "Alice"}, errors: []}}
      {:ok, %TypedGql.Result{data: nil, errors: [%TypedGql.Error{message: "Not found"}]}}

  ## Assigns

  The `assigns` field carries response metadata a Req response step put
  there with `put_resp_assign/3` — rate-limit numbers from a GraphQL
  `extensions` field, say. See the
  [prepare_req guide](guides/extending-requests-with-prepare-req.md) for a
  worked client.
  """

  use TypedStructor

  alias TypedGql.Error

  @typed_gql_private_key :typed_gql

  typed_structor do
    parameter :data_type

    field :data, data_type
    field :errors, [Error.t()], default: []
    field :assigns, map(), default: %{}
  end

  # `data` is nil whenever there was nothing to decode — the response carried
  # "data": null or no "data" key at all, or the query has no result module —
  # so the unparameterized form has to admit it. Callers naming their own data
  # type add `| nil` themselves when they can receive it.
  @type t() :: t(struct() | nil)

  @doc """
  Stores a key-value pair in the TypedGql assigns area of a `Req.Response`.

  Intended for use inside Req response steps. The stored assigns are
  automatically transferred to `%TypedGql.Result{assigns: ...}` after
  the response is decoded.
  """
  @spec put_resp_assign(Req.Response.t(), atom(), term()) :: Req.Response.t()
  def put_resp_assign(%Req.Response{} = resp, key, value) when is_atom(key) do
    assigns =
      resp.private
      |> Map.get(@typed_gql_private_key, %{})
      |> Map.put(key, value)

    put_in(resp.private[@typed_gql_private_key], assigns)
  end

  @doc false
  @spec assigns_from_response(Req.Response.t()) :: map()
  def assigns_from_response(%Req.Response{private: private}) do
    Map.get(private, @typed_gql_private_key, %{})
  end
end
