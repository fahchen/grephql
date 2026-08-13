defmodule TypedGql.Validator.Rules.DirectivesTest do
  use ExUnit.Case, async: true

  alias TypedGql.Schema.Directive, as: SchemaDirective
  alias TypedGql.Schema.InputValue
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.Validator.Context
  alias TypedGql.Validator.Rules.Directives

  @skip_directive %SchemaDirective{
    name: "skip",
    locations: [:field, :inline_fragment],
    args: %{
      "if" => %InputValue{
        name: "if",
        type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "Boolean"}}
      }
    }
  }

  @include_directive %SchemaDirective{
    name: "include",
    locations: [:field, :inline_fragment],
    args: %{
      "if" => %InputValue{
        name: "if",
        type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "Boolean"}}
      }
    }
  }

  @deprecated_directive %SchemaDirective{
    name: "deprecated",
    locations: [:field_definition, :enum_value],
    args: %{
      "reason" => %InputValue{
        name: "reason",
        type: %TypeRef{kind: :scalar, name: "String"}
      }
    }
  }

  @operation_directive %SchemaDirective{
    name: "trace",
    locations: [:query, :mutation],
    args: %{
      "enabled" => %InputValue{
        name: "enabled",
        type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "Boolean"}}
      }
    }
  }

  @variable_definition_directive %SchemaDirective{
    name: "lower",
    locations: [:variable_definition],
    args: %{"by" => %InputValue{name: "by", type: %TypeRef{kind: :scalar, name: "Int"}}}
  }

  @query_only_directive %SchemaDirective{name: "trace", locations: [:query], args: %{}}

  describe "directive existence" do
    test "known directive passes" do
      ctx = validate(~s|query { user(id: "1") { name @skip(if: true) } }|)
      assert errors(ctx) == []
    end

    test "unknown directive fails" do
      ctx = validate(~s|query { user(id: "1") { name @foo } }|)
      assert [error] = errors(ctx)
      assert error.message =~ "unknown directive \"@foo\""
    end
  end

  describe "directive location" do
    test "directive on valid location passes" do
      ctx = validate(~s|query { user(id: "1") { name @skip(if: true) } }|)
      assert errors(ctx) == []
    end

    test "directive on query operation passes when allowed on QUERY" do
      ctx =
        validate(~s|query @trace(enabled: true) { user(id: "1") { name } }|,
          directives: [@operation_directive | default_directives()]
        )

      assert errors(ctx) == []
    end

    test "directive on mutation operation passes when allowed on MUTATION" do
      ctx =
        validate(~s|mutation @trace(enabled: false) { doThing }|,
          directives: [@operation_directive | default_directives()]
        )

      assert errors(ctx) == []
    end

    test "directive on invalid location fails" do
      ctx = validate(~s|query @skip(if: true) { user(id: "1") { name } }|)
      location_errors = Enum.filter(errors(ctx), &(&1.message =~ "not allowed"))
      assert [error] = location_errors
      assert error.message =~ "directive \"@skip\" is not allowed on query operations"
    end

    test "directive on invalid mutation location shows mutation label" do
      schema =
        SchemaHelper.build_schema(
          mutation_type: "Mutation",
          types:
            Map.merge(SchemaHelper.default_types(), %{
              "Mutation" => %TypedGql.Schema.Type{
                kind: :object,
                name: "Mutation",
                fields: %{
                  "doThing" => %TypedGql.Schema.Field{
                    name: "doThing",
                    type: %TypedGql.Schema.TypeRef{kind: :scalar, name: "Boolean"},
                    args: %{}
                  }
                }
              }
            }),
          directives: default_directives()
        )

      doc = parse!(~s|mutation @skip(if: true) { doThing }|)
      ctx = Directives.validate(doc, %Context{schema: schema})
      location_errors = Enum.filter(errors(ctx), &(&1.message =~ "not allowed"))
      assert [error] = location_errors
      assert error.message =~ "not allowed on mutation operations"
    end

    test "directive on fragment definition shows fragment definition label" do
      query = """
      query { user(id: "1") { ...UserFrag } }
      fragment UserFrag on User @skip(if: true) { name }
      """

      ctx = validate(query)
      location_errors = Enum.filter(errors(ctx), &(&1.message =~ "not allowed"))
      assert [error] = location_errors
      assert error.message =~ "not allowed on fragment definitions"
    end

    # Both spellings must reach the rule — upstream drops the directives on the
    # one without a default value; see BDR-0008 G3.
    test "directive on a variable definition shows the variable definition label" do
      for query <- [
            ~s|query Q($id: ID @skip(if: true)) { user(id: "1") { name } }|,
            ~s|query Q($id: ID = "1" @skip(if: true)) { user(id: "1") { name } }|
          ] do
        ctx = validate(query)
        location_errors = Enum.filter(errors(ctx), &(&1.message =~ "not allowed"))
        assert [error] = location_errors
        assert error.message =~ "not allowed on variable definitions"
      end
    end

    test "directive on a variable definition passes when allowed on VARIABLE_DEFINITION" do
      directives = [@variable_definition_directive | default_directives()]

      for query <- [
            ~s|query Q($id: ID @lower(by: 1)) { user(id: "1") { name } }|,
            ~s|query Q($id: ID = "1" @lower(by: 1)) { user(id: "1") { name } }|
          ] do
        assert errors(validate(query, directives: directives)) == []
      end
    end

    # "no errors" alone would also hold if the parser dropped the directive, so
    # prove the rule really inspected it by giving it a badly typed argument.
    test "arguments of a variable definition directive are checked" do
      directives = [@variable_definition_directive | default_directives()]

      for query <- [
            ~s|query Q($id: ID @lower(by: "one")) { user(id: "1") { name } }|,
            ~s|query Q($id: ID = "1" @lower(by: "one")) { user(id: "1") { name } }|
          ] do
        assert [error] = errors(validate(query, directives: directives))
        assert error.message =~ ~s(type mismatch for argument "by" on directive "@lower")
      end
    end
  end

  describe "directive location labels" do
    setup do
      %{directives: [@query_only_directive | default_directives()]}
    end

    test "field label", %{directives: directives} do
      ctx = validate(~s|query { user(id: "1") { name @trace } }|, directives: directives)
      assert location_error(ctx) =~ "not allowed on fields"
    end

    test "inline fragment label", %{directives: directives} do
      ctx =
        validate(~s|query { user(id: "1") { ... on User @trace { name } } }|,
          directives: directives
        )

      assert location_error(ctx) =~ "not allowed on inline fragments"
    end

    test "subscription label", %{directives: directives} do
      ctx =
        validate(~s|subscription @trace { user(id: "1") { name } }|, directives: directives)

      assert location_error(ctx) =~ "not allowed on subscription operations"
    end
  end

  describe "directive uniqueness" do
    test "unique directives pass" do
      ctx = validate(~s|query { user(id: "1") { name @skip(if: true) @include(if: false) } }|)
      assert errors(ctx) == []
    end

    test "duplicate directive fails" do
      ctx = validate(~s|query { user(id: "1") { name @skip(if: true) @skip(if: false) } }|)
      dup_errors = Enum.filter(errors(ctx), &(&1.message =~ "more than once"))
      assert [error] = dup_errors
      assert error.message =~ "directive \"@skip\" is used more than once"
    end
  end

  describe "directive arguments" do
    test "valid argument passes" do
      ctx = validate(~s|query { user(id: "1") { name @skip(if: true) } }|)
      assert errors(ctx) == []
    end

    test "unknown argument fails" do
      ctx = validate(~s|query { user(id: "1") { name @skip(if: true, foo: "bar") } }|)
      arg_errors = Enum.filter(errors(ctx), &(&1.message =~ "not defined on directive"))
      assert [error] = arg_errors
      assert error.message =~ "argument \"foo\" is not defined on directive \"@skip\""
    end

    test "missing required argument fails" do
      ctx = validate(~s|query { user(id: "1") { name @skip } }|)
      req_errors = Enum.filter(errors(ctx), &(&1.message =~ "required argument"))
      assert [error] = req_errors
      assert error.message =~ "required argument \"if\" is missing on directive \"@skip\""
    end

    test "wrong argument type fails" do
      ctx = validate(~s|query { user(id: "1") { name @skip(if: "yes") } }|)
      type_errors = Enum.filter(errors(ctx), &(&1.message =~ "type mismatch"))
      assert [error] = type_errors
      assert error.message =~ "type mismatch for argument \"if\" on directive \"@skip\""
    end

    test "correct argument type passes" do
      ctx = validate(~s|query { user(id: "1") { name @skip(if: true) } }|)
      type_errors = Enum.filter(errors(ctx), &(&1.message =~ "type mismatch"))
      assert type_errors == []
    end

    test "optional argument can be omitted" do
      directives = [
        %SchemaDirective{
          name: "cache",
          locations: [:field],
          args: %{
            "maxAge" => %InputValue{
              name: "maxAge",
              type: %TypeRef{kind: :scalar, name: "Int"}
            }
          }
        }
        | default_directives()
      ]

      ctx = validate(~s|query { user(id: "1") { name @cache } }|, directives: directives)
      req_errors = Enum.filter(errors(ctx), &(&1.message =~ "required argument"))
      assert req_errors == []
    end
  end

  describe "directive on inline fragment" do
    test "directive on inline fragment passes" do
      ctx =
        validate(~s|query { user(id: "1") { ... on User @skip(if: true) { name } } }|)

      assert errors(ctx) == []
    end
  end

  defp parse!(query) do
    {:ok, doc} = TypedGql.Parser.parse(query)
    doc
  end

  defp validate(query, opts \\ []) do
    directives = Keyword.get(opts, :directives, default_directives())
    schema = SchemaHelper.build_schema(directives: directives)
    ctx = %Context{schema: schema}
    Directives.validate(parse!(query), ctx)
  end

  defp errors(ctx), do: Context.errors_by_severity(ctx, :error)

  defp location_error(ctx) do
    [error] = Enum.filter(errors(ctx), &(&1.message =~ "not allowed"))
    error.message
  end

  defp default_directives do
    [@skip_directive, @include_directive, @deprecated_directive]
  end
end
