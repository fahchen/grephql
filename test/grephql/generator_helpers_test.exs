defmodule Grephql.GeneratorHelpersTest do
  use ExUnit.Case, async: true

  alias Grephql.GeneratorHelpers

  describe "enum_type_ast/2" do
    test "single value returns bare atom" do
      assert :open = GeneratorHelpers.enum_type_ast(["OPEN"])
    end

    test "multiple values returns union AST" do
      ast = GeneratorHelpers.enum_type_ast(["OPEN", "CLOSED"])
      assert {:|, [], [:open, :closed]} = ast
    end

    test "three values returns nested union AST" do
      ast = GeneratorHelpers.enum_type_ast(["ADMIN", "USER", "GUEST"])
      assert {:|, [], [:admin, {:|, [], [:user, :guest]}]} = ast
    end

    test "underscores SCREAMING_SNAKE values" do
      ast = GeneratorHelpers.enum_type_ast(["PULL_REQUEST", "ISSUE"])
      assert {:|, [], [:pull_request, :issue]} = ast
    end

    test "inner_nullable: false does not append nil" do
      ast = GeneratorHelpers.enum_type_ast(["OPEN", "CLOSED"], inner_nullable: false)
      assert {:|, [], [:open, :closed]} = ast
    end

    test "inner_nullable: nil does not append nil" do
      ast = GeneratorHelpers.enum_type_ast(["OPEN", "CLOSED"], inner_nullable: nil)
      assert {:|, [], [:open, :closed]} = ast
    end

    test "inner_nullable: true appends nil to union" do
      ast = GeneratorHelpers.enum_type_ast(["OPEN", "CLOSED"], inner_nullable: true)
      assert {:|, [], [{:|, [], [:open, :closed]}, nil]} = ast
    end

    test "single value with inner_nullable: true" do
      ast = GeneratorHelpers.enum_type_ast(["OPEN"], inner_nullable: true)
      assert {:|, [], [:open, nil]} = ast
    end
  end

  describe "scalar_typed_opts/1" do
    test "non-null enum field without inner_nullable" do
      resolved = %{nullable: false, enum_values: ["A", "B"], inner_nullable: nil}
      opts = GeneratorHelpers.scalar_typed_opts(resolved)

      assert opts[:null] == false
      assert opts[:type] == {:|, [], [:a, :b]}
    end

    test "nullable enum field without inner_nullable" do
      resolved = %{nullable: true, enum_values: ["A", "B"], inner_nullable: nil}
      opts = GeneratorHelpers.scalar_typed_opts(resolved)

      assert opts[:null] == true
      assert opts[:type] == {:|, [], [:a, :b]}
    end

    test "list enum with inner_nullable: true includes nil in type" do
      resolved = %{nullable: false, enum_values: ["OPEN", "CLOSED"], inner_nullable: true}
      opts = GeneratorHelpers.scalar_typed_opts(resolved)

      assert opts[:null] == false
      assert opts[:type] == {:|, [], [{:|, [], [:open, :closed]}, nil]}
    end

    test "list enum with inner_nullable: false excludes nil from type" do
      resolved = %{nullable: true, enum_values: ["OPEN", "CLOSED"], inner_nullable: false}
      opts = GeneratorHelpers.scalar_typed_opts(resolved)

      assert opts[:null] == true
      assert opts[:type] == {:|, [], [:open, :closed]}
    end

    test "non-enum field returns no type key" do
      resolved = %{nullable: true, enum_values: nil, inner_nullable: nil}
      opts = GeneratorHelpers.scalar_typed_opts(resolved)

      assert opts == [null: true]
      refute Keyword.has_key?(opts, :type)
    end
  end
end
