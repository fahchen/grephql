defmodule TypedGql.Integration.TransportHttpStatusAndMalformedBodyErrorTuplesTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: everything below the GraphQL layer — HTTP status
  # failures, transport failures, and undecodable bodies — surfaces as
  # {:error, _} tuples rather than raising or masquerading as results.
  use ExUnit.Case, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql"

    defgql(:get_user, """
    query GetUser($id: ID!) {
      user(id: $id) {
        id
        name
      }
    }
    """)
  end

  setup {Req.Test, :verify_on_exit!}

  describe "transport and HTTP errors" do
    test "every non-2xx status returns the response struct as an error tuple" do
      for status <- [400, 401, 500] do
        assert {:error, %Req.Response{status: ^status}} = fetch_status(status)
      end
    end

    test "the error response preserves the server body" do
      assert {:error, %Req.Response{body: body}} = fetch_status(401)

      assert body == %{"message" => "http 401"}
    end

    test "a transport error returns the exception from the adapter" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               Client.get_user(
                 %{id: "u1"},
                 req_options: [
                   retry: false,
                   adapter: fn req -> {req, %Req.TransportError{reason: :timeout}} end
                 ]
               )
    end

    test "a 200 response with a non-JSON body returns a decode exception" do
      Req.Test.expect(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html>gateway page</html>")
      end)

      assert {:error, error} = call()
      assert is_exception(error)
    end
  end

  defp fetch_status(status) do
    Req.Test.expect(Client, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{"message" => "http #{status}"})
    end)

    # retry: false keeps Req from re-invoking the single-use stub on 500
    call(retry: false)
  end

  defp call(extra_req_options \\ []) do
    Client.get_user(
      %{id: "u1"},
      req_options: [plug: {Req.Test, Client}] ++ extra_req_options
    )
  end
end
