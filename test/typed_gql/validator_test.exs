defmodule TypedGql.ValidatorTest do
  use ExUnit.Case, async: true

  alias TypedGql.Schema.Directive, as: SchemaDirective
  alias TypedGql.Schema.Field
  alias TypedGql.Schema.InputValue
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.Validator
  alias TypedGql.Validator.Error

  describe "validate/2" do
    test "returns :ok for a valid query" do
      schema = SchemaHelper.build_schema()
      doc = parse!(~s|query { user(id: "1") { name } }|)
      assert :ok = Validator.validate(doc, schema)
    end

    test "accepts directive on query operation when schema allows QUERY" do
      schema = SchemaHelper.build_schema(directives: [operation_directive([:query])])
      doc = parse!(~s|query @trace(enabled: true) { user(id: "1") { name } }|)

      assert :ok = Validator.validate(doc, schema)
    end

    test "accepts directive on mutation operation when schema allows MUTATION" do
      schema =
        SchemaHelper.build_schema(
          mutation_type: "Mutation",
          types: Map.put(SchemaHelper.default_types(), "Mutation", mutation_type()),
          directives: [operation_directive([:mutation])]
        )

      doc = parse!(~s|mutation @trace(enabled: true) { doThing }|)

      assert :ok = Validator.validate(doc, schema)
    end

    test "returns {:error, errors} for invalid query" do
      schema = SchemaHelper.build_schema()
      doc = parse!("mutation { createUser { id } }")
      assert {:error, [error]} = Validator.validate(doc, schema)
      assert error.message =~ "mutations"
    end

    test "collects errors from multiple rules" do
      schema = SchemaHelper.build_schema()
      doc = parse!("query { nonExistent @bogus }")

      assert {:error, errors} = Validator.validate(doc, schema)
      messages = Enum.map(errors, & &1.message)

      # One from Rules.Fields, one from Rules.Directives.
      assert ~s(field "nonExistent" does not exist on type "Query") in messages
      assert ~s(unknown directive "@bogus") in messages
    end
  end

  describe "validate_fragment/3" do
    test "returns :ok for a valid fragment" do
      schema = SchemaHelper.build_schema()
      doc = parse!("fragment UserFields on User { name email }")
      assert :ok = Validator.validate_fragment(doc, schema)
    end

    test "returns {:error, errors} for an invalid fragment" do
      schema = SchemaHelper.build_schema()
      doc = parse!("fragment UserFields on User { nonExistent }")
      assert {:error, [error]} = Validator.validate_fragment(doc, schema)
      assert error.message =~ "nonExistent"
    end
  end

  describe "error formatting with caller_env offset" do
    test "error on non-first line has correct raw line/column" do
      schema = SchemaHelper.build_schema()

      doc =
        parse!("""
        query {
          user(id: "1") {
            nonExistent
          }
        }
        """)

      assert {:error, [error]} = Validator.validate(doc, schema)
      assert error.line == 3
      assert error.column == 5
    end

    test "Error.format with offset adds caller_env.line to error line" do
      schema = SchemaHelper.build_schema()

      doc =
        parse!("""
        query {
          user(id: "1") {
            nonExistent
          }
        }
        """)

      assert {:error, [error]} = Validator.validate(doc, schema)
      # line 3 + offset 50 = 53, column unchanged
      assert Error.format(error, 50) ==
               "(53:5) field \"nonExistent\" does not exist on type \"User\""
    end

    test "Error.format without offset uses raw line" do
      schema = SchemaHelper.build_schema()

      doc =
        parse!("""
        query {
          user(id: "1") {
            nonExistent
          }
        }
        """)

      assert {:error, [error]} = Validator.validate(doc, schema)
      assert Error.format(error) == "(3:5) field \"nonExistent\" does not exist on type \"User\""
    end
  end

  defp parse!(query) do
    {:ok, doc} = TypedGql.Parser.parse(query)
    doc
  end

  defp operation_directive(locations) do
    %SchemaDirective{
      name: "trace",
      locations: locations,
      args: %{
        "enabled" => %InputValue{
          name: "enabled",
          type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "Boolean"}}
        }
      }
    }
  end

  defp mutation_type do
    %Type{
      kind: :object,
      name: "Mutation",
      fields: %{
        "doThing" => %Field{
          name: "doThing",
          type: %TypeRef{kind: :scalar, name: "Boolean"},
          args: %{}
        }
      }
    }
  end
end
