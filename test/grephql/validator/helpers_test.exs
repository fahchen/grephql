defmodule Grephql.Validator.HelpersTest do
  use ExUnit.Case, async: true

  alias Grephql.Language.Argument
  alias Grephql.Language.BooleanValue
  alias Grephql.Language.EnumValue
  alias Grephql.Language.FloatValue
  alias Grephql.Language.IntValue
  alias Grephql.Language.NullValue
  alias Grephql.Language.StringValue
  alias Grephql.Language.Variable
  alias Grephql.Schema.TypeRef
  alias Grephql.Validator.Helpers

  describe "variable?/1" do
    test "returns true for Variable" do
      assert Helpers.variable?(%Variable{name: "id"})
    end

    test "returns false for non-Variable" do
      refute Helpers.variable?(%StringValue{value: "hello"})
      refute Helpers.variable?(%IntValue{value: 42})
    end
  end

  describe "compatible_value?/2" do
    test "IntValue is compatible with Int, Float, ID" do
      int = %IntValue{value: 1}
      assert Helpers.compatible_value?(int, "Int")
      assert Helpers.compatible_value?(int, "Float")
      assert Helpers.compatible_value?(int, "ID")
      refute Helpers.compatible_value?(int, "String")
      refute Helpers.compatible_value?(int, "Boolean")
    end

    test "FloatValue is compatible with Float only" do
      float = %FloatValue{value: 1.0}
      assert Helpers.compatible_value?(float, "Float")
      refute Helpers.compatible_value?(float, "Int")
    end

    test "StringValue is compatible with String and ID" do
      str = %StringValue{value: "hello"}
      assert Helpers.compatible_value?(str, "String")
      assert Helpers.compatible_value?(str, "ID")
      refute Helpers.compatible_value?(str, "Int")
    end

    test "BooleanValue is compatible with Boolean only" do
      bool = %BooleanValue{value: true}
      assert Helpers.compatible_value?(bool, "Boolean")
      refute Helpers.compatible_value?(bool, "String")
    end

    test "NullValue is compatible with any type" do
      null = %NullValue{}
      assert Helpers.compatible_value?(null, "String")
      assert Helpers.compatible_value?(null, "Int")
    end

    test "EnumValue is compatible with any type" do
      enum = %EnumValue{value: "ACTIVE"}
      assert Helpers.compatible_value?(enum, "Status")
      assert Helpers.compatible_value?(enum, "Role")
    end
  end

  describe "value_type_mismatch?/2" do
    test "returns false for variable values" do
      arg = %Argument{name: "id", value: %Variable{name: "id"}}
      type_ref = %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}

      refute Helpers.value_type_mismatch?(arg, type_ref)
    end

    test "returns false when value is compatible" do
      arg = %Argument{name: "active", value: %BooleanValue{value: true}}
      type_ref = %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "Boolean"}}

      refute Helpers.value_type_mismatch?(arg, type_ref)
    end

    test "returns true when value is incompatible" do
      arg = %Argument{name: "active", value: %StringValue{value: "yes"}}
      type_ref = %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "Boolean"}}

      assert Helpers.value_type_mismatch?(arg, type_ref)
    end

    test "handles nullable type refs" do
      arg = %Argument{name: "count", value: %StringValue{value: "abc"}}
      type_ref = %TypeRef{kind: :scalar, name: "Int"}

      assert Helpers.value_type_mismatch?(arg, type_ref)
    end
  end
end
