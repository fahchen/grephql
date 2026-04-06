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

  describe "deprecation warnings" do
    test "emits warnings without caller_env" do
      types =
        Map.merge(SchemaHelper.default_types(), %{
          "User" => %Grephql.Schema.Type{
            kind: :object,
            name: "User",
            fields: %{
              "name" => %Grephql.Schema.Field{
                name: "name",
                type: %Grephql.Schema.TypeRef{kind: :scalar, name: "String"}
              },
              "email" => %Grephql.Schema.Field{
                name: "email",
                type: %Grephql.Schema.TypeRef{kind: :scalar, name: "String"},
                is_deprecated: true,
                deprecation_reason: "use contactEmail"
              }
            }
          }
        })

      schema = SchemaHelper.build_schema(types: types)
      doc = parse!(~s|query { user(id: "1") { email } }|)

      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert :ok = Validator.validate(doc, schema)
        end)

      assert output =~ "deprecated"
    end

    test "emits warnings with caller_env" do
      types =
        Map.merge(SchemaHelper.default_types(), %{
          "User" => %Grephql.Schema.Type{
            kind: :object,
            name: "User",
            fields: %{
              "name" => %Grephql.Schema.Field{
                name: "name",
                type: %Grephql.Schema.TypeRef{kind: :scalar, name: "String"}
              },
              "email" => %Grephql.Schema.Field{
                name: "email",
                type: %Grephql.Schema.TypeRef{kind: :scalar, name: "String"},
                is_deprecated: true,
                deprecation_reason: "use contactEmail"
              }
            }
          }
        })

      schema = SchemaHelper.build_schema(types: types)
      doc = parse!(~s|query { user(id: "1") { email } }|)

      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert :ok = Validator.validate(doc, schema, __ENV__)
        end)

      assert output =~ "deprecated"
    end
  end

  defp parse!(query) do
    {:ok, doc} = Grephql.Parser.parse(query)
    doc
  end
end
