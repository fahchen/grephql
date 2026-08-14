defmodule TypedGql.Integration.OperationWithoutVariablesAndEndpointOverrideAtCallSiteTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: common call-site behaviors — a no-variable operation
  # generates an opts-only function, and the endpoint can be overridden per
  # call. The document goes through the ~GQL sigil to exercise that path.
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug:
          {Req.Test,
           TypedGql.Integration.OperationWithoutVariablesAndEndpointOverrideAtCallSiteTest.Client}
      ]

    defgql(:list_users, ~GQL"""
    query ListUsers {
      users {
        id
        name
        role
      }
    }
    """)
  end

  describe "generated shape" do
    test "a no-variable operation exports an opts-only function, not a variables arity" do
      assert function_exported?(Client, :list_users, 0)
      assert function_exported?(Client, :list_users, 1)
      refute function_exported?(Client, :list_users, 2)
    end

    test "no Variables module is generated when the operation declares none" do
      refute Code.ensure_loaded?(Client.ListUsers.Variables)
    end
  end

  describe "dumped request" do
    test "the body carries an empty variables map under the ListUsers operation name" do
      request = capture_request()

      assert request["operationName"] == "ListUsers"
      assert request["variables"] == %{}
    end

    test "an endpoint given in call-site opts overrides the compile-time endpoint" do
      Req.Test.expect(Client, fn conn ->
        assert conn.host == "staging.example.com"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, %Result{}} = call(endpoint: "https://staging.example.com/graphql")
    end
  end

  describe "loaded response" do
    test "the list decodes into typed structs" do
      result = fetch()

      assert [
               %Client.ListUsers.Result.Users{id: "u1", name: "Alice", role: :admin},
               %Client.ListUsers.Result.Users{id: "u2", name: "Bob", role: :user}
             ] = result.data.users
    end
  end

  defp capture_request do
    parent = self()

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = call()
    assert_received {:request, request}
    request
  end

  defp fetch do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "users" => [
            %{"id" => "u1", "name" => "Alice", "role" => "ADMIN"},
            %{"id" => "u2", "name" => "Bob", "role" => "USER"}
          ]
        }
      })
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp call(extra_opts \\ []) do
    Client.list_users(extra_opts)
  end
end
