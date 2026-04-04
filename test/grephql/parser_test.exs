defmodule Grephql.ParserTest do
  use ExUnit.Case, async: true

  alias Grephql.Language
  alias Grephql.Parser

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

    test "operation with directive" do
      input = "query @cached { user { name } }"

      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse(input)
      assert [%Language.Directive{name: "cached"}] = op.directives
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
  end

  describe "parse/1 location tracking" do
    test "nodes have location information" do
      assert {:ok, %Language.Document{definitions: [op]}} = Parser.parse("{ user { name } }")

      assert %{line: 1, column: _} = op.loc
    end
  end
end
