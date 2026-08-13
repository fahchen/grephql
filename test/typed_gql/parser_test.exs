defmodule TypedGql.ParserTest do
  use ExUnit.Case, async: true

  alias TypedGql.Language
  alias TypedGql.Parser

  describe "parse/1 simple query" do
    test "shorthand query" do
      assert {:ok, %Language.Document{definitions: [op]}} =
               Parser.parse("{ user { name } }")

      assert %Language.OperationDefinition{
               operation: :query,
               shorthand: true,
               selection_set: %Language.SelectionSet{selections: [user_field]}
             } = op

      assert %Language.Field{
               name: "user",
               selection_set: %Language.SelectionSet{selections: [name_field]}
             } = user_field

      assert %Language.Field{name: "name"} = name_field
    end

    test "named query" do
      assert {:ok, %Language.Document{definitions: [op]}} =
               Parser.parse("query GetUser { user { name email } }")

      assert %Language.OperationDefinition{
               operation: :query,
               name: "GetUser",
               selection_set: %Language.SelectionSet{selections: selections}
             } = op

      [user_field] = selections
      assert %Language.Field{name: "user"} = user_field
      assert length(user_field.selection_set.selections) == 2
    end
  end

  describe "parse/1 mutation" do
    test "named mutation with variables" do
      input = """
      mutation CreateUser($name: String!, $email: String) {
        createUser(name: $name, email: $email) {
          id
          name
        }
      }
      """

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      assert %Language.OperationDefinition{
               operation: :mutation,
               name: "CreateUser",
               variable_definitions: var_defs
             } = op

      assert length(var_defs) == 2

      [name_var, email_var] = var_defs

      assert %Language.VariableDefinition{
               variable: %Language.Variable{name: "name"},
               type: %Language.NonNullType{type: %Language.NamedType{name: "String"}}
             } = name_var

      assert %Language.VariableDefinition{
               variable: %Language.Variable{name: "email"},
               type: %Language.NamedType{name: "String"}
             } = email_var
    end
  end

  describe "parse/1 variables" do
    test "variable with default value" do
      input = "query($limit: Int = 10) { users { name } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [var_def] = op.variable_definitions
      assert %Language.VariableDefinition{default_value: %Language.IntValue{value: 10}} = var_def
    end

    test "list type variable" do
      input = "query($ids: [ID!]!) { users(ids: $ids) { name } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [var_def] = op.variable_definitions

      assert %Language.VariableDefinition{
               type: %Language.NonNullType{
                 type: %Language.ListType{
                   type: %Language.NonNullType{type: %Language.NamedType{name: "ID"}}
                 }
               }
             } = var_def
    end

    # Upstream keeps directives only on the default-value production; see
    # BDR-0008 G3.
    test "variable definition directives are kept, with or without a default value" do
      for input <- [
            "query($limit: Int @lower(by: 1)) { users { name } }",
            "query($limit: Int = 10 @lower(by: 1)) { users { name } }"
          ] do
        assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)
        [var_def] = op.variable_definitions

        assert [
                 %Language.Directive{
                   name: "lower",
                   arguments: [
                     %Language.Argument{name: "by", value: %Language.IntValue{value: 1}}
                   ]
                 }
               ] = var_def.directives
      end
    end
  end

  describe "parse/1 arguments" do
    test "field with inline arguments" do
      input = ~s|{ user(id: "123") { name } }|

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [user_field] = op.selection_set.selections

      assert %Language.Field{
               name: "user",
               arguments: [
                 %Language.Argument{name: "id", value: %Language.StringValue{value: "123"}}
               ]
             } = user_field
    end

    test "field with integer argument" do
      input = "{ users(limit: 10) { name } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [users_field] = op.selection_set.selections
      [arg] = users_field.arguments
      assert %Language.Argument{name: "limit", value: %Language.IntValue{value: 10}} = arg
    end

    test "field with boolean argument" do
      input = "{ users(active: true) { name } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [users_field] = op.selection_set.selections
      [arg] = users_field.arguments
      assert %Language.Argument{name: "active", value: %Language.BooleanValue{value: true}} = arg
    end

    test "field with enum argument" do
      input = "{ users(role: ADMIN) { name } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [users_field] = op.selection_set.selections
      [arg] = users_field.arguments
      assert %Language.Argument{name: "role", value: %Language.EnumValue{value: "ADMIN"}} = arg
    end

    test "field with null argument" do
      input = "{ user(id: null) { name } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [user_field] = op.selection_set.selections
      [arg] = user_field.arguments
      assert %Language.Argument{name: "id", value: %Language.NullValue{}} = arg
    end

    test "field with list argument" do
      input = ~s|{ users(ids: ["1", "2"]) { name } }|

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [users_field] = op.selection_set.selections
      [arg] = users_field.arguments
      assert %Language.Argument{name: "ids", value: %Language.ListValue{values: values}} = arg
      assert length(values) == 2
    end

    test "field with object argument" do
      input = ~s|{ createUser(input: {name: "Alice", age: 30}) { id } }|

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [field] = op.selection_set.selections
      [arg] = field.arguments
      assert %Language.Argument{name: "input", value: %Language.ObjectValue{fields: fields}} = arg
      assert length(fields) == 2

      assert %Language.ObjectField{name: "name", value: %Language.StringValue{value: "Alice"}} =
               hd(fields)
    end
  end

  describe "parse/1 directives" do
    test "field with directive" do
      input = "{ user { name @skip(if: true) } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [user_field] = op.selection_set.selections
      [name_field] = user_field.selection_set.selections

      assert %Language.Field{
               name: "name",
               directives: [
                 %Language.Directive{
                   name: "skip",
                   arguments: [
                     %Language.Argument{name: "if", value: %Language.BooleanValue{value: true}}
                   ]
                 }
               ]
             } = name_field
    end

    test "query operation with directive" do
      input = "query @cached { user { name } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)
      assert op.operation == :query
      assert [%Language.Directive{name: "cached"}] = op.directives
    end

    test "mutation operation with directive" do
      input = "mutation CreateUser @audit { createUser(input: {name: \"Alice\"}) { id } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)
      assert op.operation == :mutation
      assert op.name == "CreateUser"
      assert [%Language.Directive{name: "audit"}] = op.directives
    end
  end

  describe "parse/1 fragments" do
    test "fragment definition and spread" do
      input = """
      query {
        user {
          ...UserFields
        }
      }

      fragment UserFields on User {
        name
        email
      }
      """

      assert {:ok, %Language.Document{definitions: definitions}} = Parser.parse(input)
      assert length(definitions) == 2

      [op, frag] = definitions
      assert %Language.OperationDefinition{} = op

      assert %Language.Fragment{
               name: "UserFields",
               type_condition: %Language.NamedType{name: "User"},
               selection_set: %Language.SelectionSet{selections: selections}
             } = frag

      assert length(selections) == 2

      [spread] =
        op.selection_set.selections |> hd() |> Map.get(:selection_set) |> Map.get(:selections)

      assert %Language.FragmentSpread{name: "UserFields"} = spread
    end
  end

  describe "parse/1 inline fragments" do
    test "inline fragment with type condition" do
      input = """
      {
        search {
          ... on User { name }
          ... on Post { title }
        }
      }
      """

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [search_field] = op.selection_set.selections
      selections = search_field.selection_set.selections
      assert length(selections) == 2

      [user_frag, post_frag] = selections

      assert %Language.InlineFragment{
               type_condition: %Language.NamedType{name: "User"}
             } = user_frag

      assert %Language.InlineFragment{
               type_condition: %Language.NamedType{name: "Post"}
             } = post_frag
    end
  end

  describe "parse/1 aliases" do
    test "field alias" do
      input = "{ myUser: user { name } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [field] = op.selection_set.selections
      assert %Language.Field{alias: "myUser", name: "user"} = field
    end
  end

  describe "parse/1 nested selections" do
    test "deeply nested query" do
      input = """
      query {
        user {
          name
          posts {
            title
            comments {
              body
              author {
                name
              }
            }
          }
        }
      }
      """

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)

      [user] = op.selection_set.selections
      assert user.name == "user"

      [name, posts] = user.selection_set.selections
      assert name.name == "name"
      assert posts.name == "posts"

      [title, comments] = posts.selection_set.selections
      assert title.name == "title"
      assert comments.name == "comments"

      [body, author] = comments.selection_set.selections
      assert body.name == "body"
      assert author.name == "author"

      [author_name] = author.selection_set.selections
      assert author_name.name == "name"
    end
  end

  describe "parse/1 errors" do
    test "invalid syntax returns error" do
      assert {:error, message} = Parser.parse("{ user { }")
      assert is_binary(message)
    end

    test "completely invalid input" do
      assert {:error, message} = Parser.parse("\x00")
      assert is_binary(message)
    end

    # The grammar has no empty-selection-set production, so no downstream
    # consumer (generator, validator rules, traversal) can ever see one.
    test "an empty selection set is a syntax error" do
      assert {:error, _message} = Parser.parse("query { }")
      assert {:error, _message} = Parser.parse("query { user { } }")
      assert {:error, _message} = Parser.parse("fragment F on User { }")
      assert {:error, _message} = Parser.parse("query { ... on User { } }")
    end

    # The validator walks (Traversal, Variables, Fragments, Directives) and
    # Macros.__resolve_fragments__/2 match these three shapes with no fallback
    # clause, so a fourth production would have to be handled in each of them.
    # Reading the grammar is what pins that down; the parse below only shows the
    # three known forms round-trip.
    test "the grammar declares exactly three Selection productions" do
      productions =
        "src/typed_gql_parser.yrl"
        |> File.read!()
        |> then(&Regex.scan(~r/^Selection -> (\w+)/m, &1, capture: :all_but_first))
        |> List.flatten()

      assert productions == ["Field", "FragmentSpread", "InlineFragment"]
    end

    # `repeatable` is only a keyword inside a directive definition; see BDR-0008 G4.
    test "a field spelled `repeatable` is an ordinary name" do
      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse("query { repeatable }")
      assert [%Language.Field{name: "repeatable"}] = op.selection_set.selections
    end

    # See BDR-0008 G5.
    test "a leading pipe is allowed on a one-entry SDL list" do
      assert {:ok, %Language.Document{definitions: [union]}} = Parser.parse("union S = | User")
      assert [%Language.NamedType{name: "User"}] = union.types

      assert {:ok, %Language.Document{definitions: [directive]}} =
               Parser.parse("directive @d on | FIELD")

      assert directive.locations == [:field]
    end

    test "a selection is only ever a Field, FragmentSpread or InlineFragment" do
      assert {:ok, %Language.Document{definitions: [op]}} =
               Parser.parse("query { a b { c } ...F ... on User { d } ... { e } }")

      kinds =
        op.selection_set.selections
        |> Enum.map(& &1.__struct__)
        |> Enum.uniq()
        |> Enum.sort()

      assert kinds == [Language.Field, Language.FragmentSpread, Language.InlineFragment]
    end
  end

  describe "parse/1 location tracking" do
    test "nodes have location information" do
      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse("{ user { name } }")

      assert %{line: 1, column: _} = op.loc
    end

    test "an enum value points at its own token, not the argument" do
      assert [%Language.EnumValue{value: "GUEST", loc: %{line: 1, column: 27}}] =
               enum_values("query { usersByRole(role: GUEST) { name } }")
    end

    test "each enum value in a list keeps its own location" do
      assert [
               %{value: "ADMIN", loc: %{line: 1, column: 30}},
               %{value: "GUEST", loc: %{line: 1, column: 37}}
             ] = enum_values("query { usersByRoles(roles: [ADMIN, GUEST]) { name } }")
    end

    test "an enum value nested in an input object is located" do
      assert [%{value: "GUEST", loc: %{line: 1, column: 37}}] =
               enum_values(~s|mutation { createUser(input: {role: GUEST}) { id } }|)
    end

    test "an enum value on a later line keeps its line" do
      query = """
      query {
        usersByRole(
          role: GUEST
        ) { name }
      }
      """

      assert [%{loc: %{line: 3, column: 11}}] = enum_values(query)
    end

    test "an SDL enum value definition is located" do
      assert {:ok, %Language.Document{definitions: [enum]}} =
               Parser.parse("enum Role { ADMIN GUEST }")

      assert [
               %Language.EnumValueDefinition{value: "ADMIN", loc: %{line: 1, column: 13}},
               %Language.EnumValueDefinition{value: "GUEST", loc: %{line: 1, column: 19}}
             ] = enum.values
    end

    # `on` is a keyword to the lexer, so it reaches the grammar as a different
    # token shape than every other name.
    test "a name spelled `on` is located like any other name" do
      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse("query { on { x } }")

      assert [%Language.Field{name: "on", loc: %{line: 1, column: 9}}] =
               op.selection_set.selections

      assert [%Language.EnumValue{value: "on", loc: %{line: 1, column: 17}}] =
               enum_values("query { f(role: on) { x } }")
    end

    test "`ON` is an ordinary name, not the fragment keyword" do
      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse("query { ON { x } }")

      assert [%Language.Field{name: "ON", loc: %{line: 1, column: 9}}] =
               op.selection_set.selections

      assert [%Language.EnumValue{value: "ON", loc: %{line: 1, column: 17}}] =
               enum_values("query { f(role: ON) { x } }")

      assert {:ok, %Language.Document{definitions: [%Language.Fragment{name: "ON"}]}} =
               Parser.parse("fragment ON on User { name }")
    end
  end

  # https://spec.graphql.org/draft/#sec-Appendix-Grammar-Summary.Source-Text —
  # some positions take Value[Const], where a variable is not a valid value.
  # The grammar rejects them outright, so no validator rule is needed.
  describe "parse/1 constant-only positions" do
    test "a variable definition's default value cannot be a variable" do
      assert {:error, _message} = Parser.parse(~s|query Q($size: Int = $var) { user { name } }|)
    end

    test "a constant list or input object cannot contain a variable" do
      assert {:error, _message} =
               Parser.parse(~s|query Q($size: [Int] = [$var]) { user { name } }|)

      assert {:error, _message} = Parser.parse(~s|query Q($p: P = {x: $var}) { user { name } }|)
    end

    test "a variable definition's directive arguments cannot be variables" do
      assert {:error, _message} =
               Parser.parse(~s|query Q($size: Int @feature(name: $n)) { user { name } }|)

      assert {:error, _message} =
               Parser.parse(~s|query Q($size: Int = 1 @feature(name: $n)) { user { name } }|)
    end

    test "SDL directive arguments cannot be variables" do
      assert {:error, _message} = Parser.parse(~s|scalar Sweet @feature(name: $name)|)
      assert {:error, _message} = Parser.parse(~s|type Comment @feature(name: $name) { id: ID }|)
    end

    test "field arguments still accept variables" do
      assert {:ok, %Language.Document{}} =
               Parser.parse(~s|query Q($id: ID!) { user(id: $id) { name } }|)
    end
  end

  defp enum_values(query) do
    {:ok, document} = Parser.parse(query)
    collect_enum_values(document)
  end

  defp collect_enum_values(%Language.EnumValue{} = node), do: [node]

  defp collect_enum_values(%_struct{} = node) do
    node |> Map.from_struct() |> Map.values() |> collect_enum_values()
  end

  defp collect_enum_values(values) when is_list(values),
    do: Enum.flat_map(values, &collect_enum_values/1)

  defp collect_enum_values(_other), do: []
end
