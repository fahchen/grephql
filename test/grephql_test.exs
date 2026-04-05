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
  end
end
