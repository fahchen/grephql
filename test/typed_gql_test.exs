defmodule TypedGqlTest do
  use ExUnit.Case, async: true

  alias TypedGql.OperationInfo
  alias TypedGql.Result

  setup {Req.Test, :verify_on_exit!}

  describe "execute/3" do
    defmodule ExecuteClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "support/schemas/minimal.json",
        endpoint: "https://api.example.com/graphql"

      defgql(:get_user, "query GetUser($id: ID!) { user(id: $id) { name email } }")
      defgql(:get_default_user, "query { user(id: \"1\") { name } }")
    end

    test "successful response with data" do
      Req.Test.stub(ExecuteClient, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["query"] =~ "GetUser"
        assert request["variables"] == %{"id" => "42"}
        assert request["operationName"] == "GetUser"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{"user" => %{"name" => "Alice", "email" => "alice@example.com"}}
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               ExecuteClient.get_user(%{id: "42"}, req_options: [plug: {Req.Test, ExecuteClient}])

      assert result.data.user.name == "Alice"
      assert result.data.user.email == "alice@example.com"
      assert result.errors == []
    end

    test "successful response with errors only" do
      Req.Test.stub(ExecuteClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => nil,
            "errors" => [%{"message" => "Not found", "path" => ["user"]}]
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               ExecuteClient.get_user(%{id: "99"}, req_options: [plug: {Req.Test, ExecuteClient}])

      assert result.data == nil
      assert [error] = result.errors
      assert error.message == "Not found"
    end

    test "successful response with partial data and errors" do
      Req.Test.stub(ExecuteClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{"user" => %{"name" => "Alice", "email" => nil}},
            "errors" => [%{"message" => "email is restricted", "path" => ["user", "email"]}]
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               ExecuteClient.get_user(%{id: "1"}, req_options: [plug: {Req.Test, ExecuteClient}])

      assert result.data.user.name == "Alice"
      assert [error] = result.errors
      assert error.message == "email is restricted"
    end

    test "non-2xx response returns error" do
      Req.Test.stub(ExecuteClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "Internal Server Error"}))
      end)

      assert {:error, %Req.Response{status: 500}} =
               ExecuteClient.get_user(%{id: "1"}, req_options: [plug: {Req.Test, ExecuteClient}])
    end

    test "invalid variables return changeset error" do
      assert {:error, %Ecto.Changeset{}} = ExecuteClient.get_user(%{})
    end

    test "query without variables" do
      Req.Test.stub(ExecuteClient, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["variables"] == %{}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{"user" => %{"name" => "Default"}}
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               ExecuteClient.get_default_user(req_options: [plug: {Req.Test, ExecuteClient}])

      assert result.data.user.name == "Default"
    end

    test "transport error returns {:error, exception}" do
      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               ExecuteClient.get_default_user(
                 req_options: [
                   retry: false,
                   adapter: fn req ->
                     {req, %Req.TransportError{reason: :econnrefused}}
                   end
                 ]
               )
    end

    defmodule NoEndpointClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "support/schemas/minimal.json"

      defgql(:get_user, "query { user(id: \"1\") { name } }")
    end

    test "no endpoint: the URL can come from :req_options instead" do
      Req.Test.stub(NoEndpointClient, fn conn ->
        assert conn.host == "api.example.com"
        assert conn.request_path == "/graphql"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => %{"user" => %{"name" => "Base"}}}))
      end)

      assert {:ok, %Result{} = result} =
               NoEndpointClient.get_user(
                 req_options: [
                   base_url: "https://api.example.com/graphql",
                   plug: {Req.Test, NoEndpointClient}
                 ]
               )

      assert result.data.user.name == "Base"
    end

    test "no endpoint: the URL can be passed at execution time" do
      Req.Test.stub(NoEndpointClient, fn conn ->
        assert conn.host == "api.example.com"
        assert conn.request_path == "/graphql"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => %{"user" => %{"name" => "Url"}}}))
      end)

      assert {:ok, %Result{} = result} =
               NoEndpointClient.get_user(
                 req_options: [
                   url: "https://api.example.com/graphql",
                   plug: {Req.Test, NoEndpointClient}
                 ]
               )

      assert result.data.user.name == "Url"
    end

    defmodule StubbedClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "support/schemas/minimal.json",
        endpoint: "https://api.example.com/graphql",
        req_options: [plug: {Req.Test, TypedGqlTest.StubbedClient}]

      defgql(:get_user, "query { user(id: \"1\") { name } }")
    end

    test "execute/1 uses the default variables and options" do
      Req.Test.stub(StubbedClient, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        # execute/1 defaults variables to %{}, and the query is anonymous so no
        # operationName is sent.
        assert request["variables"] == %{}
        refute Map.has_key?(request, "operationName")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"errors" => [%{"message" => "boom"}]}))
      end)

      query = %TypedGql.Query{
        document: "query { user(id: \"1\") { name } }",
        operation_type: "query",
        client_module: StubbedClient,
        result_module: nil
      }

      assert {:ok, %Result{data: nil}} = TypedGql.execute(query)
    end

    test "a non-JSON body is reported as an error" do
      Req.Test.stub(StubbedClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "not json at all")
      end)

      # The error's module depends on the JSON library: Elixir's JSON reports a
      # tuple that normalize_error wraps in a RuntimeError, while the Jason
      # fallback on Elixir < 1.18 raises its own DecodeError exception.
      assert {:error, error} = StubbedClient.get_user()
      assert is_exception(error)
    end

    test "no URL at all fails in Req" do
      assert_raise ArgumentError, ~r/scheme is required/, fn ->
        NoEndpointClient.get_user()
      end
    end

    test "execute opts override config" do
      Req.Test.stub(ExecuteClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{"user" => %{"name" => "Alice"}}
          })
        )
      end)

      assert {:ok, %Result{}} =
               ExecuteClient.get_default_user(
                 endpoint: "https://override.example.com/graphql",
                 req_options: [plug: {Req.Test, ExecuteClient}]
               )
    end

    test "prepare_req callback populates assigns from response" do
      defmodule PrepareReqClient do
        use TypedGql,
          otp_app: :typed_gql,
          source: "support/schemas/minimal.json",
          endpoint: "https://api.example.com/graphql"

        def prepare_req(req) do
          Req.Request.append_response_steps(req,
            capture_extensions: fn {req, resp} ->
              {req, TypedGql.Result.put_resp_assign(resp, :extensions, resp.body["extensions"])}
            end
          )
        end

        defgql(:get_user, "query { user(id: \"1\") { name } }")
      end

      Req.Test.stub(PrepareReqClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{"user" => %{"name" => "Alice"}},
            "extensions" => %{
              "cost" => %{
                "requestedQueryCost" => 12,
                "throttleStatus" => %{"currentlyAvailable" => 980}
              }
            }
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               PrepareReqClient.get_user(req_options: [plug: {Req.Test, PrepareReqClient}])

      assert result.data.user.name == "Alice"
      assert result.assigns.extensions["cost"]["requestedQueryCost"] == 12
      assert result.assigns.extensions["cost"]["throttleStatus"]["currentlyAvailable"] == 980
    end

    test "assigns default to empty map when prepare_req is not overridden" do
      Req.Test.stub(ExecuteClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{"user" => %{"name" => "Alice", "email" => "alice@example.com"}}
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               ExecuteClient.get_user(%{id: "1"}, req_options: [plug: {Req.Test, ExecuteClient}])

      assert result.assigns == %{}
    end

    test "assigns survive when response body is raw binary" do
      defmodule RawBodyClient do
        use TypedGql,
          otp_app: :typed_gql,
          source: "support/schemas/minimal.json",
          endpoint: "https://api.example.com/graphql"

        def prepare_req(req) do
          req
          |> Req.Request.append_response_steps(
            capture_request_id: fn {req, resp} ->
              {req, TypedGql.Result.put_resp_assign(resp, :request_id, "test-123")}
            end
          )
          |> Req.merge(decode_body: false)
        end

        defgql(:get_user, "query { user(id: \"1\") { name } }")
      end

      Req.Test.stub(RawBodyClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{"data" => %{"user" => %{"name" => "Alice"}}})
        )
      end)

      assert {:ok, %Result{} = result} =
               RawBodyClient.get_user(req_options: [plug: {Req.Test, RawBodyClient}])

      assert result.data.user.name == "Alice"
      assert result.assigns.request_id == "test-123"
    end

    test "per-call req_options merge with compile-time config, not replace" do
      defmodule MergeClient do
        use TypedGql,
          otp_app: :typed_gql,
          source: "support/schemas/minimal.json",
          endpoint: "https://api.example.com/graphql",
          req_options: [plug: {Req.Test, __MODULE__}]

        defgql(:get_user, "query { user(id: \"1\") { name } }")
      end

      Req.Test.stub(MergeClient, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-custom") == ["hello"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{"data" => %{"user" => %{"name" => "Merged"}}})
        )
      end)

      # Per-call header should NOT clobber compile-time plug
      assert {:ok, %Result{} = result} =
               MergeClient.get_user(req_options: [headers: [{"x-custom", "hello"}]])

      assert result.data.user.name == "Merged"
    end
  end

  describe "OperationInfo.attach/1 + get/1" do
    defmodule OpInfoClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "support/schemas/minimal.json",
        endpoint: "https://api.example.com/graphql"

      def prepare_req(req), do: TypedGql.OperationInfo.attach(req)

      defgql(:get_user, "query GetUser($id: ID!) { user(id: $id) { name } }")
      defgql(:get_default_user, "query { user(id: \"1\") { name } }")
    end

    test "opted-in named operation exposes function/client/operation" do
      Req.Test.expect(OpInfoClient, fn conn ->
        assert OperationInfo.get(conn) == %{
                 function: "get_user",
                 client: inspect(OpInfoClient),
                 operation: "GetUser"
               }

        json_ok(conn, %{"user" => %{"name" => "Alice"}})
      end)

      assert {:ok, %Result{}} =
               OpInfoClient.get_user(%{id: "1"}, req_options: [plug: {Req.Test, OpInfoClient}])
    end

    test "opted-in anonymous query omits the operation" do
      Req.Test.expect(OpInfoClient, fn conn ->
        assert OperationInfo.get(conn) == %{
                 function: "get_default_user",
                 client: inspect(OpInfoClient),
                 operation: nil
               }

        json_ok(conn, %{"user" => %{"name" => "Default"}})
      end)

      assert {:ok, %Result{}} =
               OpInfoClient.get_default_user(req_options: [plug: {Req.Test, OpInfoClient}])
    end

    test "without opting in, no operation info is sent" do
      client = TypedGqlTest.ExecuteClient

      Req.Test.expect(client, fn conn ->
        assert OperationInfo.get(conn) == %{function: nil, client: nil, operation: nil}

        json_ok(conn, %{"user" => %{"name" => "Alice"}})
      end)

      assert {:ok, %Result{}} =
               client.get_default_user(req_options: [plug: {Req.Test, client}])
    end

    test "attached step is a no-op on requests that carry no query" do
      req =
        [url: "https://api.example.com/graphql", plug: {Req.Test, OpInfoClient}]
        |> Req.new()
        |> OperationInfo.attach()

      Req.Test.expect(OpInfoClient, fn conn ->
        assert OperationInfo.get(conn) == %{function: nil, client: nil, operation: nil}

        json_ok(conn, %{})
      end)

      assert {:ok, %Req.Response{status: 200}} = Req.post(req)
    end

    test "distinguishes multiple functions on the same client" do
      Req.Test.expect(OpInfoClient, 2, fn conn ->
        name = if OperationInfo.get(conn).function == "get_user", do: "Named", else: "Default"

        json_ok(conn, %{"user" => %{"name" => name}})
      end)

      assert {:ok, %Result{} = named} =
               OpInfoClient.get_user(%{id: "1"}, req_options: [plug: {Req.Test, OpInfoClient}])

      assert {:ok, %Result{} = default} =
               OpInfoClient.get_default_user(req_options: [plug: {Req.Test, OpInfoClient}])

      assert named.data.user.name == "Named"
      assert default.data.user.name == "Default"
    end
  end

  defp json_ok(conn, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => data}))
  end
end
