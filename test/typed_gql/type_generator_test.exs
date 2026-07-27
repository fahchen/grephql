defmodule TypedGql.TypeGeneratorTest do
  use ExUnit.Case, async: true

  # These modules are dynamically defined by TypeGenerator.generate/3 at test
  # runtime, so the compiler cannot see them when compiling this test file.
  @compile {:no_warn_undefined,
            [
              TypedGql.Test.Alias.GetUser.Result.User,
              TypedGql.Test.AliasArgs.GetUsers.Result,
              TypedGql.Test.AliasArgs.GetUsers.Result.Author,
              TypedGql.Test.AliasArgs.GetUsers.Result.Editor,
              TypedGql.Test.AliasMulti.GetUsers.Result,
              TypedGql.Test.AliasMulti.GetUsers.Result.Author,
              TypedGql.Test.AliasMulti.GetUsers.Result.SimpleUser,
              TypedGql.Test.AutoTypename.GetNode.Result.Node.User,
              TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.AppSubscription,
              TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.Shop,
              TypedGql.Test.Isolation.GetUser.Result.User,
              TypedGql.Test.Isolation.ListUsers.Result.User,
              TypedGql.Test.ListEmbed.GetUser.Result.User,
              TypedGql.Test.Nested.GetUser.Result.User,
              TypedGql.Test.NoDupTypename.GetNode.Result.Node.User,
              TypedGql.Test.NoPK.GetUser.Result.User,
              TypedGql.Test.NonNull.GetUser.Result.User,
              TypedGql.Test.ObjectInlineFrag.GetUser.Result.User,
              TypedGql.Test.ResultRoot.GetUser.Result,
              TypedGql.Test.ResultRoot.GetUser.Result.User,
              TypedGql.Test.Union.Search.Result.Search.Post,
              TypedGql.Test.Union.Search.Result.Search.User,
              TypedGql.Test.UnionField.Search.Result.Result
            ]}

  alias TypedGql.Schema.Field, as: SchemaField
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.TypeGenerator

  describe "basic scalar fields" do
    test "generates embedded schema with scalar fields" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name email } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Basic,
          function_name: :get_user
        )

      assert TypedGql.Test.Basic.GetUser.Result.User in modules

      user = struct(TypedGql.Test.Basic.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end

    test "non-null field uses null: false" do
      types = types_with_non_null_name()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.NonNull,
        function_name: :get_user
      )

      fields = TypedGql.Test.NonNull.GetUser.Result.User.__schema__(:fields)
      assert :name in fields
    end

    test "nullable field defaults to nil" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name email } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Nullable,
        function_name: :get_user
      )

      user = struct(TypedGql.Test.Nullable.GetUser.Result.User)
      assert user.name == nil
      assert user.email == nil
    end
  end

  describe "generated module list" do
    test "first returned module is the operation Result root" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name email } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.ResultRoot,
          function_name: :get_user
        )

      # Compiler.compile_document!/4 uses hd(output_modules) as the decode root.
      assert hd(modules) == TypedGql.Test.ResultRoot.GetUser.Result
    end
  end

  describe "inline fragment on an object parent" do
    test "abstract-typed inline fragment with a nested fragment flattens without crashing" do
      schema = schema_object_with_interface()
      operation = parse!("query { user(id: \"1\") { ... on Node { id ... { name } } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.ObjectInlineFrag,
          function_name: :get_user
        )

      assert TypedGql.Test.ObjectInlineFrag.GetUser.Result.User in modules

      fields = TypedGql.Test.ObjectInlineFrag.GetUser.Result.User.__schema__(:fields)
      assert :id in fields
      assert :name in fields
    end
  end

  describe "generation lifecycle hooks" do
    defmodule RecordingPlugin do
      @moduledoc false
      use TypedGql.Generation.Plugin

      @impl TypedGql.Generation.Plugin
      def before_normalize(selections, _context) do
        send(self(), :before_normalize)
        selections
      end

      @impl TypedGql.Generation.Plugin
      def after_normalize(selections, _context) do
        send(self(), :after_normalize)
        selections
      end

      @impl TypedGql.Generation.Plugin
      def after_lower(module_asts, _context) do
        send(self(), :after_lower)
        module_asts
      end
    end

    test "the pipeline invokes before_normalize, after_normalize, and after_lower" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.HookOrder,
        function_name: :get_user,
        generation_plugins: [RecordingPlugin]
      )

      assert_received :before_normalize
      assert_received :after_normalize
      assert_received :after_lower
    end
  end

  describe "nested object fields" do
    test "generates nested embedded schema with embeds_one" do
      types = types_with_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name posts { title } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Nested,
          function_name: :get_user
        )

      assert TypedGql.Test.Nested.GetUser.Result.User in modules
      assert TypedGql.Test.Nested.GetUser.Result.User.Posts in modules

      assert :posts in TypedGql.Test.Nested.GetUser.Result.User.__schema__(:embeds)
    end

    test "deeply nested objects generate full path" do
      types = types_with_author()
      schema = SchemaHelper.build_schema(types: types)

      operation =
        parse!("query { user(id: \"1\") { name posts { title author { name } } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.Deep,
          function_name: :get_user
        )

      assert TypedGql.Test.Deep.GetUser.Result.User in modules
      assert TypedGql.Test.Deep.GetUser.Result.User.Posts in modules
      assert TypedGql.Test.Deep.GetUser.Result.User.Posts.Author in modules
    end

    test "list field generates embeds_many" do
      types = types_with_list_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name posts { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.ListEmbed,
        function_name: :get_user
      )

      assert :posts in TypedGql.Test.ListEmbed.GetUser.Result.User.__schema__(:embeds)
    end
  end

  describe "field alias support" do
    test "alias affects struct field name" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { display_name: name email } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.Alias,
        function_name: :get_user
      )

      fields = TypedGql.Test.Alias.GetUser.Result.User.__schema__(:fields)
      assert :display_name in fields
      refute :name in fields
    end

    test "multiple aliases of the same field generate independent structs" do
      schema = SchemaHelper.build_schema()

      operation =
        parse!(
          ~s|query { author: user(id: "1") { name email } simpleUser: user(id: "1") { name } }|
        )

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.AliasMulti,
          function_name: :get_users
        )

      assert TypedGql.Test.AliasMulti.GetUsers.Result in modules
      assert TypedGql.Test.AliasMulti.GetUsers.Result.Author in modules
      assert TypedGql.Test.AliasMulti.GetUsers.Result.SimpleUser in modules

      # Each alias gets its own struct with its own selected fields
      author_fields = TypedGql.Test.AliasMulti.GetUsers.Result.Author.__schema__(:fields)
      assert :name in author_fields
      assert :email in author_fields

      simple_fields = TypedGql.Test.AliasMulti.GetUsers.Result.SimpleUser.__schema__(:fields)
      assert :name in simple_fields
      refute :email in simple_fields

      # Result has both alias fields
      result_fields = TypedGql.Test.AliasMulti.GetUsers.Result.__schema__(:fields)
      assert :author in result_fields
      assert :simple_user in result_fields
    end

    test "same field aliased with different arguments: independent structs, both arg sets printed, decode by alias" do
      schema = SchemaHelper.build_schema()

      query =
        ~s|query { author: user(id: "1") { name email } editor: user(id: "2") { name } }|

      {:ok, doc} = TypedGql.Parser.parse(query)
      operation = hd(doc.definitions)

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.AliasArgs,
          function_name: :get_users
        )

      result_mod = TypedGql.Test.AliasArgs.GetUsers.Result

      # Generation: one struct per alias, each with only its own selected fields
      assert result_mod in modules
      assert TypedGql.Test.AliasArgs.GetUsers.Result.Author in modules
      assert TypedGql.Test.AliasArgs.GetUsers.Result.Editor in modules

      author_fields = TypedGql.Test.AliasArgs.GetUsers.Result.Author.__schema__(:fields)
      assert :name in author_fields
      assert :email in author_fields

      editor_fields = TypedGql.Test.AliasArgs.GetUsers.Result.Editor.__schema__(:fields)
      assert :name in editor_fields
      refute :email in editor_fields

      result_fields = result_mod.__schema__(:fields)
      assert :author in result_fields
      assert :editor in result_fields

      # Printer: both distinct argument sets survive query reconstruction
      printed = TypedGql.Printer.print(doc)
      assert printed =~ ~s|author: user(id: "1")|
      assert printed =~ ~s|editor: user(id: "2")|

      # Decode: response keyed by alias loads into the matching nested struct
      data = %{
        "author" => %{"name" => "A", "email" => "a@x"},
        "editor" => %{"name" => "E"}
      }

      result = TypedGql.ResponseDecoder.decode!(result_mod, data)
      assert result.author.name == "A"
      assert result.author.email == "a@x"
      assert result.editor.name == "E"
    end

    test "alias affects nested module name" do
      types = types_with_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { articles: posts { title } } }")

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.AliasNested,
          function_name: :get_user
        )

      assert TypedGql.Test.AliasNested.GetUser.Result.User.Articles in modules
      refute TypedGql.Test.AliasNested.GetUser.Result.User.Posts in modules
    end
  end

  describe "per-query isolation" do
    test "different queries for same type get independent structs" do
      schema = SchemaHelper.build_schema()

      op1 = parse!("query { user(id: \"1\") { name email } }")

      TypeGenerator.generate(op1, schema,
        client_module: TypedGql.Test.Isolation,
        function_name: :get_user
      )

      op2 = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(op2, schema,
        client_module: TypedGql.Test.Isolation,
        function_name: :list_users
      )

      get_fields = TypedGql.Test.Isolation.GetUser.Result.User.__schema__(:fields)
      list_fields = TypedGql.Test.Isolation.ListUsers.Result.User.__schema__(:fields)

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
        client_module: TypedGql.Test.NoPK,
        function_name: :get_user
      )

      fields = TypedGql.Test.NoPK.GetUser.Result.User.__schema__(:fields)
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
          client_module: TypedGql.Test.Union,
          function_name: :search
        )

      assert TypedGql.Test.Union.Search.Result in modules
      assert TypedGql.Test.Union.Search.Result.Search.User in modules
      assert TypedGql.Test.Union.Search.Result.Search.Post in modules

      # User struct has shared fields + own fields
      user_fields = TypedGql.Test.Union.Search.Result.Search.User.__schema__(:fields)
      assert :__typename in user_fields
      assert :id in user_fields
      assert :email in user_fields

      # Post struct has shared fields + own fields
      post_fields = TypedGql.Test.Union.Search.Result.Search.Post.__schema__(:fields)
      assert :__typename in post_fields
      assert :id in post_fields
      assert :title in post_fields
    end

    test "union field uses parameterized type, not embed" do
      schema = schema_with_union()

      operation =
        parse!("query { search { __typename ... on User { email } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.UnionField,
        function_name: :search
      )

      # search field should be a regular field (parameterized type), not an embed
      result_module = Module.safe_concat(TypedGql.Test.UnionField.Search, Result)
      embeds = result_module.__schema__(:embeds)
      refute :search in embeds

      fields = result_module.__schema__(:fields)
      assert :search in fields
    end

    test "end-to-end decode with union field" do
      schema = schema_with_union()

      operation =
        parse!("query { search { __typename id ... on User { email } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.UnionE2E,
        function_name: :search
      )

      json = %{
        "search" => [
          %{"__typename" => "User", "id" => "1", "email" => "a@b.com"},
          %{"__typename" => "Post", "id" => "2", "title" => "Hello"}
        ]
      }

      result = TypedGql.ResponseDecoder.decode!(TypedGql.Test.UnionE2E.Search.Result, json)

      [user, post] = result.search
      assert %{__struct__: TypedGql.Test.UnionE2E.Search.Result.Search.User} = user
      assert user.id == "1"
      assert user.email == "a@b.com"
      assert %{__struct__: TypedGql.Test.UnionE2E.Search.Result.Search.Post} = post
      assert post.id == "2"
      assert post.title == "Hello"
    end

    test "auto-injects __typename when not queried" do
      schema = schema_with_single_union()

      operation =
        parse!("query { node { ... on User { name } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.AutoTypename,
        function_name: :get_node
      )

      # __typename is auto-injected into each fragment struct
      user_fields = TypedGql.Test.AutoTypename.GetNode.Result.Node.User.__schema__(:fields)
      assert :__typename in user_fields

      json = %{"node" => %{"__typename" => "User", "name" => "Alice"}}
      result = TypedGql.ResponseDecoder.decode!(TypedGql.Test.AutoTypename.GetNode.Result, json)

      assert %{__struct__: TypedGql.Test.AutoTypename.GetNode.Result.Node.User} = result.node
      assert result.node.name == "Alice"
    end

    test "does not duplicate __typename when already queried" do
      schema = schema_with_single_union()

      operation =
        parse!("query { node { __typename ... on User { name } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.NoDupTypename,
        function_name: :get_node
      )

      user_fields = TypedGql.Test.NoDupTypename.GetNode.Result.Node.User.__schema__(:fields)
      typename_count = Enum.count(user_fields, &(&1 == :__typename))
      assert typename_count == 1
    end

    test "handles __typename when not in introspection fields" do
      schema = schema_with_interface_no_typename()

      operation =
        parse!(
          "query($id: ID!) { node(id: $id) { ... on AppSubscription { status } ... on Shop { name } } }"
        )

      modules =
        TypeGenerator.generate(operation, schema,
          client_module: TypedGql.Test.InterfaceNoTypename,
          function_name: :get_node
        )

      assert TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.AppSubscription in modules
      assert TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.Shop in modules

      # __typename is auto-injected and resolved even without it in the schema fields
      sub_fields =
        TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.AppSubscription.__schema__(:fields)

      assert :__typename in sub_fields
      assert :status in sub_fields

      shop_fields =
        TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.Shop.__schema__(:fields)

      assert :__typename in shop_fields
      assert :name in shop_fields

      # End-to-end decode works
      json = %{"node" => %{"__typename" => "AppSubscription", "status" => "ACTIVE"}}

      result =
        TypedGql.ResponseDecoder.decode!(
          TypedGql.Test.InterfaceNoTypename.GetNode.Result,
          json
        )

      assert %{__struct__: TypedGql.Test.InterfaceNoTypename.GetNode.Result.Node.AppSubscription} =
               result.node

      assert result.node.status == "ACTIVE"
    end

    test "single union field (not list) uses field with union type" do
      schema = schema_with_single_union()

      operation =
        parse!("query { node { __typename ... on User { name } ... on Post { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.SingleUnion,
        function_name: :get_node
      )

      json = %{"node" => %{"__typename" => "User", "name" => "Alice"}}
      result = TypedGql.ResponseDecoder.decode!(TypedGql.Test.SingleUnion.GetNode.Result, json)

      assert %{__struct__: TypedGql.Test.SingleUnion.GetNode.Result.Node.User} = result.node
      assert result.node.name == "Alice"
    end
  end

  # Helpers

  defp parse!(query) do
    {:ok, %{definitions: [operation | _rest]}} = TypedGql.Parser.parse(query)
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

  # Interface type where concrete types do NOT have __typename in their fields,
  # matching real introspection JSON behaviour.
  defp schema_with_interface_no_typename do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "node" => %SchemaField{
              name: "node",
              type: %TypeRef{kind: :interface, name: "Node"},
              args: %{
                "id" => %TypedGql.Schema.InputValue{
                  name: "id",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :scalar, name: "ID"}
                  }
                }
              }
            }
          }
        },
        "Node" => %Type{
          kind: :interface,
          name: "Node",
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            }
          },
          possible_types: ["AppSubscription", "Shop"]
        },
        "AppSubscription" => %Type{
          kind: :object,
          name: "AppSubscription",
          interfaces: ["Node"],
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "status" => %SchemaField{
              name: "status",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        },
        "Shop" => %Type{
          kind: :object,
          name: "Shop",
          interfaces: ["Node"],
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "name" => %SchemaField{
              name: "name",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  # Object parent (User) whose selection uses an inline fragment on an
  # interface it implements. Exercises the object-mode flattening path where a
  # nested inline fragment must not leak into resolve_object/5.
  defp schema_object_with_interface do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %Type{
          kind: :object,
          name: "Query",
          fields: %{
            "user" => %SchemaField{
              name: "user",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :object, name: "User"}}
            }
          }
        },
        "Node" => %Type{
          kind: :interface,
          name: "Node",
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            }
          },
          possible_types: ["User"]
        },
        "User" => %Type{
          kind: :object,
          name: "User",
          interfaces: ["Node"],
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            },
            "name" => %SchemaField{
              name: "name",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end
end
