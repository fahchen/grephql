defmodule TypedGql.GeneratorHelpersTest do
  use ExUnit.Case, async: true

  # Defined at test runtime by create_modules/1, so the compiler cannot see it.
  @compile {:no_warn_undefined, TypedGql.Test.CreateModulesSequential}

  alias TypedGql.GeneratorHelpers

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

  describe "build_params_type_ast/2" do
    test "field with custom type override uses that type" do
      custom_type = quote(do: :open | :closed)
      field_defs = [{:field, :status, :string, [typed: [type: custom_type, null: false]]}]
      ast = GeneratorHelpers.build_params_type_ast(field_defs, [:status])
      {:%{}, [], [{key, type}]} = ast
      assert {:required, [], [:status]} = key
      # Should use the custom type, not String.t()
      assert type == custom_type
    end

    test "embeds_many field generates list type" do
      field_defs = [{:embeds_many, :posts, MyApp.Post, [typed: [null: false]]}]
      ast = GeneratorHelpers.build_params_type_ast(field_defs, [:posts])
      {:%{}, [], [{_key, type}]} = ast
      # Should be [MyApp.Post.params()]
      assert Macro.to_string(type) =~ "MyApp.Post.params()"
    end

    test "nullable field wraps type with nil" do
      field_defs = [{:field, :name, :string, [typed: [null: true]]}]
      ast = GeneratorHelpers.build_params_type_ast(field_defs, [])
      {:%{}, [], [{key, _type}]} = ast
      assert {:optional, [], [:name]} = key
    end

    test "a non-keyword typed: option reads as no options, not a crash" do
      field_defs = [{:field, :name, :string, [typed: true]}]
      ast = GeneratorHelpers.build_params_type_ast(field_defs, [])
      {:%{}, [], [{_key, type}]} = ast
      assert Macro.to_string(type) == "String.t() | nil"
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

  describe "typed opts producers" do
    # nullable_from_opts/1 reads `:typed` with Keyword.get/3 and has no fallback
    # for a non-list, so every producer feeding {:typed, opts} must return one.
    test "always return a keyword list, whatever the resolved type looks like" do
      for nullable <- [true, false],
          enum_values <- [nil, ["OPEN", "CLOSED"]],
          inner_nullable <- [nil, true, false] do
        resolved = %{
          nullable: nullable,
          enum_values: enum_values,
          inner_nullable: inner_nullable
        }

        assert Keyword.keyword?(GeneratorHelpers.scalar_typed_opts(resolved))
        assert Keyword.keyword?(GeneratorHelpers.embed_typed_opts(:embeds_one, resolved))
        assert Keyword.keyword?(GeneratorHelpers.embed_typed_opts(:embeds_many, resolved))
      end
    end
  end

  describe "ecto_type_to_type_ast/1" do
    test "maps each built-in scalar to its typespec AST" do
      assert GeneratorHelpers.ecto_type_to_type_ast(:string) == quote(do: String.t())
      assert GeneratorHelpers.ecto_type_to_type_ast(:integer) == quote(do: integer())
      assert GeneratorHelpers.ecto_type_to_type_ast(:float) == quote(do: float())
      assert GeneratorHelpers.ecto_type_to_type_ast(:boolean) == quote(do: boolean())
    end

    test "wraps arrays and delegates custom types to their t/0" do
      assert GeneratorHelpers.ecto_type_to_type_ast({:array, :integer}) == quote(do: [integer()])

      ast = GeneratorHelpers.ecto_type_to_type_ast(TypedGql.Types.DateTime)
      assert Macro.to_string(ast) == "TypedGql.Types.DateTime.t()"
    end
  end

  describe "create_modules/1" do
    test "falls back to sequential creation outside a compiler session" do
      # A test process is never a Kernel.ParallelCompiler worker, so pmap/2
      # raises here and the sequential path runs.
      ast = quote(do: def(hello, do: :world))

      assert GeneratorHelpers.create_modules([{TypedGql.Test.CreateModulesSequential, ast}]) ==
               :ok

      assert TypedGql.Test.CreateModulesSequential.hello() == :world
    end
  end
end
