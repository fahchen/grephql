defmodule Grephql.FormatterTest do
  use ExUnit.Case, async: true

  alias Grephql.Formatter

  describe "features/1" do
    test "declares ~G sigil" do
      assert Formatter.features([]) == [sigils: [:G]]
    end
  end

  describe "format/2" do
    test "formats a simple query" do
      input = "query GetUser($id: ID!) { user(id: $id) { name email } }"

      assert Formatter.format(input, sigil: :g) == """
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
      assert Formatter.format(invalid, sigil: :g) == invalid
    end

    test "returns original content for empty string" do
      assert Formatter.format("", sigil: :g) == ""
    end

    test "formats messy whitespace" do
      input = "  {   user(  id:  \"1\"  )  {  name  }  }  "

      assert Formatter.format(input, sigil: :g) == """
             {
               user(id: "1") {
                 name
               }
             }\
             """
    end

    test "is idempotent" do
      input = "query GetUser($id: ID!) { user(id: $id) { name posts { title } } }"
      first = Formatter.format(input, sigil: :g)
      second = Formatter.format(first, sigil: :g)
      assert first == second
    end

    test "formats query with inline fragments" do
      input = "{ search { ... on User { name } ... on Repo { fullName } } }"

      assert Formatter.format(input, sigil: :g) == """
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

      assert Formatter.format(input, sigil: :g) == """
             query($show: Boolean!) {
               user {
                 name @skip(if: $show)
                 email
               }
             }\
             """
    end
  end
end
