defmodule TypedGql.OperationInfoTest do
  use ExUnit.Case, async: true

  alias TypedGql.OperationInfo
  alias TypedGql.Result

  setup {Req.Test, :verify_on_exit!}

  defmodule OptedIn do
    @moduledoc false
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/minimal.json",
      endpoint: "https://api.example.com/graphql"

    def prepare_req(req), do: TypedGql.OperationInfo.attach(req)

    defgql(:get_user, "query GetUser($id: ID!) { user(id: $id) { name } }")
    defgql(:get_default_user, "query { user(id: \"1\") { name } }")
  end

  defmodule OptedOut do
    @moduledoc false
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/minimal.json",
      endpoint: "https://api.example.com/graphql"

    defgql(:get_default_user, "query { user(id: \"1\") { name } }")
  end

  describe "attach/1" do
    test "stamps the defgql function name on the request" do
      opts = expect_call(OptedIn, &assert(header(&1, "x-typed-gql-function") == ["get_user"]))

      assert {:ok, %Result{}} = OptedIn.get_user(%{id: "1"}, opts)
    end

    test "stamps the client module on the request" do
      client = inspect(TypedGql.OperationInfoTest.OptedIn)
      opts = expect_call(OptedIn, &assert(header(&1, "x-typed-gql-client") == [client]))

      assert {:ok, %Result{}} = OptedIn.get_user(%{id: "1"}, opts)
    end

    test "stamps the GraphQL operation name on the request" do
      opts = expect_call(OptedIn, &assert(header(&1, "x-typed-gql-operation") == ["GetUser"]))

      assert {:ok, %Result{}} = OptedIn.get_user(%{id: "1"}, opts)
    end

    test "omits the operation header for an anonymous operation" do
      opts = expect_call(OptedIn, &assert(header(&1, "x-typed-gql-operation") == []))

      assert {:ok, %Result{}} = OptedIn.get_default_user(opts)
    end
  end

  describe "get/1" do
    test "reads the stamped values back off the conn" do
      expected = %{
        function: "get_user",
        client: inspect(TypedGql.OperationInfoTest.OptedIn),
        operation: "GetUser"
      }

      opts = expect_call(OptedIn, &assert(OperationInfo.get(&1) == expected))

      assert {:ok, %Result{}} = OptedIn.get_user(%{id: "1"}, opts)
    end

    test "returns nil for every value on a conn carrying no headers" do
      # A client that never attaches the step: `get/1` still answers, so one stub
      # shared with un-instrumented clients can branch instead of crashing.
      opts =
        expect_call(
          OptedOut,
          &assert(OperationInfo.get(&1) == %{function: nil, client: nil, operation: nil})
        )

      assert {:ok, %Result{}} = OptedOut.get_default_user(opts)
    end
  end

  # Expects exactly one call on the client's stub, runs `assertion` against the
  # conn it receives, and returns the options that route the call to that stub.
  defp expect_call(client, assertion) do
    Req.Test.expect(client, fn conn ->
      assertion.(conn)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => %{"user" => %{"name" => "Alice"}}}))
    end)

    [req_options: [plug: {Req.Test, client}]]
  end

  defp header(conn, name), do: Plug.Conn.get_req_header(conn, name)
end
