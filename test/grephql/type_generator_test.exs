defmodule Grephql.TypeGeneratorTest do
  use ExUnit.Case, async: true

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

      assert Grephql.Test.Basic.GetUser.User in modules

      user = struct(Grephql.Test.Basic.GetUser.User, name: "Alice", email: "a@b.com")
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

      fields = Grephql.Test.NonNull.GetUser.User.__schema__(:fields)
      assert :name in fields
    end

    test "nullable field defaults to nil" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name email } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Nullable,
        function_name: :get_user
      )

      user = struct(Grephql.Test.Nullable.GetUser.User)
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

      assert Grephql.Test.Nested.GetUser.User in modules
      assert Grephql.Test.Nested.GetUser.User.Posts in modules

      assert :posts in Grephql.Test.Nested.GetUser.User.__schema__(:embeds)
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

      assert Grephql.Test.Deep.GetUser.User in modules
      assert Grephql.Test.Deep.GetUser.User.Posts in modules
      assert Grephql.Test.Deep.GetUser.User.Posts.Author in modules
    end

    test "list field generates embeds_many" do
      types = types_with_list_posts()
      schema = SchemaHelper.build_schema(types: types)
      operation = parse!("query { user(id: \"1\") { name posts { title } } }")

      TypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.ListEmbed,
        function_name: :get_user
      )

      assert :posts in Grephql.Test.ListEmbed.GetUser.User.__schema__(:embeds)
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

      fields = Grephql.Test.Alias.GetUser.User.__schema__(:fields)
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

      assert Grephql.Test.AliasNested.GetUser.User.Articles in modules
      refute Grephql.Test.AliasNested.GetUser.User.Posts in modules
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

      get_fields = Grephql.Test.Isolation.GetUser.User.__schema__(:fields)
      list_fields = Grephql.Test.Isolation.ListUsers.User.__schema__(:fields)

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

      fields = Grephql.Test.NoPK.GetUser.User.__schema__(:fields)
      refute :id in fields
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
end
