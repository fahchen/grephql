defmodule Grephql.IntegrationTest do
  use ExUnit.Case, async: true

  alias Grephql.Result

  defmodule Client do
    use Grephql,
      otp_app: :grephql,
      source: "support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql"

    defgql(:get_user, """
    query GetUser($id: ID!) {
      user(id: $id) {
        id
        name
        email
        role
        createdAt
        profile { bio avatarUrl }
        posts { id title status publishedAt tags }
      }
    }
    """)

    defgql(:list_users, """
    query ListUsers {
      users { id name role }
    }
    """)

    defgql(:search, """
    query Search($query: String!) {
      search(query: $query) {
        ... on User { id name role }
        ... on Post { id title status }
      }
    }
    """)

    defgql(:get_nodes, """
    query GetNodes($ids: [ID!]!) {
      nodes(ids: $ids) {
        ... on User { id name }
        ... on Post { id title }
      }
    }
    """)

    defgql(:create_user, """
    mutation CreateUser($input: CreateUserInput!) {
      createUser(input: $input) {
        id
        name
        email
        role
        createdAt
      }
    }
    """)

    defgql(:update_user, """
    mutation UpdateUser($id: ID!, $input: UpdateUserInput!) {
      updateUser(id: $id, input: $input) {
        id
        name
        role
      }
    }
    """)
  end

  setup {Req.Test, :verify_on_exit!}

  describe "enum fields" do
    test "decodes enum values in response" do
      expect_json(%{
        "data" => %{
          "user" => %{
            "id" => "1",
            "name" => "Alice",
            "email" => "alice@example.com",
            "role" => "ADMIN",
            "createdAt" => "2025-01-15T10:30:00Z",
            "profile" => nil,
            "posts" => []
          }
        }
      })

      assert {:ok, %Result{} = result} = Client.get_user(%{id: "1"}, req_options: req_options())

      assert result.data.user.role == :admin
    end

    test "decodes enum in list of objects" do
      expect_json(%{
        "data" => %{
          "users" => [
            %{"id" => "1", "name" => "Alice", "role" => "ADMIN"},
            %{"id" => "2", "name" => "Bob", "role" => "USER"},
            %{"id" => "3", "name" => "Carol", "role" => "GUEST"}
          ]
        }
      })

      assert {:ok, %Result{} = result} = Client.list_users(req_options: req_options())

      roles = Enum.map(result.data.users, & &1.role)
      assert roles == [:admin, :user, :guest]
    end
  end

  describe "DateTime custom scalar" do
    test "decodes DateTime field" do
      expect_json(%{
        "data" => %{
          "user" => %{
            "id" => "1",
            "name" => "Alice",
            "email" => nil,
            "role" => "USER",
            "createdAt" => "2025-06-15T14:30:00Z",
            "profile" => nil,
            "posts" => []
          }
        }
      })

      assert {:ok, %Result{} = result} = Client.get_user(%{id: "1"}, req_options: req_options())

      assert result.data.user.created_at == ~U[2025-06-15 14:30:00Z]
    end

    test "decodes nullable DateTime as nil" do
      expect_json(%{
        "data" => %{
          "user" => %{
            "id" => "1",
            "name" => "Alice",
            "email" => nil,
            "role" => "USER",
            "createdAt" => "2025-01-01T00:00:00Z",
            "profile" => nil,
            "posts" => [
              %{
                "id" => "10",
                "title" => "Draft",
                "status" => "DRAFT",
                "publishedAt" => nil,
                "tags" => []
              }
            ]
          }
        }
      })

      assert {:ok, %Result{} = result} = Client.get_user(%{id: "1"}, req_options: req_options())

      post = hd(result.data.user.posts)
      assert post.published_at == nil
    end
  end

  describe "nested objects" do
    test "decodes embeds_one nested object" do
      expect_json(%{
        "data" => %{
          "user" => %{
            "id" => "1",
            "name" => "Alice",
            "email" => "a@b.com",
            "role" => "USER",
            "createdAt" => "2025-01-01T00:00:00Z",
            "profile" => %{
              "bio" => "Hello world",
              "avatarUrl" => "https://example.com/avatar.png"
            },
            "posts" => []
          }
        }
      })

      assert {:ok, %Result{} = result} = Client.get_user(%{id: "1"}, req_options: req_options())

      assert result.data.user.profile.bio == "Hello world"
      assert result.data.user.profile.avatar_url == "https://example.com/avatar.png"
    end

    test "decodes nullable nested object as nil" do
      expect_json(%{
        "data" => %{
          "user" => %{
            "id" => "1",
            "name" => "Alice",
            "email" => nil,
            "role" => "USER",
            "createdAt" => "2025-01-01T00:00:00Z",
            "profile" => nil,
            "posts" => []
          }
        }
      })

      assert {:ok, %Result{} = result} = Client.get_user(%{id: "1"}, req_options: req_options())

      assert result.data.user.profile == nil
    end
  end

  describe "list fields" do
    test "decodes list of objects (embeds_many)" do
      expect_json(%{
        "data" => %{
          "user" => %{
            "id" => "1",
            "name" => "Alice",
            "email" => nil,
            "role" => "USER",
            "createdAt" => "2025-01-01T00:00:00Z",
            "profile" => nil,
            "posts" => [
              %{
                "id" => "10",
                "title" => "First Post",
                "status" => "PUBLISHED",
                "publishedAt" => "2025-03-01T12:00:00Z",
                "tags" => ["elixir", "graphql"]
              },
              %{
                "id" => "11",
                "title" => "Second Post",
                "status" => "DRAFT",
                "publishedAt" => nil,
                "tags" => []
              }
            ]
          }
        }
      })

      assert {:ok, %Result{} = result} = Client.get_user(%{id: "1"}, req_options: req_options())

      assert length(result.data.user.posts) == 2
      [post1, post2] = result.data.user.posts
      assert post1.title == "First Post"
      assert post1.status == :published
      assert post1.published_at == ~U[2025-03-01 12:00:00Z]
      assert post1.tags == ["elixir", "graphql"]
      assert post2.title == "Second Post"
      assert post2.status == :draft
      assert post2.published_at == nil
      assert post2.tags == []
    end

    test "decodes list of scalar strings (tags)" do
      expect_json(%{
        "data" => %{
          "user" => %{
            "id" => "1",
            "name" => "Alice",
            "email" => nil,
            "role" => "USER",
            "createdAt" => "2025-01-01T00:00:00Z",
            "profile" => nil,
            "posts" => [
              %{
                "id" => "10",
                "title" => "Tagged",
                "status" => "PUBLISHED",
                "publishedAt" => nil,
                "tags" => ["a", "b", "c"]
              }
            ]
          }
        }
      })

      assert {:ok, %Result{} = result} = Client.get_user(%{id: "1"}, req_options: req_options())

      assert hd(result.data.user.posts).tags == ["a", "b", "c"]
    end
  end

  describe "union types" do
    test "decodes union with mixed types" do
      expect_json(%{
        "data" => %{
          "search" => [
            %{"__typename" => "User", "id" => "1", "name" => "Alice", "role" => "ADMIN"},
            %{"__typename" => "Post", "id" => "10", "title" => "Hello", "status" => "PUBLISHED"}
          ]
        }
      })

      assert {:ok, %Result{} = result} =
               Client.search(%{query: "hello"}, req_options: req_options())

      [user, post] = result.data.search
      assert user.__typename == "User"
      assert user.name == "Alice"
      assert user.role == :admin
      assert post.__typename == "Post"
      assert post.title == "Hello"
      assert post.status == :published
    end
  end

  describe "interface types" do
    test "decodes interface with concrete types" do
      expect_json(%{
        "data" => %{
          "nodes" => [
            %{"__typename" => "User", "id" => "1", "name" => "Alice"},
            %{"__typename" => "Post", "id" => "10", "title" => "Hello"}
          ]
        }
      })

      assert {:ok, %Result{} = result} =
               Client.get_nodes(%{ids: ["1", "10"]}, req_options: req_options())

      [user, post] = result.data.nodes
      assert user.__typename == "User"
      assert user.id == "1"
      assert user.name == "Alice"
      assert post.__typename == "Post"
      assert post.id == "10"
      assert post.title == "Hello"
    end
  end

  describe "mutations" do
    test "mutation with input object" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["operationName"] == "CreateUser"
        assert request["variables"]["input"]["name"] == "New User"
        assert request["variables"]["input"]["email"] == "new@example.com"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "createUser" => %{
                "id" => "42",
                "name" => "New User",
                "email" => "new@example.com",
                "role" => "USER",
                "createdAt" => "2025-06-15T12:00:00Z"
              }
            }
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               Client.create_user(
                 %{input: %{name: "New User", email: "new@example.com"}},
                 req_options: req_options()
               )

      assert result.data.create_user.id == "42"
      assert result.data.create_user.name == "New User"
      assert result.data.create_user.role == :user
      assert result.data.create_user.created_at == ~U[2025-06-15 12:00:00Z]
    end

    test "mutation with nested input object variables serialized correctly" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        input = request["variables"]["input"]
        assert input["name"] == "Alice"
        assert input["email"] == "alice@example.com"
        assert input["role"] == "ADMIN"
        assert input["profile"]["bio"] == "Hello"
        assert input["profile"]["avatarUrl"] == "https://img.example.com/a.png"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "createUser" => %{
                "id" => "43",
                "name" => "Alice",
                "email" => "alice@example.com",
                "role" => "ADMIN",
                "createdAt" => "2025-06-15T12:00:00Z"
              }
            }
          })
        )
      end)

      assert {:ok, %Result{}} =
               Client.create_user(
                 %{
                   input: %{
                     name: "Alice",
                     email: "alice@example.com",
                     role: "ADMIN",
                     profile: %{bio: "Hello", avatar_url: "https://img.example.com/a.png"}
                   }
                 },
                 req_options: req_options()
               )
    end

    test "mutation with multiple variables" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["variables"]["id"] == "1"
        assert request["variables"]["input"]["name"] == "Updated"
        assert request["variables"]["input"]["role"] == "ADMIN"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "updateUser" => %{"id" => "1", "name" => "Updated", "role" => "ADMIN"}
            }
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               Client.update_user(
                 %{id: "1", input: %{name: "Updated", role: "ADMIN"}},
                 req_options: req_options()
               )

      assert result.data.update_user.name == "Updated"
      assert result.data.update_user.role == :admin
    end

    test "mutation with invalid variables returns changeset error" do
      assert {:error, %Ecto.Changeset{}} =
               Client.create_user(%{input: %{}}, req_options: req_options())
    end
  end

  describe "variables serialization round-trip" do
    test "variables are serialized to camelCase JSON" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert Map.has_key?(request["variables"], "id")
        assert request["variables"]["id"] == "42"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "user" => %{
                "id" => "42",
                "name" => "Alice",
                "email" => nil,
                "role" => "USER",
                "createdAt" => "2025-01-01T00:00:00Z",
                "profile" => nil,
                "posts" => []
              }
            }
          })
        )
      end)

      assert {:ok, %Result{}} = Client.get_user(%{id: "42"}, req_options: req_options())
    end

    test "list variable serialized correctly" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["variables"]["ids"] == ["1", "2", "3"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "nodes" => [
                %{"__typename" => "User", "id" => "1", "name" => "Alice"},
                %{"__typename" => "Post", "id" => "2", "title" => "Hello"}
              ]
            }
          })
        )
      end)

      assert {:ok, %Result{}} =
               Client.get_nodes(%{ids: ["1", "2", "3"]}, req_options: req_options())
    end
  end

  defp req_options, do: [plug: {Req.Test, Client}]

  defp expect_json(body), do: expect_json(200, body)

  defp expect_json(status, body) do
    Req.Test.expect(Client, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end)
  end
end
