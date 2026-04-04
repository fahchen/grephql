defmodule Grephql.LexerTest do
  use ExUnit.Case, async: true

  alias Grephql.Lexer

  describe "tokenize/1 punctuators" do
    test "single-character punctuators" do
      assert {:ok, tokens} = Lexer.tokenize("{ } ( ) [ ] : = ! | $ @")

      names = Enum.map(tokens, &elem(&1, 0))

      assert names == [
               :"{",
               :"}",
               :"(",
               :")",
               :"[",
               :"]",
               :":",
               :=,
               :!,
               :"|",
               :"$",
               :@
             ]
    end

    test "spread operator ..." do
      assert {:ok, [{:..., {1, 1}}]} = Lexer.tokenize("...")
    end
  end

  describe "tokenize/1 names" do
    test "simple name" do
      assert {:ok, [{:name, {1, 1}, ~c"foo"}]} = Lexer.tokenize("foo")
    end

    test "name starting with underscore" do
      assert {:ok, [{:name, {1, 1}, ~c"_private"}]} = Lexer.tokenize("_private")
    end

    test "name with digits" do
      assert {:ok, [{:name, {1, 1}, ~c"field1"}]} = Lexer.tokenize("field1")
    end
  end

  describe "tokenize/1 reserved words" do
    test "query keyword" do
      assert {:ok, [{:query, {1, 1}}]} = Lexer.tokenize("query")
    end

    test "mutation keyword" do
      assert {:ok, [{:mutation, {1, 1}}]} = Lexer.tokenize("mutation")
    end

    test "fragment keyword" do
      assert {:ok, [{:fragment, {1, 1}}]} = Lexer.tokenize("fragment")
    end

    test "type keyword" do
      assert {:ok, [{:type, {1, 1}}]} = Lexer.tokenize("type")
    end

    test "on keyword" do
      assert {:ok, [{:on, {1, 1}}]} = Lexer.tokenize("on")
    end

    test "null keyword" do
      assert {:ok, [{:null, {1, 1}}]} = Lexer.tokenize("null")
    end
  end

  describe "tokenize/1 boolean values" do
    test "true" do
      assert {:ok, [{:boolean_value, {1, 1}, ~c"true"}]} = Lexer.tokenize("true")
    end

    test "false" do
      assert {:ok, [{:boolean_value, {1, 1}, ~c"false"}]} = Lexer.tokenize("false")
    end
  end

  describe "tokenize/1 integers" do
    test "positive integer" do
      assert {:ok, [{:int_value, {1, 1}, ~c"42"}]} = Lexer.tokenize("42")
    end

    test "negative integer" do
      assert {:ok, [{:int_value, {1, 1}, ~c"-1"}]} = Lexer.tokenize("-1")
    end

    test "zero" do
      assert {:ok, [{:int_value, {1, 1}, ~c"0"}]} = Lexer.tokenize("0")
    end
  end

  describe "tokenize/1 floats" do
    test "simple float" do
      assert {:ok, [{:float_value, {1, 1}, ~c"3.14"}]} = Lexer.tokenize("3.14")
    end

    test "float with exponent" do
      assert {:ok, [{:float_value, {1, 1}, ~c"1.0e10"}]} = Lexer.tokenize("1.0e10")
    end

    test "float with fractional and exponent" do
      assert {:ok, [{:float_value, {1, 1}, ~c"2.5e3"}]} = Lexer.tokenize("2.5e3")
    end

    test "negative float" do
      assert {:ok, [{:float_value, {1, 1}, ~c"-0.5"}]} = Lexer.tokenize("-0.5")
    end
  end

  describe "tokenize/1 strings" do
    test "simple string" do
      assert {:ok, [{:string_value, {1, 1}, ~c"\"hello\""}]} = Lexer.tokenize(~s("hello"))
    end

    test "string with escape sequences" do
      assert {:ok, [{:string_value, {1, 1}, value}]} = Lexer.tokenize(~s("line\\nbreak"))
      assert value == ~c"\"line\nbreak\""
    end

    test "string with unicode escape" do
      assert {:ok, [{:string_value, {1, 1}, value}]} = Lexer.tokenize(~s("\\u0041"))
      assert to_string(value) == ~s("A")
    end
  end

  describe "tokenize/1 block strings" do
    test "simple block string" do
      input = ~s(\"\"\"hello world\"\"\")

      assert {:ok, [{:block_string_value, {1, 1}, value}]} = Lexer.tokenize(input)
      assert to_string(value) == ~s(\"\"\"hello world\"\"\")
    end
  end

  describe "tokenize/1 ignored tokens" do
    test "whitespace is ignored" do
      assert {:ok, [{:name, {1, 1}, ~c"a"}, {:name, {1, 3}, ~c"b"}]} =
               Lexer.tokenize("a b")
    end

    test "commas are ignored" do
      assert {:ok, [{:name, {1, 1}, ~c"a"}, {:name, {1, 3}, ~c"b"}]} =
               Lexer.tokenize("a,b")
    end

    test "comments are ignored" do
      assert {:ok, [{:name, {1, 1}, ~c"a"}, {:name, {2, 1}, ~c"b"}]} =
               Lexer.tokenize("a # comment\nb")
    end
  end

  describe "tokenize/1 line tracking" do
    test "tracks line numbers across newlines" do
      input = "{\n  name\n}"

      assert {:ok, tokens} = Lexer.tokenize(input)

      assert [
               {:"{", {1, 1}},
               {:name, {2, 3}, ~c"name"},
               {:"}", {3, 1}}
             ] = tokens
    end
  end

  describe "tokenize/1 full query" do
    test "simple query" do
      input = """
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          email
        }
      }
      """

      assert {:ok, tokens} = Lexer.tokenize(input)
      names = Enum.map(tokens, &elem(&1, 0))

      assert names == [
               :query,
               :name,
               :"(",
               :"$",
               :name,
               :":",
               :name,
               :!,
               :")",
               :"{",
               :name,
               :"(",
               :name,
               :":",
               :"$",
               :name,
               :")",
               :"{",
               :name,
               :name,
               :"}",
               :"}"
             ]
    end
  end

  describe "tokenize/1 errors" do
    test "invalid character returns error" do
      assert {:error, _rest, {1, _col}} = Lexer.tokenize("query \x00")
    end
  end

  describe "tokenize/2 token limit" do
    test "returns error when token limit exceeded" do
      assert {:error, :exceeded_token_limit} =
               Lexer.tokenize("a b c d e", token_limit: 3)
    end

    test "succeeds within token limit" do
      assert {:ok, tokens} = Lexer.tokenize("a b c", token_limit: 5)
      assert length(tokens) == 3
    end
  end
end
