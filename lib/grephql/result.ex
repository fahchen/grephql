defmodule Grephql.Result do
  @moduledoc """
  Represents a GraphQL response.

  Contains the decoded `data` (typed per-query), any `errors`
  returned by the server, and an `assigns` map for user-defined
  metadata populated via Req response steps.

  ## Examples

      {:ok, %Grephql.Result{data: %MyClient.GetUser.Result.User{name: "Alice"}, errors: []}}
      {:ok, %Grephql.Result{data: nil, errors: [%Grephql.Error{message: "Not found"}]}}

  ## Assigns

  The `assigns` field lets you capture arbitrary response metadata
  (e.g. rate-limit info from a GraphQL `extensions` field) by using
  a Req response step in your client's `prepare_req/1` callback:

      defmodule MyApp.Shopify do
        use Grephql,
          otp_app: :my_app,
          source: "priv/shopify_schema.json"

        def prepare_req(req) do
          Req.Request.append_response_steps(req,
            shopify_extensions: fn {req, resp} ->
              extensions = resp.body["extensions"]
              {req, Grephql.Result.put_resp_assign(resp, :extensions, extensions)}
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

  alias Grephql.Error

  @grephql_private_key :grephql

  typed_structor do
    parameter :data_type

    field :data, data_type
    field :errors, [Error.t()], default: []
    field :assigns, map(), default: %{}
  end

  @type t() :: t(struct())

  @doc """
  Stores a key-value pair in the Grephql assigns area of a `Req.Response`.

  Intended for use inside Req response steps. The stored assigns are
  automatically transferred to `%Grephql.Result{assigns: ...}` after
  the response is decoded.
  """
  @spec put_resp_assign(Req.Response.t(), atom(), term()) :: Req.Response.t()
  def put_resp_assign(%Req.Response{} = resp, key, value) when is_atom(key) do
    assigns =
      resp.private
      |> Map.get(@grephql_private_key, %{})
      |> Map.put(key, value)

    put_in(resp.private[@grephql_private_key], assigns)
  end

  @doc false
  @spec assigns_from_response(Req.Response.t()) :: map()
  def assigns_from_response(%Req.Response{private: private}) do
    Map.get(private, @grephql_private_key, %{})
  end
end
