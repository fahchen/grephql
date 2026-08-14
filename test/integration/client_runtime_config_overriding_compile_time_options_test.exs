defmodule TypedGql.Integration.ClientRuntimeConfigOverridingCompileTimeOptionsTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: the three-layer config chain — call-site opts override
  # runtime Application config, which overrides compile-time use options.
  # setup_all installs the runtime layer for the whole file, so every test
  # observes the same runtime config.
  use ExUnit.Case, async: true

  alias TypedGql.Result

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://compile.example.com/graphql"

    defgql(:get_user, """
    query GetUser($id: ID!) {
      user(id: $id) {
        id
        name
      }
    }
    """)
  end

  setup_all do
    # Scoped put_env: the env key is this file's own Client module, which no
    # other test can reference, so no sibling test reads it.
    Application.put_env(:typed_gql, Client, endpoint: "https://runtime.example.com/graphql")
    on_exit(fn -> Application.delete_env(:typed_gql, Client) end)
    :ok
  end

  setup {Req.Test, :verify_on_exit!}

  describe "config precedence" do
    test "runtime Application config endpoint overrides the compile-time endpoint" do
      conn = capture_conn()

      assert conn.host == "runtime.example.com"
    end

    test "call-site opts override the runtime config endpoint" do
      conn = capture_conn(endpoint: "https://callsite.example.com/graphql")

      assert conn.host == "callsite.example.com"
    end

    test "call-site req_options merge in while the runtime endpoint still holds" do
      conn = capture_conn(req_options: [headers: [{"x-config-layer", "call-site"}]])

      assert conn.host == "runtime.example.com"
      assert Plug.Conn.get_req_header(conn, "x-config-layer") == ["call-site"]
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
    {extra_req_options, other_opts} = Keyword.pop(opts, :req_options, [])
    req_options = [plug: {Req.Test, Client}] ++ extra_req_options

    Client.get_user(%{id: "u1"}, [req_options: req_options] ++ other_opts)
  end
end
