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

  The `assigns` field lets you capture arbitrary response metadata
  (e.g. rate-limit info from a GraphQL `extensions` field) by using
  a Req response step in your client's `prepare_req/1` callback:

      defmodule MyApp.Shopify do
        use TypedGql,
          otp_app: :my_app,
          source: "priv/shopify_schema.json"

        def prepare_req(req) do
          Req.Request.append_response_steps(req,
            shopify_extensions: fn {req, resp} ->
              extensions = resp.body["extensions"]
              {req, TypedGql.Result.put_resp_assign(resp, :extensions, extensions)}
            end
          )
        end

        defgql :get_products, ~GQL\"\"\"
          query { products(first: 10) { edges { node { title } } } }
        \"\"\"
      end

      {:ok, result} = MyApp.Shopify.get_products()
      result.assigns[:extensions]["cost"]["throttleStatus"]
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

  # `data` is nil whenever the server answers with "data": null, so the
  # unparameterized form has to admit it.
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
