defmodule TypedGql.Integration.QueryMergingDuplicateSelectionsAcrossFragmentsAndFieldsTest do
  @moduledoc """
  FieldsInSetCanMerge in practice — the same response key selected from several
  places collapses into one selection:

  - a nested module unions the fields of the direct selection and the fragment
  - a scalar selected both directly and via a fragment becomes one field
  - a repeated root field collapses into a single response key, generating every
    variant struct its copies select
  - printing keeps the source form: both selection sites, both root-field copies,
    each copy getting `__typename` injected for variant dispatch
  - the response decodes the merged whole, across selection sites and variants
  """
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug:
          {Req.Test,
           TypedGql.Integration.QueryMergingDuplicateSelectionsAcrossFragmentsAndFieldsTest.Client}
      ]

    defgql(:merged_profile, """
    query MergedProfile($id: ID!) {
      user(id: $id) {
        id
        name
        ...WithEmail
        ...WithPosts
        posts { id }
      }
    }
    fragment WithEmail on User { name email }
    fragment WithPosts on User { posts { title status } }
    """)

    defgql(:merged_search, """
    query MergedSearch($term: String!) {
      search(query: $term) { ... on User { id name } }
      search(query: $term) { ... on Post { id title } }
    }
    """)
  end

  describe "generated shape" do
    test "the posts module unions the fields of the direct selection and the fragment" do
      assert %{related: Client.MergedProfile.Result.User.Posts, cardinality: :many} =
               Client.MergedProfile.Result.User.__schema__(:embed, :posts)

      assert Enum.sort(Client.MergedProfile.Result.User.Posts.__schema__(:fields)) ==
               [:id, :status, :title]
    end

    test "a scalar selected both directly and via a fragment becomes one field" do
      assert Client.MergedProfile.Result.User.__schema__(:fields) == [:id, :name, :email, :posts]
    end

    test "the repeated search root field collapses into a single response key" do
      assert Client.MergedSearch.Result.__schema__(:fields) == [:search]

      assert {:array, {:parameterized, {Client.MergedSearch.Result.Search.Union, %{}}}} =
               Client.MergedSearch.Result.__schema__(:type, :search)
    end

    test "the merged search selection generates both union variant structs" do
      assert Client.MergedSearch.Result.Search.User.__schema__(:fields) == [:id, :name]
      assert Client.MergedSearch.Result.Search.Post.__schema__(:fields) == [:id, :title]
    end
  end

  describe "dumped request" do
    test "the printed profile document keeps both posts selection sites and the fragments" do
      request = capture_request(:merged_profile)

      assert request["operationName"] == "MergedProfile"
      assert count(request["query"], "posts {") == 2
      assert request["query"] =~ "fragment WithEmail on User"
      assert request["query"] =~ "fragment WithPosts on User"
    end

    test "the repeated search field prints as two copies, each with its own inline fragment" do
      request = capture_request(:merged_search)

      assert count(request["query"], "search(query: $term)") == 2
      assert request["query"] =~ "... on User"
      assert request["query"] =~ "... on Post"
    end

    test "each printed search copy gets __typename injected for variant dispatch" do
      request = capture_request(:merged_search)

      assert count(request["query"], "__typename") == 2
    end
  end

  describe "loaded response" do
    test "a posts element decodes id, title, and status across both selection sites" do
      result = fetch_profile()

      assert [
               %Client.MergedProfile.Result.User.Posts{
                 id: "p1",
                 title: "Hello",
                 status: :published
               }
             ] = result.data.user.posts
    end

    test "the merged user decodes direct fields and fragment fields together" do
      result = fetch_profile()

      assert %Client.MergedProfile.Result.User{
               id: "u1",
               name: "Alice",
               email: "alice@example.com"
             } = result.data.user
    end

    test "a search list with a User and a Post casts each element to its variant struct" do
      result = fetch_search()

      assert [
               %Client.MergedSearch.Result.Search.User{id: "u2", name: "Bob"},
               %Client.MergedSearch.Result.Search.Post{id: "p20", title: "Hello"}
             ] = result.data.search
    end
  end

  defp capture_request(operation) do
    parent = self()

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = call(operation)
    assert_received {:request, request}
    request
  end

  defp fetch_profile do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "user" => %{
            "id" => "u1",
            "name" => "Alice",
            "email" => "alice@example.com",
            "posts" => [%{"id" => "p1", "title" => "Hello", "status" => "PUBLISHED"}]
          }
        }
      })
    end)

    assert {:ok, %Result{} = result} = call(:merged_profile)
    result
  end

  defp fetch_search do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "search" => [
            %{"__typename" => "User", "id" => "u2", "name" => "Bob"},
            %{"__typename" => "Post", "id" => "p20", "title" => "Hello"}
          ]
        }
      })
    end)

    assert {:ok, %Result{} = result} = call(:merged_search)
    result
  end

  defp call(:merged_profile) do
    Client.merged_profile(%{id: "u1"})
  end

  defp call(:merged_search) do
    Client.merged_search(%{term: "elixir"})
  end

  defp count(string, substring) do
    string |> String.split(substring) |> length() |> Kernel.-(1)
  end
end
