defmodule TypedGql.Integration.QueryWithNullableAndNonNullObjectListShapesTest do
  @moduledoc """
  How a list of objects lowers, depending on the nullability the schema declares:

  - `[Post!]!` generates an `embeds_many`
  - `[Post]` generates a plain array field whose struct default is nil
  - every `[Post!]!` element decodes into a struct
  - a null `[Post]` list stays nil instead of becoming `[]`
  - a null element inside `[Post]` survives the cast
  """
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug: {Req.Test, __MODULE__}
      ]

    defgql(:post_board, """
    query PostBoard($id: ID!) {
      user(id: $id) {
        id
        posts {
          id
          title
          status
        }
      }
      drafts {
        id
        title
        status
        publishedAt
      }
    }
    """)
  end

  describe "generated shape" do
    test "[Post!]! generates embeds_many" do
      user_mod = Client.PostBoard.Result.User

      assert :posts in user_mod.__schema__(:embeds)
      assert %{cardinality: :many} = user_mod.__schema__(:embed, :posts)
    end

    test "[Post] generates a plain array field with a nil default" do
      result_mod = Client.PostBoard.Result

      refute :drafts in result_mod.__schema__(:embeds)

      assert {:array, {:parameterized, {Ecto.Embedded, %{cardinality: :one}}}} =
               result_mod.__schema__(:type, :drafts)

      assert result_mod.__struct__().drafts == nil
    end
  end

  describe "loaded response" do
    test "every [Post!]! element decodes into a struct" do
      result =
        fetch(%{
          "user" => user_with_posts(),
          "drafts" => []
        })

      assert [
               %Client.PostBoard.Result.User.Posts{id: "p1", status: :published},
               %Client.PostBoard.Result.User.Posts{id: "p2", status: :draft}
             ] = result.data.user.posts
    end

    test "a null [Post] list stays nil instead of becoming []" do
      result = fetch(%{"user" => user_with_posts(), "drafts" => nil})

      assert result.data.drafts == nil
    end

    test "a null element inside [Post] survives the cast" do
      result =
        fetch(%{
          "user" => user_with_posts(),
          "drafts" => [
            %{"id" => "d1", "title" => "WIP", "status" => "DRAFT", "publishedAt" => nil},
            nil
          ]
        })

      assert [
               %Client.PostBoard.Result.Drafts{id: "d1", status: :draft, published_at: nil},
               nil
             ] = result.data.drafts
    end
  end

  defp user_with_posts do
    %{
      "id" => "u1",
      "posts" => [
        %{"id" => "p1", "title" => "One", "status" => "PUBLISHED"},
        %{"id" => "p2", "title" => "Two", "status" => "DRAFT"}
      ]
    }
  end

  defp fetch(data) do
    Req.Test.expect(Client, fn conn -> Req.Test.json(conn, %{"data" => data}) end)

    assert {:ok, %Result{} = result} =
             Client.post_board(%{id: "u1"})

    result
  end
end
