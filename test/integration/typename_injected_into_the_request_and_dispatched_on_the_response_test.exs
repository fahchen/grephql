defmodule TypedGql.Integration.TypenameInjectedIntoTheRequestAndDispatchedOnTheResponseTest do
  @moduledoc """
  The `__typename` round trip, for a document that never mentions it:

  - the source document carries no `__typename`, and the request sent does,
    once per abstract selection
  - a union element decodes to the variant its `__typename` names
  - two payloads differing only in `__typename` decode to different structs,
    so dispatch reads that field rather than guessing from the other keys
  - the same holds for an interface selection
  """
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [plug: {Req.Test, __MODULE__}]

    @document """
    query TypenameRoundTrip($term: String!, $ids: [ID!]!) {
      search(query: $term) {
        ... on User { id name }
        ... on Post { id title }
      }
      nodes(ids: $ids) {
        id
        ... on User { name }
        ... on Post { title }
      }
    }
    """

    # Interpolated, not passed as the attribute itself, so defgql sees a binary
    # while the test can still assert on the very same source string.
    defgql(:round_trip, "#{@document}")

    @doc false
    def document, do: @document
  end

  describe "dumped request" do
    test "the source document asks for no __typename" do
      refute Client.document() =~ "__typename"
    end

    test "the request carries one __typename per abstract selection" do
      request = capture_request()

      assert request["query"] =~ "__typename"
      assert length(:binary.matches(request["query"], "__typename")) == 2
    end
  end

  describe "loaded response" do
    test "a union element decodes to the variant its __typename names" do
      result = fetch(search: [%{"__typename" => "Post", "id" => "p1", "title" => "Hello"}])

      assert [%Client.RoundTrip.Result.Search.Post{id: "p1", title: "Hello"}] = result.data.search
    end

    # The two payloads carry the same keys, so only __typename can be deciding.
    test "payloads differing only in __typename decode to different structs" do
      as_user = fetch(search: [%{"__typename" => "User", "id" => "x1"}])
      as_post = fetch(search: [%{"__typename" => "Post", "id" => "x1"}])

      assert [%Client.RoundTrip.Result.Search.User{id: "x1"}] = as_user.data.search
      assert [%Client.RoundTrip.Result.Search.Post{id: "x1"}] = as_post.data.search
    end

    test "an interface element dispatches on __typename the same way" do
      result =
        fetch(
          nodes: [
            %{"__typename" => "User", "id" => "u1", "name" => "Alice"},
            %{"__typename" => "Post", "id" => "p1", "title" => "Hello"}
          ]
        )

      assert [
               %Client.RoundTrip.Result.Nodes.User{id: "u1", name: "Alice"},
               %Client.RoundTrip.Result.Nodes.Post{id: "p1", title: "Hello"}
             ] = result.data.nodes
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

  defp fetch(data) do
    payload =
      %{"search" => [], "nodes" => []}
      |> Map.merge(Map.new(data, fn {k, v} -> {to_string(k), v} end))

    Req.Test.expect(Client, fn conn -> Req.Test.json(conn, %{"data" => payload}) end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp call do
    Client.round_trip(%{term: "elixir", ids: ["u1", "p1"]})
  end
end
