defmodule TypedGql.Integration.QuerySelectingUnionAndInterfaceVariantsViaFragmentsTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: union and interface selections with per-variant inline
  # fragments, whose bodies come from named fragments shared across the two
  # root fields.
  use ExUnit.Case, async: true

  alias TypedGql.Result

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql"

    defgql(:site_search, """
    query SiteSearch($term: String!, $ids: [ID!]!) {
      search(query: $term) {
        ... on User {
          ...UserCore
        }
        ... on Post {
          ...PostCore
          author {
            ...UserCore
          }
        }
      }
      nodes(ids: $ids) {
        id
        ... on User {
          name
        }
        ... on Post {
          title
        }
      }
    }

    fragment UserCore on User {
      id
      name
      role
    }

    fragment PostCore on Post {
      id
      title
      status
    }
    """)
  end

  setup {Req.Test, :verify_on_exit!}

  describe "generated shape" do
    test "union and interface selections lower to generated dispatcher types" do
      result_mod = Client.SiteSearch.Result

      assert {:array, {:parameterized, {Client.SiteSearch.Result.Search.Union, %{}}}} =
               result_mod.__schema__(:type, :search)

      assert {:array, {:parameterized, {Client.SiteSearch.Result.Nodes.Union, %{}}}} =
               result_mod.__schema__(:type, :nodes)
    end

    test "each variant gets its own struct module" do
      assert %Client.SiteSearch.Result.Search.User{} =
               struct(Client.SiteSearch.Result.Search.User)

      assert %Client.SiteSearch.Result.Search.Post{} =
               struct(Client.SiteSearch.Result.Search.Post)

      assert %Client.SiteSearch.Result.Nodes.User{} = struct(Client.SiteSearch.Result.Nodes.User)
      assert %Client.SiteSearch.Result.Nodes.Post{} = struct(Client.SiteSearch.Result.Nodes.Post)
    end
  end

  describe "dumped request" do
    test "named fragments are printed once at document level and spread in both variants" do
      request = capture_request()

      assert request["operationName"] == "SiteSearch"
      assert request["query"] =~ "fragment UserCore on User"
      assert request["query"] =~ "fragment PostCore on Post"
      assert request["query"] =~ "...UserCore"
      assert request["query"] =~ "...PostCore"
    end

    test "the list variable serializes as a JSON array" do
      request = capture_request()

      assert request["variables"] == %{"term" => "elixir", "ids" => ["u1", "p20"]}
    end
  end

  describe "loaded response" do
    test "union elements cast to their variant structs by __typename" do
      result = fetch()

      assert [
               %Client.SiteSearch.Result.Search.User{id: "u2", name: "Bob", role: :user},
               %Client.SiteSearch.Result.Search.Post{
                 id: "p20",
                 title: "Hello",
                 status: :published
               }
             ] = result.data.search
    end

    test "a fragment spread inside a variant decodes its nested object" do
      result = fetch()

      assert [_user, %{author: %{id: "u1", name: "Alice", role: :admin}}] = result.data.search
    end

    test "interface elements cast to variant structs and a null element survives" do
      result = fetch()

      assert [
               %Client.SiteSearch.Result.Nodes.User{id: "u1", name: "Alice"},
               nil,
               %Client.SiteSearch.Result.Nodes.Post{id: "p20", title: "Hello"}
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

  defp fetch do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "search" => [
            %{"__typename" => "User", "id" => "u2", "name" => "Bob", "role" => "USER"},
            %{
              "__typename" => "Post",
              "id" => "p20",
              "title" => "Hello",
              "status" => "PUBLISHED",
              "author" => %{"id" => "u1", "name" => "Alice", "role" => "ADMIN"}
            }
          ],
          "nodes" => [
            %{"__typename" => "User", "id" => "u1", "name" => "Alice"},
            nil,
            %{"__typename" => "Post", "id" => "p20", "title" => "Hello"}
          ]
        }
      })
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp call do
    Client.site_search(
      %{term: "elixir", ids: ["u1", "p20"]},
      req_options: [plug: {Req.Test, Client}]
    )
  end
end
