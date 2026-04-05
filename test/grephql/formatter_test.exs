defmodule Grephql.FormatterTest do
  use ExUnit.Case, async: true

  alias Grephql.Formatter

  describe "features/1" do
    test "declares ~GQL sigil" do
      assert Formatter.features([]) == [sigils: [:GQL]]
    end
  end

  describe "format/2" do
    test "formats a simple query" do
      input = "query GetUser($id: ID!) { user(id: $id) { name email } }"

      assert Formatter.format(input, sigil: :GQLQL) == """
             query GetUser($id: ID!) {
               user(id: $id) {
                 name
                 email
               }
             }\
             """
    end

    test "returns original content on parse error" do
      invalid = "not valid graphql {"
      assert Formatter.format(invalid, sigil: :GQLQL) == invalid
    end

    test "returns original content for empty string" do
      assert Formatter.format("", sigil: :GQLQL) == ""
    end

    test "formats messy whitespace" do
      input = "  {   user(  id:  \"1\"  )  {  name  }  }  "

      assert Formatter.format(input, sigil: :GQLQL) == """
             {
               user(id: "1") {
                 name
               }
             }\
             """
    end

    test "is idempotent" do
      input = "query GetUser($id: ID!) { user(id: $id) { name posts { title } } }"
      first = Formatter.format(input, sigil: :GQLQL)
      second = Formatter.format(first, sigil: :GQLQL)
      assert first == second
    end

    test "formats query with inline fragments" do
      input = "{ search { ... on User { name } ... on Repo { fullName } } }"

      assert Formatter.format(input, sigil: :GQLQL) == """
             {
               search {
                 ... on User {
                   name
                 }
                 ... on Repo {
                   fullName
                 }
               }
             }\
             """
    end

    test "formats query with directives" do
      input = "query($show: Boolean!) { user { name @skip(if: $show) email } }"

      assert Formatter.format(input, sigil: :GQLQL) == """
             query($show: Boolean!) {
               user {
                 name @skip(if: $show)
                 email
               }
             }\
             """
    end

    test "appends trailing newline for double-quote heredoc delimiter" do
      input = "query GetUser($id: ID!) { user(id: $id) { name } }"

      result = Formatter.format(input, sigil: :GQL, opening_delimiter: ~S("""))

      assert String.ends_with?(result, "}\n")
    end

    test "appends trailing newline for single-quote heredoc delimiter" do
      input = "query GetUser($id: ID!) { user(id: $id) { name } }"

      result = Formatter.format(input, sigil: :GQL, opening_delimiter: ~S('''))

      assert String.ends_with?(result, "}\n")
    end

    test "no trailing newline for inline delimiter" do
      input = "query GetUser($id: ID!) { user(id: $id) { name } }"

      result = Formatter.format(input, sigil: :GQL, opening_delimiter: ~S("))

      refute String.ends_with?(result, "}\n")
    end

    test "heredoc format is idempotent" do
      input = "query GetUser($id: ID!) { user(id: $id) { name } }"
      opts = [sigil: :GQL, opening_delimiter: ~S(""")]

      first = Formatter.format(input, opts)
      second = Formatter.format(first, opts)
      assert first == second
    end
  end
end
