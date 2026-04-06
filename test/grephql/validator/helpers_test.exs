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

  alias Grephql.Language.ListValue
  alias Grephql.Language.ObjectValue
  alias Grephql.Test.SchemaHelper

  describe "unwrap_type/1" do
    test "returns nil for nil input" do
      assert Helpers.unwrap_type(nil) == nil
    end

    test "returns named type ref unchanged" do
      ref = %TypeRef{kind: :scalar, name: "String"}
      assert Helpers.unwrap_type(ref) == ref
    end

    test "unwraps non_null wrapper" do
      inner = %TypeRef{kind: :scalar, name: "String"}
      ref = %TypeRef{kind: :non_null, of_type: inner}
      assert Helpers.unwrap_type(ref) == inner
    end

    test "unwraps nested non_null > list > object" do
      inner = %TypeRef{kind: :object, name: "User"}
      ref = %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :list, of_type: inner}}
      assert Helpers.unwrap_type(ref) == inner
    end
  end

  describe "root_type_name/2" do
    test "returns subscription type name" do
      schema = SchemaHelper.build_schema(subscription_type: "Subscription")
      assert Helpers.root_type_name(schema, :subscription) == "Subscription"
    end

    test "returns nil when subscription type is not set" do
      schema = SchemaHelper.build_schema()
      assert Helpers.root_type_name(schema, :subscription) == nil
    end
  end

  describe "unwrap_list_type/1" do
    test "returns inner type from list" do
      inner = %TypeRef{kind: :scalar, name: "String"}
      assert Helpers.unwrap_list_type(%TypeRef{kind: :list, of_type: inner}) == inner
    end

    test "unwraps non_null wrapping a list" do
      inner = %TypeRef{kind: :scalar, name: "String"}
      ref = %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :list, of_type: inner}}
      assert Helpers.unwrap_list_type(ref) == inner
    end

    test "returns nil for non-list type" do
      assert Helpers.unwrap_list_type(%TypeRef{kind: :scalar, name: "String"}) == nil
    end
  end

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

    test "ListValue is compatible with any type" do
      list = %ListValue{values: []}
      assert Helpers.compatible_value?(list, "String")
    end

    test "ObjectValue is compatible with any type" do
      obj = %ObjectValue{fields: []}
      assert Helpers.compatible_value?(obj, "SomeInput")
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
