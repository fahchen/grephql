defmodule TypedGql.Integration.MutationWithNestedInputObjectEnumAndDatetimeVariablesTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: the dump direction of a mutation whose single variable
  # is a nested input object carrying an enum, a DateTime, and optional
  # fields that the caller omits.
  use ExUnit.Case, async: true

  alias TypedGql.Result

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql"

    defgql(:create_post, """
    mutation CreatePost($input: CreatePostInput!) {
      createPost(input: $input) {
        id
        title
        status
        publishedAt
        tags
        author {
          id
          name
          role
        }
      }
    }
    """)
  end

  setup {Req.Test, :verify_on_exit!}

  describe "generated shape" do
    test "Variables embeds the shared Client.Inputs input module" do
      assert %{related: Client.Inputs.CreatePostInput, cardinality: :one} =
               Client.CreatePost.Variables.__schema__(:embed, :input)
    end

    test "the input module embeds its nested input object as another Inputs module" do
      assert %{related: Client.Inputs.MetadataInput, cardinality: :one} =
               Client.Inputs.CreatePostInput.__schema__(:embed, :metadata)
    end
  end

  describe "dumped request" do
    test "nested input fields dump to camelCase JSON keys" do
      request = capture_request()

      assert %{"seoTitle" => "How Grephql Works", "publishAt" => _publish_at} =
               request["variables"]["input"]["metadata"]
    end

    test "an enum input given as its wire string dumps unchanged" do
      request = capture_request()

      assert request["variables"]["input"]["status"] == "PUBLISHED"
    end

    test "a DateTime input dumps as an ISO8601 string" do
      request = capture_request()

      assert request["variables"]["input"]["metadata"]["publishAt"] == "2025-03-01T09:00:00Z"
    end
  end

  describe "loaded response" do
    test "the enum field decodes to its atom and the DateTime field to a %DateTime{}" do
      result = fetch_post()

      assert %Client.CreatePost.Result.CreatePost{
               status: :published,
               published_at: ~U[2025-03-01 09:00:00Z]
             } = result.data.create_post
    end

    test "the nested author object decodes into its typed struct" do
      result = fetch_post()

      assert %Client.CreatePost.Result.CreatePost.Author{
               id: "u1",
               name: "Alice",
               role: :admin
             } = result.data.create_post.author
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

  defp fetch_post do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "createPost" => %{
            "id" => "p1",
            "title" => "How Grephql Works",
            "status" => "PUBLISHED",
            "publishedAt" => "2025-03-01T09:00:00Z",
            "tags" => ["elixir", "graphql"],
            "author" => %{"id" => "u1", "name" => "Alice", "role" => "ADMIN"}
          }
        }
      })
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp call do
    Client.create_post(
      %{
        input: %{
          title: "How Grephql Works",
          status: "PUBLISHED",
          tags: ["elixir", "graphql"],
          metadata: %{seo_title: "How Grephql Works", publish_at: ~U[2025-03-01 09:00:00Z]}
        }
      },
      req_options: [plug: {Req.Test, Client}]
    )
  end
end
