defmodule TypedGql.Integration.OperationVariablesCarryingDefaultValuesTest do
  @moduledoc """
  Variables an operation declares a default value for:

  - a nullable variable with a default satisfies a non-null argument (spec 5.8.5)
  - a variable with a default is optional for the caller, whatever its nullability
  - an omitted defaulted variable is left out of the request, so the server applies
    the default rather than receiving an explicit null
  - a value passed for a defaulted variable is sent and overrides the default
  - a non-null variable without a default is still required
  """
  use TypedGql.IntegrationCase, async: true

  import TypedGql.Test.Helpers, only: [errors_on: 2]

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug: {Req.Test, __MODULE__}
      ]

    # $term is nullable but defaulted, and `search(query:)` takes String! —
    # allowed because the default guarantees the argument never sees null.
    defgql(:search_defaulted, """
    query SearchDefaulted($term: String = "elixir") {
      search(query: $term) {
        ... on User { id name }
      }
    }
    """)

    defgql(:search_non_null_defaulted, """
    query SearchNonNullDefaulted($term: String! = "elixir") {
      search(query: $term) {
        ... on User { id }
      }
    }
    """)

    defgql(:search_required, """
    query SearchRequired($term: String!) {
      search(query: $term) {
        ... on User { id }
      }
    }
    """)
  end

  describe "dumped request" do
    test "an omitted defaulted variable is absent from the request, not null" do
      request = capture_request(fn -> Client.search_defaulted(%{}) end)

      assert request["variables"] == %{}
    end

    test "an omitted non-null defaulted variable is absent too" do
      request = capture_request(fn -> Client.search_non_null_defaulted(%{}) end)

      assert request["variables"] == %{}
    end

    test "a value passed for a defaulted variable overrides the default on the wire" do
      request = capture_request(fn -> Client.search_defaulted(%{term: "erlang"}) end)

      assert request["variables"] == %{"term" => "erlang"}
    end

    test "the printed document keeps the default value declaration" do
      request = capture_request(fn -> Client.search_defaulted(%{}) end)

      assert request["query"] =~ ~s($term: String = "elixir")
    end
  end

  describe "changeset validation" do
    test "a non-null variable without a default is still required" do
      assert {:error, %Ecto.Changeset{} = changeset} = Client.search_required(%{})

      assert "can't be blank" in errors_on(changeset, :term)
    end
  end

  describe "loaded response" do
    test "the response decodes normally when the server applied the default" do
      Req.Test.expect(Client, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{"search" => [%{"__typename" => "User", "id" => "u1", "name" => "Alice"}]}
        })
      end)

      assert {:ok, %Result{} = result} = Client.search_defaulted(%{})

      assert [%Client.SearchDefaulted.Result.Search.User{id: "u1", name: "Alice"}] =
               result.data.search
    end
  end

  defp capture_request(call) do
    parent = self()

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = call.()
    assert_received {:request, request}
    request
  end
end
