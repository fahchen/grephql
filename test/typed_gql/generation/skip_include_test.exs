defmodule TypedGql.Generation.SkipIncludeTest do
  use ExUnit.Case, async: true

  # Generated modules are defined at test runtime by TypeGenerator.generate/3.
  @compile {:no_warn_undefined,
            [
              TypedGql.Test.SkipInclude.FieldInclude.Result,
              TypedGql.Test.SkipInclude.FieldSkip.Result,
              TypedGql.Test.SkipInclude.LiteralInclude.Result,
              TypedGql.Test.SkipInclude.LiteralSkip.Result,
              TypedGql.Test.SkipInclude.LiteralFragmentInclude.Result,
              TypedGql.Test.SkipInclude.InlineFragment.Result,
              TypedGql.Test.SkipInclude.FragmentSpread.Result,
              TypedGql.Test.SkipInclude.FieldEmbed.Result,
              TypedGql.Test.SkipInclude.FragmentEmbed.Result,
              TypedGql.Test.SkipInclude.UnionInclude.Result,
              TypedGql.Test.SkipInclude.UserPlugin.Result
            ]}

  alias TypedGql.Generation.Field
  alias TypedGql.Generation.Plugins.SkipInclude
  alias TypedGql.Generation.Schema
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.TypeGenerator

  defmodule CapturePlugin do
    @moduledoc false
    use TypedGql.Generation.Plugin

    @impl TypedGql.Generation.Plugin
    def after_resolve(tree, _context) do
      send(self(), {:resolved_tree, tree})
      tree
    end
  end

  defmodule RenameFieldPlugin do
    @moduledoc false
    use TypedGql.Generation.Plugin

    alias TypedGql.Generation.Field
    alias TypedGql.Generation.Schema

    @impl TypedGql.Generation.Plugin
    def after_resolve(tree, _context) do
      Schema.map_fields(tree, fn
        %Field{name: :name} = field -> %{field | name: :display_name}
        field -> field
      end)
    end
  end

  describe "field-level @include / @skip" do
    test "@include(if: $var) makes a non-null ID field nullable" do
      tree =
        resolve_tree(
          ~s|query Q($show: Boolean!) { user(id: "1") { id @include(if: $show) name } }|,
          TypedGql.Test.SkipInclude.FieldInclude,
          :q
        )

      assert nullable?(tree, :id)
      # name carries no directive, so SkipInclude leaves it untouched
      assert field(tree, :name).query_field.directives == []
    end

    test "@skip(if: $var) makes a non-null ID field nullable" do
      tree =
        resolve_tree(
          ~s|query Q($hide: Boolean!) { user(id: "1") { id @skip(if: $hide) name } }|,
          TypedGql.Test.SkipInclude.FieldSkip,
          :q
        )

      assert nullable?(tree, :id)
    end
  end

  describe "no-op literal directives" do
    test "@include(if: true) does NOT make a non-null field nullable" do
      tree =
        resolve_tree(
          ~s|query Q { user(id: "1") { id @include(if: true) name } }|,
          TypedGql.Test.SkipInclude.LiteralInclude,
          :q
        )

      refute nullable?(tree, :id)
    end

    test "@skip(if: false) does NOT make a non-null field nullable" do
      tree =
        resolve_tree(
          ~s|query Q { user(id: "1") { id @skip(if: false) name } }|,
          TypedGql.Test.SkipInclude.LiteralSkip,
          :q
        )

      refute nullable?(tree, :id)
    end

    test "@include(if: true) on an inline fragment leaves inner fields non-null" do
      tree =
        resolve_tree(
          ~s|query Q { user(id: "1") { ... @include(if: true) { id } } }|,
          TypedGql.Test.SkipInclude.LiteralFragmentInclude,
          :q
        )

      refute nullable?(tree, :id)
    end
  end

  describe "directive propagation from fragments" do
    test "inline-fragment @include propagates to all inner fields" do
      tree =
        resolve_tree(
          ~s|query Q($show: Boolean!) { user(id: "1") { ... @include(if: $show) { id name } } }|,
          TypedGql.Test.SkipInclude.InlineFragment,
          :q
        )

      assert nullable?(tree, :id)
      assert nullable?(tree, :name)
    end

    test "fragment-spread @include propagates to all expanded fields" do
      fragments = %{"UserFields" => parse_fragment("fragment UserFields on User { id name }")}

      tree =
        resolve_tree(
          ~s|query Q($show: Boolean!) { user(id: "1") { ...UserFields @include(if: $show) } }|,
          TypedGql.Test.SkipInclude.FragmentSpread,
          :q,
          fragments: fragments
        )

      assert nullable?(tree, :id)
      assert nullable?(tree, :name)
    end
  end

  describe "directive propagation on union/interface inline fragments" do
    test "inline-fragment @include over a union propagates to concrete-type fields" do
      schema = schema_with_union()

      root =
        resolve_root(
          ~s|query Q($show: Boolean!) { search { __typename ... on User @include(if: $show) { id email } ... on Post { id title } } }|,
          TypedGql.Test.SkipInclude.UnionInclude,
          :q,
          schema: schema
        )

      search_node = node_for(root, "SearchResult") || union_child(root)
      user_variant = Enum.find(search_node.children, &(&1.parent_type == "User"))
      post_variant = Enum.find(search_node.children, &(&1.parent_type == "Post"))

      # User variant fields are conditional (inline fragment carries @include).
      assert field(user_variant, :id).resolved.nullable == true
      assert field(user_variant, :email).resolved.nullable == true

      # Post variant has no directive: its non-null id stays non-null.
      assert field(post_variant, :id).resolved.nullable == false
    end

    test "untyped inline fragment on a union does not crash and is hoisted to shared fields" do
      schema = schema_with_union()

      root =
        resolve_root(
          ~s|query Q($show: Boolean!) { search { ... @include(if: $show) { __typename } ... on User { id email } ... on Post { id title } } }|,
          TypedGql.Test.SkipInclude.UnionUntyped,
          :q,
          schema: schema
        )

      union = union_child(root)
      # No crash on the type-condition-less fragment; both typed variants build.
      assert Enum.find(union.children, &(&1.parent_type == "User"))
      assert Enum.find(union.children, &(&1.parent_type == "Post"))
    end
  end

  describe "field-level directive does not propagate into sub-selection" do
    test "@include on an embed field marks the embed nullable but not its children" do
      schema = SchemaHelper.build_schema(types: types_with_profile())

      tree =
        resolve_tree(
          ~s|query Q($show: Boolean!) { user(id: "1") { name profile @include(if: $show) { bio } } }|,
          TypedGql.Test.SkipInclude.FieldEmbed,
          :q,
          schema: schema
        )

      # The embed field itself is conditional -> nullable.
      assert field(tree, :profile).resolved.nullable == true

      # Its child `bio` keeps schema nullability (no propagation of the parent's directive).
      bio = field(node_for(tree.root, "Profile"), :bio)
      assert bio.query_field.directives == []
    end
  end

  describe "fragment directive over an object field" do
    test "inline-fragment @include marks an embed nullable but not its children" do
      schema = SchemaHelper.build_schema(types: types_with_profile())

      tree =
        resolve_tree(
          ~s|query Q($show: Boolean!) { user(id: "1") { name ... @include(if: $show) { profile { bio } } } }|,
          TypedGql.Test.SkipInclude.FragmentEmbed,
          :q,
          schema: schema
        )

      # The embed is a direct member of the conditional fragment -> nullable.
      assert field(tree, :profile).resolved.nullable == true

      # bio lives inside profile; the fragment directive does not reach it.
      bio = field(node_for(tree.root, "Profile"), :bio)
      assert bio.query_field.directives == []
    end
  end

  describe "SkipInclude.after_resolve/2 conditionality rules" do
    setup do
      context = %TypedGql.Generation.Context{schema: SchemaHelper.build_schema()}
      %{context: context}
    end

    test "@include(if: false) and @skip(if: true) still produce a nullable field", %{
      context: context
    } do
      for {directive_name, literal} <- [{"include", false}, {"skip", true}] do
        tree =
          object_with_field(
            scalar_field(:id, false, [boolean_directive(directive_name, literal)])
          )

        out = SkipInclude.after_resolve(tree, context)
        assert hd(out.fields).resolved.nullable == true
      end
    end

    test "a directive without an if: argument is not conditional", %{context: context} do
      directive = %TypedGql.Language.Directive{name: "skip", arguments: []}
      tree = object_with_field(scalar_field(:id, false, [directive]))

      out = SkipInclude.after_resolve(tree, context)
      assert hd(out.fields).resolved.nullable == false
    end

    test "embeds_many fields are left unchanged even when conditional", %{context: context} do
      embed = %Field{
        kind: :embeds_many,
        name: :posts,
        original_name: "posts",
        resolved: %{
          ecto_type: {:object, "Post"},
          nullable: false,
          enum_values: nil,
          inner_nullable: nil
        },
        embed_module: SomePostModule,
        query_field: %TypedGql.Language.Field{
          name: "posts",
          directives: [variable_directive("include", "show")]
        },
        schema_field: %TypedGql.Schema.Field{
          name: "posts",
          type: %TypedGql.Schema.TypeRef{kind: :object, name: "Post"}
        }
      }

      tree = object_with_field(embed)
      out = SkipInclude.after_resolve(tree, context)
      assert hd(out.fields).resolved.nullable == false
    end
  end

  describe "user generation_plugins" do
    test "a user plugin can transform a field (rename it)" do
      tree =
        resolve_tree(
          ~s|query Q { user(id: "1") { id name } }|,
          TypedGql.Test.SkipInclude.UserPlugin,
          :q,
          generation_plugins: [RenameFieldPlugin]
        )

      # The user plugin renamed :name -> :display_name in the resolved tree.
      assert field(tree, :display_name)
      refute Enum.any?(tree.user.fields, &(&1.name == :name))
      # id is untouched.
      refute nullable?(tree, :id)
    end
  end

  # Helpers

  # Returns the `User` node of the resolved tree (the queries below all select a
  # top-level `user` embed, so the fields under test live one level down).
  defp resolve_tree(query, client_module, function_name, opts \\ []) do
    schema = Keyword.get_lazy(opts, :schema, &SchemaHelper.build_schema/0)
    operation = parse!(query)

    # CapturePlugin must run last so it observes the fully-transformed tree
    # (after the built-in SkipInclude and any user generation_plugins). Order
    # matters, so a prepend won't do; the list is tiny so the append is fine.
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    plugins = Keyword.get(opts, :generation_plugins, []) ++ [CapturePlugin]

    TypeGenerator.generate(operation, schema,
      client_module: client_module,
      function_name: function_name,
      fragments: Keyword.get(opts, :fragments, %{}),
      generation_plugins: plugins
    )

    assert_received {:resolved_tree, root}
    %{root: root, user: node_for(root, "User")}
  end

  defp resolve_root(query, client_module, function_name, opts) do
    %{root: root} = resolve_tree(query, client_module, function_name, opts)
    root
  end

  defp union_child(%Schema{kind: :union} = node), do: node

  defp union_child(%Schema{children: children}) do
    Enum.find_value(children, &union_child/1)
  end

  defp union_child(_other), do: nil

  defp node_for(%Schema{parent_type: type} = node, type), do: node

  defp node_for(%Schema{children: children}, type) do
    Enum.find_value(children, fn child -> node_for(child, type) end)
  end

  defp node_for(_other, _type), do: nil

  defp field(%{user: %Schema{} = node}, name), do: field(node, name)

  defp field(%Schema{} = node, name) do
    Enum.find(node.fields, &(&1.name == name)) ||
      raise "field #{inspect(name)} not found in #{inspect(node.module)}"
  end

  defp nullable?(tree, name) do
    %Field{resolved: %{nullable: nullable}} = field(tree, name)
    nullable
  end

  defp object_with_field(%Field{} = field) do
    %Schema{kind: :object, module: HandBuilt, parent_type: "User", fields: [field], children: []}
  end

  defp scalar_field(name, nullable, directives) do
    %Field{
      kind: :field,
      name: name,
      original_name: Atom.to_string(name),
      resolved: %{ecto_type: :string, nullable: nullable, enum_values: nil, inner_nullable: nil},
      query_field: %TypedGql.Language.Field{name: Atom.to_string(name), directives: directives},
      schema_field: %TypedGql.Schema.Field{
        name: Atom.to_string(name),
        type: %TypedGql.Schema.TypeRef{kind: :scalar, name: "ID"}
      }
    }
  end

  defp boolean_directive(name, value) do
    %TypedGql.Language.Directive{
      name: name,
      arguments: [
        %TypedGql.Language.Argument{
          name: "if",
          value: %TypedGql.Language.BooleanValue{value: value}
        }
      ]
    }
  end

  defp variable_directive(name, var_name) do
    %TypedGql.Language.Directive{
      name: name,
      arguments: [
        %TypedGql.Language.Argument{
          name: "if",
          value: %TypedGql.Language.Variable{name: var_name}
        }
      ]
    }
  end

  defp parse!(query) do
    {:ok, %{definitions: [operation | _rest]}} = TypedGql.Parser.parse(query)
    operation
  end

  defp parse_fragment(source) do
    {:ok, %{definitions: [fragment | _rest]}} = TypedGql.Parser.parse(source)
    fragment
  end

  defp schema_with_union do
    type_ref = fn kind, name -> %TypedGql.Schema.TypeRef{kind: kind, name: name} end
    non_null = fn inner -> %TypedGql.Schema.TypeRef{kind: :non_null, of_type: inner} end

    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Query" => %TypedGql.Schema.Type{
          kind: :object,
          name: "Query",
          fields: %{
            "search" => %TypedGql.Schema.Field{
              name: "search",
              type:
                non_null.(%TypedGql.Schema.TypeRef{
                  kind: :list,
                  of_type: type_ref.(:union, "SearchResult")
                })
            }
          }
        },
        "SearchResult" => %TypedGql.Schema.Type{
          kind: :union,
          name: "SearchResult",
          possible_types: ["User", "Post"]
        },
        "User" => %TypedGql.Schema.Type{
          kind: :object,
          name: "User",
          fields: %{
            "__typename" => %TypedGql.Schema.Field{
              name: "__typename",
              type: non_null.(type_ref.(:scalar, "String"))
            },
            "id" => %TypedGql.Schema.Field{name: "id", type: non_null.(type_ref.(:scalar, "ID"))},
            "email" => %TypedGql.Schema.Field{name: "email", type: type_ref.(:scalar, "String")}
          }
        },
        "Post" => %TypedGql.Schema.Type{
          kind: :object,
          name: "Post",
          fields: %{
            "__typename" => %TypedGql.Schema.Field{
              name: "__typename",
              type: non_null.(type_ref.(:scalar, "String"))
            },
            "id" => %TypedGql.Schema.Field{name: "id", type: non_null.(type_ref.(:scalar, "ID"))},
            "title" => %TypedGql.Schema.Field{name: "title", type: type_ref.(:scalar, "String")}
          }
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  defp types_with_profile do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %TypedGql.Schema.Type{
        kind: :object,
        name: "User",
        fields: %{
          "name" => %TypedGql.Schema.Field{
            name: "name",
            type: %TypedGql.Schema.TypeRef{kind: :scalar, name: "String"}
          },
          "profile" => %TypedGql.Schema.Field{
            name: "profile",
            type: %TypedGql.Schema.TypeRef{
              kind: :non_null,
              of_type: %TypedGql.Schema.TypeRef{kind: :object, name: "Profile"}
            }
          }
        }
      },
      "Profile" => %TypedGql.Schema.Type{
        kind: :object,
        name: "Profile",
        fields: %{
          "bio" => %TypedGql.Schema.Field{
            name: "bio",
            type: %TypedGql.Schema.TypeRef{kind: :scalar, name: "String"}
          }
        }
      }
    })
  end
end
