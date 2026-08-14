defmodule TypedGql.Integration.QuerySelectingTypenameExplicitlyOnAnObjectTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: the user selecting __typename themselves — on a plain
  # object, and on a union whose selection already gets __typename injected
  # automatically. Pins that __typename decodes to a downcased atom, not
  # the raw string the server sent.
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug:
          {Req.Test, TypedGql.Integration.QuerySelectingTypenameExplicitlyOnAnObjectTest.Client}
      ]

    defgql(:tagged_user, """
    query TaggedUser($id: ID!, $term: String!) {
      user(id: $id) {
        __typename
        id
      }
      search(query: $term) {
        __typename
        ... on User {
          name
        }
        ... on Post {
          title
        }
      }
    }
    """)
  end

  describe "generated shape" do
    test "an explicit __typename becomes a struct field of the Typename type" do
      user_mod = Client.TaggedUser.Result.User

      assert :__typename in user_mod.__schema__(:fields)

      assert {:parameterized, {TypedGql.Types.Typename, %{string_to_atom: %{"User" => :user}}}} =
               user_mod.__schema__(:type, :__typename)
    end
  end

  describe "dumped request" do
    test "an explicitly selected __typename is not duplicated by the automatic injection" do
      request = capture_request()

      selections_after_search =
        request["query"] |> String.split("search(query: $term)") |> List.last()

      assert length(:binary.matches(selections_after_search, "__typename")) == 1
    end
  end

  describe "loaded response" do
    test "__typename on an object decodes to a downcased atom, not the wire string" do
      result = fetch()

      assert result.data.user.__typename == :user
    end

    test "__typename on union variants decodes per element" do
      result = fetch()

      assert [
               %Client.TaggedUser.Result.Search.User{__typename: :user, name: "Alice"},
               %Client.TaggedUser.Result.Search.Post{__typename: :post, title: "Hello"}
             ] = result.data.search
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
          "user" => %{"__typename" => "User", "id" => "u1"},
          "search" => [
            %{"__typename" => "User", "name" => "Alice"},
            %{"__typename" => "Post", "title" => "Hello"}
          ]
        }
      })
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp call do
    Client.tagged_user(%{id: "u1", term: "elixir"})
  end
end
