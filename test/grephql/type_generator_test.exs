defmodule Grephql.TypeGeneratorTest do
  use ExUnit.Case, async: true

  # These modules are dynamically defined by TypeGenerator.generate/3 at test
  # runtime, so the compiler cannot see them when compiling this test file.
  @compile {:no_warn_undefined,
            [
              Grephql.Test.Alias.GetUser.Result.User,
              Grephql.Test.AutoTypename.GetNode.Result.Node.User,
              Grephql.Test.Isolation.GetUser.Result.User,
              Grephql.Test.Isolation.ListUsers.Result.User,
              Grephql.Test.ListEmbed.GetUser.Result.User,
              Grephql.Test.Nested.GetUser.Result.User,
              Grephql.Test.NoDupTypename.GetNode.Result.Node.User,
              Grephql.Test.NoPK.GetUser.Result.User,
              Grephql.Test.NonNull.GetUser.Result.User,
              Grephql.Test.Union.Search.Result.Search.Post,
              Grephql.Test.Union.Search.Result.Search.User,
              Grephql.Test.UnionField.Search.Result.Result
            ]}

  alias Grephql.Schema.Field, as: SchemaField
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef
  alias Grephql.Test.SchemaHelper
  alias Grephql.TypeGenerator

  describe "basic scalar fields" do
    test "generates embedded schema with scalar fields" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name email } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.Basic,
          function_name: :get_user
        )

      assert Grephql.Test.Basic.GetUser.Result.User in modules

      user = struct(Grephql.Test.Basic.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end

    test "non-null field uses null: false" do
      types = types_with_non_null_name()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.NonNull,
        function_name: :get_user
      )

      fields = Grephql.Test.NonNull.GetUser.Result.User.__schema__(:fields)
      assert :name in fields
    end

    test "nullable field defaults to nil" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name email } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Nullable,
        function_name: :get_user
      )

      user = struct(Grephql.Test.Nullable.GetUser.Result.User)
      assert user.name == nil
      assert user.email == nil
    end
  end

  describe "nested object fields" do
    test "generates nested embedded schema with embeds_one" do
      types = types_with_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name posts { title } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.Nested,
          function_name: :get_user
        )

      assert Grephql.Test.Nested.GetUser.Result.User in modules
      assert Grephql.Test.Nested.GetUser.Result.User.Posts in modules

      assert :posts in Grephql.Test.Nested.GetUser.Result.User.__schema__(:embeds)
    end

    test "deeply nested objects generate full path" do
      types = types_with_author()
      schema = SchemaHelper.build_schema(types: types)

      operation =
        parse!("query { user(id: \"1\") { name posts { title author { name } } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.Deep,
          function_name: :get_user
        )

      assert Grephql.Test.Deep.GetUser.Result.User in modules
      assert Grephql.Test.Deep.GetUser.Result.User.Posts in modules
      assert Grephql.Test.Deep.GetUser.Result.User.Posts.Author in modules
    end

    test "list field generates embeds_many" do
      types = types_with_list_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name posts { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.ListEmbed,
        function_name: :get_user
      )

      assert :posts in Grephql.Test.ListEmbed.GetUser.Result.User.__schema__(:embeds)
    end
  end

  describe "field alias support" do
    test "alias affects struct field name" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { display_name: name email } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Alias,
        function_name: :get_user
      )

      fields = Grephql.Test.Alias.GetUser.Result.User.__schema__(:fields)
      assert :display_name in fields
      refute :name in fields
    end

    test "alias affects nested module name" do
      types = types_with_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { articles: posts { title } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.AliasNested,
          function_name: :get_user
        )

      assert Grephql.Test.AliasNested.GetUser.Result.User.Articles in modules
      refute Grephql.Test.AliasNested.GetUser.Result.User.Posts in modules
    end
  end

  describe "per-query isolation" do
    test "different queries for same type get independent structs" do
      schema = SchemaHelper.build_schema()

      op1 = parse!("query { user(id: \"1\") { name email } }")

      TypeGenerator.generate(op1, schema,
        client_module: Grephql.Test.Isolation,
        function_name: :get_user
      )

      op2 = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(op2, schema,
        client_module: Grephql.Test.Isolation,
        function_name: :list_users
      )

      get_fields = Grephql.Test.Isolation.GetUser.Result.User.__schema__(:fields)
      list_fields = Grephql.Test.Isolation.ListUsers.Result.User.__schema__(:fields)

      assert :name in get_fields
      assert :email in get_fields
      assert :name in list_fields
      refute :email in list_fields
    end
  end

  describe "no primary key" do
    test "generated schemas have no :id field" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.NoPK,
        function_name: :get_user
      )

      fields = Grephql.Test.NoPK.GetUser.Result.User.__schema__(:fields)
      refute :id in fields
    end
  end

  describe "union/interface with inline fragments" do
    test "generates per-fragment structs with shared fields merged" do
      schema = schema_with_union()

      operation =
        parse!("query { search { __typename id ... on User { email } ... on Post { title } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.Union,
          function_name: :search
        )

      assert Grephql.Test.Union.Search.Result in modules
      assert Grephql.Test.Union.Search.Result.Search.User in modules
      assert Grephql.Test.Union.Search.Result.Search.Post in modules

      # User struct has shared fields + own fields
      user_fields = Grephql.Test.Union.Search.Result.Search.User.__schema__(:fields)
      assert :__typename in user_fields
      assert :id in user_fields
      assert :email in user_fields

      # Post struct has shared fields + own fields
      post_fields = Grephql.Test.Union.Search.Result.Search.Post.__schema__(:fields)
      assert :__typename in post_fields
      assert :id in post_fields
      assert :title in post_fields
    end

    test "union field uses parameterized type, not embed" do
      schema = schema_with_union()

      operation =
        parse!("query { search { __typename ... on User { email } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.UnionField,
        function_name: :search
      )

      # search field should be a regular field (parameterized type), not an embed
      embeds = Grephql.Test.UnionField.Search.Result.__schema__(:embeds)
      refute :search in embeds

      fields = Grephql.Test.UnionField.Search.Result.__schema__(:fields)
      assert :search in fields
    end

    test "end-to-end decode with union field" do
      schema = schema_with_union()

      operation =
        parse!("query { search { __typename id ... on User { email } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.UnionE2E,
        function_name: :search
      )

      json = %{
        "search" => [
          %{"__typename" => "User", "id" => "1", "email" => "a@b.com"},
          %{"__typename" => "Post", "id" => "2", "title" => "Hello"}
        ]
      }

      result = Grephql.ResponseDecoder.decode!(Grephql.Test.UnionE2E.Search.Result, json)

      [user, post] = result.search
      assert %{__struct__: Grephql.Test.UnionE2E.Search.Result.Search.User} = user
      assert user.id == "1"
      assert user.email == "a@b.com"
      assert %{__struct__: Grephql.Test.UnionE2E.Search.Result.Search.Post} = post
      assert post.id == "2"
      assert post.title == "Hello"
    end

    test "auto-injects __typename when not queried" do
      schema = schema_with_single_union()

      operation =
        parse!("query { node { ... on User { name } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.AutoTypename,
        function_name: :get_node
      )

      # __typename is auto-injected into each fragment struct
      user_fields = Grephql.Test.AutoTypename.GetNode.Result.Node.User.__schema__(:fields)
      assert :__typename in user_fields

      json = %{"node" => %{"__typename" => "User", "name" => "Alice"}}
      result = Grephql.ResponseDecoder.decode!(Grephql.Test.AutoTypename.GetNode.Result, json)

      assert %{__struct__: Grephql.Test.AutoTypename.GetNode.Result.Node.User} = result.node
      assert result.node.name == "Alice"
    end

    test "does not duplicate __typename when already queried" do
      schema = schema_with_single_union()

      operation =
        parse!("query { node { __typename ... on User { name } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.NoDupTypename,
        function_name: :get_node
      )

      user_fields = Grephql.Test.NoDupTypename.GetNode.Result.Node.User.__schema__(:fields)
      typename_count = Enum.count(user_fields, &(&1 == :__typename))
      assert typename_count == 1
    end

    test "single union field (not list) uses field with union type" do
      schema = schema_with_single_union()

      operation =
        parse!("query { node { __typename ... on User { name } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.SingleUnion,
        function_name: :get_node
      )

      json = %{"node" => %{"__typename" => "User", "name" => "Alice"}}
      result = Grephql.ResponseDecoder.decode!(Grephql.Test.SingleUnion.GetNode.Result, json)

      assert %{__struct__: Grephql.Test.SingleUnion.GetNode.Result.Node.User} = result.node
      assert result.node.name == "Alice"
    end
  end

  # Helpers

  defp parse!(query) do
    {:ok, %{definitions: [operation | _rest]}} = Grephql.Parser.parse(query)
    operation
  end

  defp types_with_non_null_name do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "name" => %SchemaField{
            name: "name",
            type: %TypeRef{
              kind: :non_null,
              of_type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      }
    })
  end

  defp types_with_posts do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "name" => %SchemaField{
            name: "name",
            type: %TypeRef{kind: :scalar, name: "String"}
          },
          "posts" => %SchemaField{
            name: "posts",
            type: %TypeRef{
              kind: :non_null,
              of_type: %TypeRef{kind: :object, name: "Post"}
            }
          }
        }
      },
      "Post" => %Type{
        kind: :object,
        name: "Post",
        fields: %{
          "title" => %SchemaField{
            name: "title",
            type: %TypeRef{kind: :scalar, name: "String"}
          }
        }
      }
    })
  end

  defp types_with_list_posts do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "name" => %SchemaField{
            name: "name",
            type: %TypeRef{kind: :scalar, name: "String"}
          },
          "posts" => %SchemaField{
            name: "posts",
            type: %TypeRef{
              kind: :non_null,
              of_type: %TypeRef{
                kind: :list,
                of_type: %TypeRef{kind: :object, name: "Post"}
              }
            }
          }
        }
      },
      "Post" => %Type{
        kind: :object,
        name: "Post",
        fields: %{
          "title" => %SchemaField{
            name: "title",
            type: %TypeRef{kind: :scalar, name: "String"}
          }
        }
      }
    })
  end

  defp types_with_author do
    base = types_with_list_posts()

    put_in(base["Post"], %Type{
      kind: :object,
      name: "Post",
      fields: %{
        "title" => %SchemaField{
          name: "title",
          type: %TypeRef{kind: :scalar, name: "String"}
        },
        "author" => %SchemaField{
          name: "author",
          type: %TypeRef{
            kind: :non_null,
            of_type: %TypeRef{kind: :object, name: "User"}
          }
        }
      }
    })
  end

  defp schema_with_union do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "search" => %SchemaField{
              name: "search",
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{
                  kind: :list,
                  of_type: %TypeRef{kind: :union, name: "SearchResult"}
                }
              }
            }
          }
        },
        "SearchResult" => %Type{
          kind: :union,
          name: "SearchResult",
          possible_types: ["User", "Post"]
        },
        "User" => %Type{
          kind: :object,
          name: "User",
          fields: %{
            "__typename" => %SchemaField{
              name: "__typename",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
            },
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "email" => %SchemaField{
              name: "email",
              type: %TypeRef{kind: :scalar, name: "String"}
            },
            "name" => %SchemaField{
              name: "name",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        },
        "Post" => %Type{
          kind: :object,
          name: "Post",
          fields: %{
            "__typename" => %SchemaField{
              name: "__typename",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
            },
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "title" => %SchemaField{
              name: "title",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  defp schema_with_single_union do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "node" => %SchemaField{
              name: "node",
              type: %TypeRef{kind: :union, name: "Node"}
            }
          }
        },
        "Node" => %Type{
          kind: :union,
          name: "Node",
          possible_types: ["User", "Post"]
        },
        "User" => %Type{
          kind: :object,
          name: "User",
          fields: %{
            "__typename" => %SchemaField{
              name: "__typename",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
            },
            "name" => %SchemaField{
              name: "name",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        },
        "Post" => %Type{
          kind: :object,
          name: "Post",
          fields: %{
            "__typename" => %SchemaField{
              name: "__typename",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
            },
            "title" => %SchemaField{
              name: "title",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end
end
