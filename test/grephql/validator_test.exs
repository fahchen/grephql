defmodule Grephql.ValidatorTest do
  use ExUnit.Case, async: true

  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator

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

  defp parse!(query) do
    {:ok, doc} = Grephql.Parser.parse(query)
    doc
  end
end
