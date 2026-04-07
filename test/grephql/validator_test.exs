defmodule Grephql.ValidatorTest do
  use ExUnit.Case, async: true

  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator
  alias Grephql.Validator.Error

  describe "validate/2" do
    test "returns :ok for a valid query" do
      schema = SchemaHelper.build_schema()
      doc = parse!(~s|query { user(id: "1") { name } }|)
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
      doc = parse!("mutation { bogusField }")
      assert {:error, errors} = Validator.validate(doc, schema)
      assert errors != []
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
    {:ok, doc} = Grephql.Parser.parse(query)
    doc
  end
end
