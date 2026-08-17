defmodule TypedGql.Validator.TraversalTest do
  use ExUnit.Case, async: true

  alias TypedGql.Schema.Field, as: SchemaField
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.Validator.Traversal

  describe "traverse_operations/4" do
    test "visits every field of an operation with the type that declares it" do
      query = ~s|query { user(id: "1") { name email } }|

      assert visit_operations(query) == [
               {"user", "Query"},
               {"name", "User"},
               {"email", "User"}
             ]
    end

    test "descends into nested selection sets" do
      query = ~s|query { user(id: "1") { posts { title } } }|

      assert visit_operations(query, types: types_with_posts()) == [
               {"user", "Query"},
               {"posts", "User"},
               {"title", "Post"}
             ]
    end

    test "threads the accumulator through every callback" do
      query = ~s|query { user(id: "1") { name email } }|
      count = fn _field, _type_name, acc -> acc + 1 end

      assert traverse(:operations, query, [], 0, count) == 3
    end

    test "visits the fields of every operation in the document" do
      query = """
      query One { user(id: "1") { name } }
      query Two { users { email } }
      """

      assert visit_operations(query) == [
               {"user", "Query"},
               {"name", "User"},
               {"users", "Query"},
               {"email", "User"}
             ]
    end

    test "ignores fragment definitions" do
      query = """
      query { user(id: "1") { name } }
      fragment F on User { email }
      """

      assert visit_operations(query) == [{"user", "Query"}, {"name", "User"}]
    end

    test "resolves the root type from the operation kind" do
      query = ~s|mutation { user(id: "1") { name } }|

      # The schema declares no mutation root, so the whole operation is visited
      # with a nil parent type rather than skipped — Operations already reported it.
      assert visit_operations(query) == [{"user", nil}, {"name", nil}]
    end

    test "an operation whose root type the schema omits still visits its fields" do
      query = ~s|query { user(id: "1") { name } }|

      assert visit_operations(query, query_type: nil) == [{"user", nil}, {"name", nil}]
    end
  end

  describe "traverse_fragments/4" do
    test "visits fragment fields with the type condition as the parent type" do
      query = "fragment F on User { name email }"

      assert visit_fragments(query) == [{"name", "User"}, {"email", "User"}]
    end

    test "ignores operation definitions" do
      query = """
      query { user(id: "1") { name } }
      fragment F on User { email }
      """

      assert visit_fragments(query) == [{"email", "User"}]
    end

    test "threads the accumulator through every callback" do
      count = fn _field, _type_name, acc -> acc + 1 end

      assert traverse(:fragments, "fragment F on User { name email }", [], 0, count) == 2
    end
  end

  describe "traverse_all/4" do
    test "visits operation fields first, then fragment fields" do
      query = """
      query { user(id: "1") { name } }
      fragment F on User { email }
      """

      assert visit_all(query) == [
               {"user", "Query"},
               {"name", "User"},
               {"email", "User"}
             ]
    end

    test "threads one accumulator across operations and fragments" do
      query = """
      query { user(id: "1") { name } }
      fragment F on User { email }
      """

      count = fn _field, _type_name, acc -> acc + 1 end

      assert traverse(:all, query, [], 0, count) == 3
    end
  end

  describe "unresolvable parent types" do
    test "a field the schema does not declare is still handed to the callback" do
      query = ~s|query { ghost { name } }|

      assert {"ghost", "Query"} in visit_operations(query)
    end

    test "the children of an unresolvable field are visited with a nil parent type" do
      query = ~s|query { ghost { name } }|

      assert visit_operations(query) == [{"ghost", "Query"}, {"name", nil}]
    end

    test "a field whose declared type is absent from the schema still names that type" do
      # `user` is declared to return "Ghost", a name the schema has no type for.
      # The traversal reports the declared name unchecked; resolving it is the
      # callback's problem.
      query = ~s|query { user(id: "1") { name } }|

      assert visit_operations(query, types: types_with_dangling_field_type()) == [
               {"user", "Query"},
               {"name", "Ghost"}
             ]
    end
  end

  describe "inline fragments" do
    test "selections are visited under the inline fragment's type condition" do
      query = ~s|query { user(id: "1") { ... on User { name } } }|

      assert visit_operations(query) == [{"user", "Query"}, {"name", "User"}]
    end

    test "a type condition replaces the enclosing parent type" do
      query = ~s|query { user(id: "1") { ... on Node { id } } }|

      assert visit_operations(query, types: types_with_node()) == [
               {"user", "Query"},
               {"id", "Node"}
             ]
    end

    # Passing nil here made every rule built on this traversal skip the
    # selections, so an unknown field inside `... { }` went unreported.
    test "an inline fragment without a type condition keeps the enclosing parent type" do
      query = ~s|query { user(id: "1") { ... { name } } }|

      assert visit_operations(query) == [{"user", "Query"}, {"name", "User"}]
    end

    test "nested inline fragments are descended" do
      query = ~s|query { user(id: "1") { ... on User { ... on User { name } } } }|

      assert visit_operations(query) == [{"user", "Query"}, {"name", "User"}]
    end
  end

  describe "fragment spreads" do
    test "a spread is not descended into from the operation that spreads it" do
      query = """
      query { user(id: "1") { ...F } }
      fragment F on User { name }
      """

      assert visit_operations(query) == [{"user", "Query"}]
    end

    test "the spread fragment's own definition is visited by traverse_all/4 exactly once" do
      query = """
      query { user(id: "1") { ...F ...F } }
      fragment F on User { name }
      """

      assert visit_all(query) == [{"user", "Query"}, {"name", "User"}]
    end
  end

  defp parse!(query) do
    {:ok, doc} = TypedGql.Parser.parse(query)
    doc
  end

  # Records {field_name, parent_type_name} in visit order.
  defp collect(field, type_name, acc), do: [{field.name, type_name} | acc]

  defp visit_operations(query, schema_opts \\ []) do
    Enum.reverse(traverse(:operations, query, schema_opts, [], &collect/3))
  end

  defp visit_fragments(query, schema_opts \\ []) do
    Enum.reverse(traverse(:fragments, query, schema_opts, [], &collect/3))
  end

  defp visit_all(query, schema_opts \\ []) do
    Enum.reverse(traverse(:all, query, schema_opts, [], &collect/3))
  end

  defp traverse(kind, query, schema_opts, acc, callback) do
    definitions = parse!(query).definitions
    schema = SchemaHelper.build_schema(schema_opts)

    case kind do
      :operations -> Traversal.traverse_operations(definitions, schema, acc, callback)
      :fragments -> Traversal.traverse_fragments(definitions, schema, acc, callback)
      :all -> Traversal.traverse_all(definitions, schema, acc, callback)
    end
  end

  defp types_with_posts do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "posts" => %SchemaField{name: "posts", type: %TypeRef{kind: :object, name: "Post"}}
        }
      },
      "Post" => %Type{
        kind: :object,
        name: "Post",
        fields: %{
          "title" => %SchemaField{name: "title", type: %TypeRef{kind: :scalar, name: "String"}}
        }
      }
    })
  end

  defp types_with_node do
    Map.merge(SchemaHelper.default_types(), %{
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
      }
    })
  end

  defp types_with_dangling_field_type do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %SchemaField{
            name: "user",
            type: %TypeRef{kind: :object, name: "Ghost"},
            args: %{}
          }
        }
      }
    })
  end
end
