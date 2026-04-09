defmodule Grephql.IntegrationTest do
  use ExUnit.Case, async: true

  import Grephql.Test.Helpers, only: [errors_on: 2]

  alias Grephql.Result

  defmodule Client do
    use Grephql,
      otp_app: :grephql,
      source: "support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql"

    deffragment """
    fragment UserCore on User {
      id
      name
      email
      role
    }
    """

    deffragment """
    fragment PostDetail on Post {
      id
      title
      body
      status
      publishedAt
      tags
      author {
        ...UserCore
        createdAt
        profile { bio avatarUrl }
      }
    }
    """

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

    defgql(:search_with_fragments, """
    query SearchWithFragments($query: String!) {
      search(query: $query) {
        ... on User {
          ...UserCore
          createdAt
          profile { bio avatarUrl }
          posts { id title status publishedAt tags }
        }
        ... on Post {
          ...PostDetail
        }
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

    defgql(:create_post, """
    mutation CreatePost($input: CreatePostInput!) {
      createPost(input: $input) {
        ...PostDetail
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

      assert %{bio: "Hello world", avatar_url: "https://example.com/avatar.png"} =
               result.data.user.profile
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

      assert [
               %{
                 title: "First Post",
                 status: :published,
                 published_at: ~U[2025-03-01 12:00:00Z],
                 tags: ["elixir", "graphql"]
               },
               %{title: "Second Post", status: :draft, published_at: nil, tags: []}
             ] = result.data.user.posts
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

      assert [
               %{__typename: "User", name: "Alice", role: :admin},
               %{__typename: "Post", title: "Hello", status: :published}
             ] = result.data.search
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

      assert [
               %{__typename: "User", id: "1", name: "Alice"},
               %{__typename: "Post", id: "10", title: "Hello"}
             ] = result.data.nodes
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

      assert %{id: "42", name: "New User", role: :user, created_at: ~U[2025-06-15 12:00:00Z]} =
               result.data.create_user
    end

    test "mutation with nested input object variables serialized correctly" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert %{
                 "name" => "Alice",
                 "email" => "alice@example.com",
                 "role" => "ADMIN",
                 "profile" => %{"bio" => "Hello", "avatarUrl" => "https://img.example.com/a.png"}
               } = request["variables"]["input"]

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

        assert %{"id" => "1", "input" => %{"name" => "Updated", "role" => "ADMIN"}} =
                 request["variables"]

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

      assert %{name: "Updated", role: :admin} = result.data.update_user
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

  describe "complex: fragment + union + nested response round-trip" do
    test "search with fragments resolves union variants with deeply nested data" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["operationName"] == "SearchWithFragments"
        assert request["query"] =~ "fragment UserCore on User"
        assert request["query"] =~ "fragment PostDetail on Post"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "search" => [
                %{
                  "__typename" => "User",
                  "id" => "1",
                  "name" => "Alice",
                  "email" => "alice@example.com",
                  "role" => "ADMIN",
                  "createdAt" => "2025-01-15T10:30:00Z",
                  "profile" => %{
                    "bio" => "Elixir dev",
                    "avatarUrl" => "https://img.example.com/alice.png"
                  },
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
                      "title" => "Draft Post",
                      "status" => "DRAFT",
                      "publishedAt" => nil,
                      "tags" => []
                    }
                  ]
                },
                %{
                  "__typename" => "Post",
                  "id" => "20",
                  "title" => "GraphQL Best Practices",
                  "body" => "Use fragments for reuse.",
                  "status" => "PUBLISHED",
                  "publishedAt" => "2025-06-01T08:00:00Z",
                  "tags" => ["graphql", "best-practices"],
                  "author" => %{
                    "id" => "2",
                    "name" => "Bob",
                    "email" => "bob@example.com",
                    "role" => "USER",
                    "createdAt" => "2024-12-01T00:00:00Z",
                    "profile" => %{"bio" => "Writer", "avatarUrl" => nil}
                  }
                },
                %{
                  "__typename" => "User",
                  "id" => "3",
                  "name" => "Carol",
                  "email" => nil,
                  "role" => "GUEST",
                  "createdAt" => "2025-07-01T00:00:00Z",
                  "profile" => nil,
                  "posts" => []
                }
              ]
            }
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               Client.search_with_fragments(%{query: "alice"}, req_options: req_options())

      [alice, post, carol] = result.data.search

      # User variant with nested profile + posts
      assert %{
               __typename: "User",
               id: "1",
               name: "Alice",
               email: "alice@example.com",
               role: :admin,
               created_at: ~U[2025-01-15 10:30:00Z],
               profile: %{bio: "Elixir dev", avatar_url: "https://img.example.com/alice.png"},
               posts: [
                 %{
                   title: "First Post",
                   status: :published,
                   published_at: ~U[2025-03-01 12:00:00Z],
                   tags: ["elixir", "graphql"]
                 },
                 %{status: :draft, published_at: nil, tags: []}
               ]
             } = alice

      # Post variant with nested author (User via fragment)
      assert %{
               __typename: "Post",
               id: "20",
               title: "GraphQL Best Practices",
               body: "Use fragments for reuse.",
               status: :published,
               published_at: ~U[2025-06-01 08:00:00Z],
               tags: ["graphql", "best-practices"],
               author: %{
                 id: "2",
                 name: "Bob",
                 role: :user,
                 created_at: ~U[2024-12-01 00:00:00Z],
                 profile: %{bio: "Writer", avatar_url: nil}
               }
             } = post

      # User variant with nil profile and empty posts
      assert %{__typename: "User", role: :guest, profile: nil, posts: []} = carol
    end
  end

  describe "complex: mutation with nested input + deep response" do
    test "createPost serializes nested input and decodes deep response" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["operationName"] == "CreatePost"

        assert %{
                 "title" => "Deep Nesting Test",
                 "body" => "Testing deeply nested inputs and responses.",
                 "status" => "DRAFT",
                 "tags" => ["test", "integration"],
                 "metadata" => %{
                   "slug" => "deep-nesting-test",
                   "seoTitle" => "Deep Nesting | Test",
                   "publishAt" => "2025-12-25T00:00:00Z"
                 }
               } = request["variables"]["input"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "createPost" => %{
                "id" => "100",
                "title" => "Deep Nesting Test",
                "body" => "Testing deeply nested inputs and responses.",
                "status" => "DRAFT",
                "publishedAt" => nil,
                "tags" => ["test", "integration"],
                "author" => %{
                  "id" => "1",
                  "name" => "Alice",
                  "email" => "alice@example.com",
                  "role" => "ADMIN",
                  "createdAt" => "2025-01-15T10:30:00Z",
                  "profile" => %{
                    "bio" => "Elixir dev",
                    "avatarUrl" => "https://img.example.com/alice.png"
                  }
                }
              }
            }
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               Client.create_post(
                 %{
                   input: %{
                     title: "Deep Nesting Test",
                     body: "Testing deeply nested inputs and responses.",
                     status: "DRAFT",
                     tags: ["test", "integration"],
                     metadata: %{
                       slug: "deep-nesting-test",
                       seo_title: "Deep Nesting | Test",
                       publish_at: "2025-12-25T00:00:00Z"
                     }
                   }
                 },
                 req_options: req_options()
               )

      assert %{
               id: "100",
               title: "Deep Nesting Test",
               body: "Testing deeply nested inputs and responses.",
               status: :draft,
               published_at: nil,
               tags: ["test", "integration"],
               author: %{
                 id: "1",
                 name: "Alice",
                 email: "alice@example.com",
                 role: :admin,
                 created_at: ~U[2025-01-15 10:30:00Z],
                 profile: %{bio: "Elixir dev", avatar_url: "https://img.example.com/alice.png"}
               }
             } = result.data.create_post
    end
  end

  describe "query boundary: deeply nested nulls, partial errors, extensions, and edge responses" do
    test "partial data with errors and extensions on deeply nested query" do
      Req.Test.expect(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "user" => %{
                "id" => "1",
                "name" => "Alice",
                "email" => nil,
                "role" => "ADMIN",
                "createdAt" => "2025-01-01T00:00:00Z",
                "profile" => %{"bio" => "Hello", "avatarUrl" => nil},
                "posts" => [
                  %{
                    "id" => "10",
                    "title" => "Published",
                    "status" => "PUBLISHED",
                    "publishedAt" => "2025-06-01T12:00:00Z",
                    "tags" => ["elixir"]
                  },
                  %{
                    "id" => "11",
                    "title" => nil,
                    "status" => "DRAFT",
                    "publishedAt" => nil,
                    "tags" => []
                  }
                ]
              }
            },
            "errors" => [
              %{
                "message" => "Field 'title' is null for restricted post",
                "path" => ["user", "posts", 1, "title"],
                "locations" => [%{"line" => 5, "column" => 9}],
                "extensions" => %{"code" => "PERMISSION_DENIED", "retryable" => false}
              },
              %{
                "message" => "Email is restricted",
                "path" => ["user", "email"]
              }
            ]
          })
        )
      end)

      assert {:ok, %Result{} = result} = Client.get_user(%{id: "1"}, req_options: req_options())

      # Partial data is decoded
      assert %{
               id: "1",
               name: "Alice",
               email: nil,
               role: :admin,
               profile: %{bio: "Hello", avatar_url: nil}
             } = result.data.user

      # Nested list with mixed null fields
      assert [
               %{title: "Published", status: :published, tags: ["elixir"]},
               %{title: nil, status: :draft, published_at: nil, tags: []}
             ] = result.data.user.posts

      # Errors with extensions
      assert [
               %{
                 message: "Field 'title' is null for restricted post",
                 path: ["user", "posts", 1, "title"],
                 locations: [%{"line" => 5, "column" => 9}],
                 extensions: %{"code" => "PERMISSION_DENIED", "retryable" => false}
               },
               %{
                 message: "Email is restricted",
                 path: ["user", "email"],
                 locations: nil,
                 extensions: nil
               }
             ] = result.errors
    end

    test "union query with empty list, single item, and null nested objects" do
      Req.Test.expect(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "search" => [
                %{
                  "__typename" => "User",
                  "id" => "1",
                  "name" => "Alice",
                  "email" => nil,
                  "role" => "GUEST",
                  "createdAt" => "2025-01-01T00:00:00Z",
                  "profile" => nil,
                  "posts" => []
                },
                %{
                  "__typename" => "Post",
                  "id" => "20",
                  "title" => "Orphan",
                  "body" => nil,
                  "status" => "ARCHIVED",
                  "publishedAt" => nil,
                  "tags" => [],
                  "author" => %{
                    "id" => "99",
                    "name" => "Ghost",
                    "email" => nil,
                    "role" => "USER",
                    "createdAt" => "2020-01-01T00:00:00Z",
                    "profile" => nil
                  }
                }
              ]
            }
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               Client.search_with_fragments(%{query: "edge"}, req_options: req_options())

      [user, post] = result.data.search

      # User with all nullable fields nil/empty
      assert %{__typename: "User", email: nil, role: :guest, profile: nil, posts: []} = user

      # Post with nil body, nil publishedAt, empty tags, author with nil profile
      assert %{
               __typename: "Post",
               body: nil,
               status: :archived,
               published_at: nil,
               tags: [],
               author: %{id: "99", profile: nil}
             } = post
    end

    test "null data with multiple errors returns nil data and all errors" do
      Req.Test.expect(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => nil,
            "errors" => [
              %{
                "message" => "Authentication required",
                "extensions" => %{"code" => "UNAUTHENTICATED"}
              },
              %{
                "message" => "Rate limited",
                "path" => ["user"],
                "extensions" => %{"code" => "RATE_LIMITED", "retryAfter" => 30}
              }
            ]
          })
        )
      end)

      assert {:ok, %Result{} = result} = Client.get_user(%{id: "1"}, req_options: req_options())

      assert result.data == nil

      assert [
               %{
                 message: "Authentication required",
                 extensions: %{"code" => "UNAUTHENTICATED"},
                 path: nil
               },
               %{extensions: %{"retryAfter" => 30}}
             ] = result.errors
    end

    test "non-200 HTTP responses return error tuples" do
      for {status, label} <- [{400, "Bad Request"}, {401, "Unauthorized"}, {403, "Forbidden"}] do
        Req.Test.expect(Client, fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(status, Jason.encode!(%{"error" => label}))
        end)

        assert {:error, %Req.Response{status: ^status}} =
                 Client.get_user(%{id: "1"}, req_options: req_options())
      end
    end

    test "transport error on query returns error tuple" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               Client.get_user(%{id: "1"},
                 req_options: [
                   retry: false,
                   adapter: fn req -> {req, %Req.TransportError{reason: :timeout}} end
                 ]
               )
    end
  end

  describe "mutation boundary: nested validation, enum coercion, all-nil optionals" do
    test "nested required field validation failures propagate through changesets" do
      # CreateUserInput requires name and email; profile is optional but if
      # given, ProfileInput fields are all optional scalars — so this should pass
      assert {:error, %Ecto.Changeset{} = changeset} =
               Client.create_user(%{input: %{}}, req_options: req_options())

      input_changeset = changeset.changes.input
      assert "can't be blank" in errors_on(input_changeset, :name)
      assert "can't be blank" in errors_on(input_changeset, :email)
    end

    test "mutation with all optional fields nil serializes correctly" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert %{"name" => "Minimal", "email" => "min@example.com"} =
                 request["variables"]["input"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "createUser" => %{
                "id" => "50",
                "name" => "Minimal",
                "email" => "min@example.com",
                "role" => "USER",
                "createdAt" => "2025-01-01T00:00:00Z"
              }
            }
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               Client.create_user(
                 %{input: %{name: "Minimal", email: "min@example.com"}},
                 req_options: req_options()
               )

      assert %{name: "Minimal", role: :user} = result.data.create_user
    end

    test "mutation with nested input, enum, and partial response with errors" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert %{
                 "title" => "Edge Post",
                 "status" => "PUBLISHED",
                 "tags" => ["a", "b", "c"],
                 "metadata" => %{
                   "slug" => "edge-post",
                   "seoTitle" => "Edge",
                   "publishAt" => "2025-12-31T23:59:59Z"
                 }
               } = request["variables"]["input"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "createPost" => %{
                "id" => "200",
                "title" => "Edge Post",
                "body" => nil,
                "status" => "PUBLISHED",
                "publishedAt" => "2025-12-31T23:59:59Z",
                "tags" => ["a", "b", "c"],
                "author" => %{
                  "id" => "1",
                  "name" => "Alice",
                  "email" => nil,
                  "role" => "ADMIN",
                  "createdAt" => "2025-01-01T00:00:00Z",
                  "profile" => nil
                }
              }
            },
            "errors" => [
              %{
                "message" => "SEO title too short",
                "path" => ["createPost"],
                "extensions" => %{"code" => "VALIDATION_WARNING", "field" => "metadata.seoTitle"}
              }
            ]
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               Client.create_post(
                 %{
                   input: %{
                     title: "Edge Post",
                     status: "PUBLISHED",
                     tags: ["a", "b", "c"],
                     metadata: %{
                       slug: "edge-post",
                       seo_title: "Edge",
                       publish_at: "2025-12-31T23:59:59Z"
                     }
                   }
                 },
                 req_options: req_options()
               )

      assert %{
               id: "200",
               title: "Edge Post",
               body: nil,
               status: :published,
               published_at: ~U[2025-12-31 23:59:59Z],
               tags: ["a", "b", "c"],
               author: %{email: nil, profile: nil}
             } = result.data.create_post

      # Partial success: data present + warning error
      assert [%{message: "SEO title too short", extensions: %{"code" => "VALIDATION_WARNING"}}] =
               result.errors
    end

    test "mutation with deeply nested optional input all nil round-trips correctly" do
      Req.Test.expect(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert %{"title" => "Bare", "tags" => []} = request["variables"]["input"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => %{
              "createPost" => %{
                "id" => "201",
                "title" => "Bare",
                "body" => nil,
                "status" => "DRAFT",
                "publishedAt" => nil,
                "tags" => [],
                "author" => %{
                  "id" => "1",
                  "name" => "System",
                  "email" => nil,
                  "role" => "USER",
                  "createdAt" => "2025-01-01T00:00:00Z",
                  "profile" => nil
                }
              }
            }
          })
        )
      end)

      assert {:ok, %Result{} = result} =
               Client.create_post(
                 %{input: %{title: "Bare", tags: []}},
                 req_options: req_options()
               )

      assert %{
               id: "201",
               body: nil,
               status: :draft,
               published_at: nil,
               tags: [],
               author: %{name: "System", profile: nil}
             } = result.data.create_post

      assert result.errors == []
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
