defmodule TypedGql.EnsureTypenameTest do
  use ExUnit.Case, async: true

  alias TypedGql.EnsureTypename
  alias TypedGql.Language.Field
  alias TypedGql.Language.Fragment
  alias TypedGql.Language.OperationDefinition
  alias TypedGql.Language.SelectionSet
  alias TypedGql.Schema.Field, as: SchemaField
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper

  describe "__typename injection" do
    test "a selection on a union gets one" do
      selections = root_field(transform!(~s|query { search { ... on User { name } } }|))

      assert [%Field{name: "__typename", alias: nil, directives: []} | _rest] = selections
    end

    test "a selection on an interface gets one" do
      selections = root_field(transform!(~s|query { node { ... on User { name } } }|))

      assert [%Field{name: "__typename", alias: nil, directives: []} | _rest] = selections
    end

    test "a selection on an object type does not" do
      selections = root_field(transform!(~s|query { user(id: "1") { name } }|))

      assert typename_count(selections) == 0
    end

    test "an explicit __typename is not duplicated" do
      selections =
        root_field(transform!(~s|query { search { __typename ... on User { name } } }|))

      assert typename_count(selections) == 1
    end

    test "a __typename a directive can remove does not count as the discriminator" do
      # Dispatch happens before @skip is resolved, so the conditional copy cannot
      # be relied on and a plain one is added alongside it.
      selections =
        ~s|query Q($hide: Boolean!) { search { __typename @skip(if: $hide) ... on User { name } } }|
        |> transform!()
        |> root_field()

      assert typename_count(selections) == 2
    end

    test "an abstract selection inside a named fragment definition gets one" do
      document =
        transform!("query { ...F }\nfragment F on Query { search { ... on User { name } } }")

      assert [%Fragment{} = fragment] =
               Enum.filter(document.definitions, &match?(%Fragment{}, &1))

      assert [%Field{name: "search"} = search] = fragment.selection_set.selections
      assert typename_count(search.selection_set.selections) == 1
    end
  end

  describe "borrowed __typename response key" do
    test "a field aliased to the __typename key is rejected" do
      error =
        assert_raise CompileError, fn ->
          transform!(~s|query { search { __typename: id ... on User { name } } }|)
        end

      assert error.description ==
               "\"__typename\" is aliased to another field on a union or interface " <>
                 "selection, leaving no response key to dispatch on"
    end

    test "an alias hiding in a nested inline fragment is rejected" do
      assert_raise CompileError, ~r/leaving no response key to dispatch on/, fn ->
        transform!(~s|query { search { ... on User { __typename: id } } }|)
      end
    end

    test "an alias hiding in a fragment spread body is rejected" do
      assert_raise CompileError, ~r/leaving no response key to dispatch on/, fn ->
        transform!(~s|query { search { ...F } }\nfragment F on User { __typename: id }|)
      end
    end

    test "a spread naming an unknown fragment is tolerated" do
      # Resolution reports the missing fragment; this stage must not crash on it.
      selections = root_field(transform!(~s|query { search { ...Missing } }|))

      assert typename_count(selections) == 1
    end

    test "__typename aliased to itself keeps the key and is allowed" do
      # Same field, same response key: the server merges the two, so nothing is
      # taken from dispatch.
      selections = root_field(transform!(~s|query { search { __typename: __typename } }|))

      assert typename_count(selections) == 2
    end

    test "an alias one response level down, under a field, is not rejected" do
      # `friend`'s sub-selection is its own response key space, so it cannot
      # collide with the injected field.
      selections =
        root_field(transform!(~s|query { search { ... on User { friend { __typename: id } } } }|))

      assert typename_count(selections) == 1
    end

    @tag timeout: 5_000
    test "mutually recursive spreads are walked once each" do
      # The `seen` set is the assertion: without it the spread walk never returns.
      document =
        transform!("""
        query { search { ...A } }
        fragment A on User { ...B }
        fragment B on User { ...A name }
        """)

      assert typename_count(root_field(document)) == 1
    end
  end

  defp transform!(query) do
    {:ok, document} = TypedGql.Parser.parse(query)
    EnsureTypename.transform(document, schema())
  end

  # The selections of the document's single root field — where an injected
  # __typename lands.
  defp root_field(document) do
    [%OperationDefinition{} = operation | _rest] = document.definitions
    %SelectionSet{selections: [%Field{} = field]} = operation.selection_set
    field.selection_set.selections
  end

  defp typename_count(selections),
    do: Enum.count(selections, &match?(%Field{name: "__typename"}, &1))

  defp schema do
    defaults = SchemaHelper.default_types()
    query = defaults["Query"]

    types =
      Map.merge(defaults, %{
        "Query" => %{query | fields: Map.merge(query.fields, abstract_root_fields())},
        "SearchResult" => %Type{
          kind: :union,
          name: "SearchResult",
          possible_types: ["User", "Post"]
        },
        "Node" => %Type{
          kind: :interface,
          name: "Node",
          possible_types: ["User"],
          fields: %{
            "id" => %SchemaField{
              name: "id",
              type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
            }
          }
        },
        "Post" => %Type{
          kind: :object,
          name: "Post",
          fields: %{
            "title" => %SchemaField{name: "title", type: %TypeRef{kind: :scalar, name: "String"}}
          }
        },
        "User" => %{
          defaults["User"]
          | fields:
              Map.put(defaults["User"].fields, "friend", %SchemaField{
                name: "friend",
                type: %TypeRef{kind: :object, name: "User"}
              })
        }
      })

    SchemaHelper.build_schema(types: types)
  end

  defp abstract_root_fields do
    %{
      "search" => %SchemaField{
        name: "search",
        type: %TypeRef{kind: :union, name: "SearchResult"},
        args: %{}
      },
      "node" => %SchemaField{
        name: "node",
        type: %TypeRef{kind: :interface, name: "Node"},
        args: %{}
      }
    }
  end
end
