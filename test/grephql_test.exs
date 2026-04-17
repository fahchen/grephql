defmodule GrephqlTest do
  use ExUnit.Case, async: true

  alias Grephql.Result

  describe "execute/3" do
    defmodule ExecuteClient do
      use Grephql,
        otp_app: :grephql,
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

    test "raises when endpoint is not configured" do
      defmodule NoEndpointClient do
        use Grephql,
          otp_app: :grephql,
          source: "support/schemas/minimal.json"

        defgql(:get_user, "query { user(id: \"1\") { name } }")
      end

      assert_raise ArgumentError, ~r/endpoint is required/, fn ->
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
        use Grephql,
          otp_app: :grephql,
          source: "support/schemas/minimal.json",
          endpoint: "https://api.example.com/graphql"

        def prepare_req(req) do
          Req.Request.append_response_steps(req,
            capture_extensions: fn {req, resp} ->
              {req, Grephql.Result.put_resp_assign(resp, :extensions, resp.body["extensions"])}
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
        use Grephql,
          otp_app: :grephql,
          source: "support/schemas/minimal.json",
          endpoint: "https://api.example.com/graphql"

        def prepare_req(req) do
          req
          |> Req.Request.append_response_steps(
            capture_request_id: fn {req, resp} ->
              {req, Grephql.Result.put_resp_assign(resp, :request_id, "test-123")}
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
        use Grephql,
          otp_app: :grephql,
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
end
