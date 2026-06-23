defmodule TypedGql.OperationInfo do
  @moduledoc """
  Tags outgoing requests with their originating `defgql` operation so that
  multiple requests can be told apart — most usefully inside `Req.Test` stubs.

  This is a Req plugin: attach it to opt in, then read the info back from the
  test `conn`.

  ## Opt in

  Attach from your client's `prepare_req/1` callback. Define it conditionally
  so it only takes effect in the environments you want (e.g. `:test`):

      defmodule MyApp.GitHub do
        use TypedGql, otp_app: :my_app, source: "priv/schemas/github.json"

        if Mix.env() == :test do
          def prepare_req(req), do: TypedGql.OperationInfo.attach(req)
        end

        defgql :get_user, "query GetUser($id: ID!) { user(id: $id) { name } }"
      end

  ## Read it back

      Req.Test.stub(MyApp.GitHub, fn conn ->
        case TypedGql.OperationInfo.get(conn) do
          %{function: "get_user"} -> # ...
        end
      end)

  ## Use in tests

  The main use is telling apart multiple operations that share one `Req.Test`
  stub/expect, so a single mock can answer each `defgql` function differently:

      test "page renders user and their posts" do
        Req.Test.expect(MyApp.GitHub, 2, fn conn ->
          case TypedGql.OperationInfo.get(conn).function do
            "get_user" -> Req.Test.json(conn, %{"data" => %{"user" => %{"name" => "Alice"}}})
            "list_posts" -> Req.Test.json(conn, %{"data" => %{"posts" => []}})
          end
        end)

        # ... exercise code that calls both MyApp.GitHub.get_user/1 and list_posts/1
      end

  Without it, a shared stub cannot distinguish requests whose only difference
  is which `defgql` function produced them (anonymous operations have no
  `operationName` in the body to branch on).

  When attached, every request carries up to three headers:

    * `x-typed-gql-function` — the `defgql` function name (e.g. `get_user`)
    * `x-typed-gql-client` — the client module (e.g. `MyApp.GitHub`)
    * `x-typed-gql-operation` — the GraphQL operation name (omitted for
      anonymous operations)
  """

  alias TypedGql.Query

  @function_header "x-typed-gql-function"
  @client_header "x-typed-gql-client"
  @operation_header "x-typed-gql-operation"

  @doc """
  Attaches the operation-info request step. Opt in from `prepare_req/1`.
  """
  @spec attach(Req.Request.t()) :: Req.Request.t()
  def attach(%Req.Request{} = request) do
    Req.Request.append_request_steps(request, typed_gql_operation_info: &put_headers/1)
  end

  defp put_headers(%Req.Request{} = request) do
    case Map.get(request.private, :typed_gql_query) do
      %Query{} = query ->
        request
        |> Req.Request.put_header(@function_header, to_string(query.function_name))
        |> Req.Request.put_header(@client_header, inspect(query.client_module))
        |> maybe_put_operation(query.operation_name)

      nil ->
        request
    end
  end

  defp maybe_put_operation(request, nil), do: request

  defp maybe_put_operation(request, operation),
    do: Req.Request.put_header(request, @operation_header, operation)

  if Code.ensure_loaded?(Plug.Conn) do
    @doc """
    Reads the attached operation info back from a `Req.Test` `conn`.

    Returns a map with `:function`, `:client`, and `:operation` (each a string
    or `nil` when the corresponding header is absent).
    """
    @spec get(Plug.Conn.t()) :: %{
            function: String.t() | nil,
            client: String.t() | nil,
            operation: String.t() | nil
          }
    def get(%Plug.Conn{} = conn) do
      %{
        function: first_header(conn, @function_header),
        client: first_header(conn, @client_header),
        operation: first_header(conn, @operation_header)
      }
    end

    defp first_header(conn, name) do
      case Plug.Conn.get_req_header(conn, name) do
        [value | _rest] -> value
        [] -> nil
      end
    end
  end
end
