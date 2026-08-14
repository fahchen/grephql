defmodule TypedGql.Integration.ClientCompileTimeReqOptionsOverriddenAtCallSiteTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: compile-time config layering without touching the
  # runtime Application env — the use options (endpoint + req_options) act
  # as defaults, and call-site opts override them per request.
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://compile.example.com/graphql",
      req_options: [
        plug:
          {Req.Test,
           TypedGql.Integration.ClientCompileTimeReqOptionsOverriddenAtCallSiteTest.Client},
        headers: [{"x-config-layer", "compile-time"}]
      ]

    defgql(:get_user, """
    query GetUser($id: ID!) {
      user(id: $id) {
        id
        name
      }
    }
    """)
  end

  describe "config precedence" do
    test "compile-time endpoint and req_options are the request defaults" do
      conn = capture_conn()

      assert conn.host == "compile.example.com"
      assert Plug.Conn.get_req_header(conn, "x-config-layer") == ["compile-time"]
    end

    test "a call-site endpoint overrides the compile-time endpoint, keeping other defaults" do
      conn = capture_conn(endpoint: "https://callsite.example.com/graphql")

      assert conn.host == "callsite.example.com"
      assert Plug.Conn.get_req_header(conn, "x-config-layer") == ["compile-time"]
    end

    test "call-site req_options override the same key set at compile time" do
      conn = capture_conn(req_options: [headers: [{"x-config-layer", "call-site"}]])

      assert conn.host == "compile.example.com"
      assert Plug.Conn.get_req_header(conn, "x-config-layer") == ["call-site"]
    end

    test "call-site req_options merge alongside compile-time ones for distinct keys" do
      conn = capture_conn(req_options: [headers: [{"x-request-id", "req-42"}]])

      assert Plug.Conn.get_req_header(conn, "x-config-layer") == ["compile-time"]
      assert Plug.Conn.get_req_header(conn, "x-request-id") == ["req-42"]
    end
  end

  defp capture_conn(opts \\ []) do
    parent = self()

    Req.Test.expect(Client, fn conn ->
      send(parent, {:conn, conn})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = call(opts)
    assert_received {:conn, conn}
    conn
  end

  defp call(opts) do
    Client.get_user(%{id: "u1"}, opts)
  end
end
