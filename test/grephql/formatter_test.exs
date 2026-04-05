defmodule Grephql.FormatterTest do
  use ExUnit.Case, async: true

  alias Grephql.Formatter

  describe "features/1" do
    test "declares ~GQL sigil" do
      assert Formatter.features([]) == [sigils: [:GQL]]
    end
  end

  describe "format/2" do
    test "inline sigil preserves original content" do
      input = "query GetUser($id: ID!) { user(id: $id) { name email } }"
      assert Formatter.format(input, sigil: :GQL) == input
    end

    test "returns original content on parse error" do
      invalid = "not valid graphql {"
      assert Formatter.format(invalid, sigil: :GQL) == invalid
    end

    test "returns original content for empty string" do
      assert Formatter.format("", sigil: :GQL) == ""
    end

    test "formats heredoc query" do
      input = "query GetUser($id: ID!) { user(id: $id) { name email } }"
      opts = [sigil: :GQL, opening_delimiter: ~S(""")]

      assert Formatter.format(input, opts) == """
             query GetUser($id: ID!) {
               user(id: $id) {
                 name
                 email
               }
             }
             """
    end

    test "formats heredoc with messy whitespace" do
      input = "  {   user(  id:  \"1\"  )  {  name  }  }  "
      opts = [sigil: :GQL, opening_delimiter: ~S(""")]

      assert Formatter.format(input, opts) == """
             {
               user(id: "1") {
                 name
               }
             }
             """
    end

    test "heredoc is idempotent" do
      input = "query GetUser($id: ID!) { user(id: $id) { name posts { title } } }"
      opts = [sigil: :GQL, opening_delimiter: ~S(""")]
      first = Formatter.format(input, opts)
      second = Formatter.format(first, opts)
      assert first == second
    end

    test "formats heredoc with inline fragments" do
      input = "{ search { ... on User { name } ... on Repo { fullName } } }"
      opts = [sigil: :GQL, opening_delimiter: ~S(""")]

      assert Formatter.format(input, opts) == """
             {
               search {
                 ... on User {
                   name
                 }
                 ... on Repo {
                   fullName
                 }
               }
             }
             """
    end

    test "formats heredoc with directives" do
      input = "query($show: Boolean!) { user { name @skip(if: $show) email } }"
      opts = [sigil: :GQL, opening_delimiter: ~S(""")]

      assert Formatter.format(input, opts) == """
             query($show: Boolean!) {
               user {
                 name @skip(if: $show)
                 email
               }
             }
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

    test "inline delimiter returns content unchanged" do
      input = "query GetUser($id: ID!) { user(id: $id) { name } }"

      result = Formatter.format(input, sigil: :GQL, opening_delimiter: ~S("))

      assert result == input
    end
  end
end
