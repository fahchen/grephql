defmodule Grephql.TypeMapperTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema.TypeRef
  alias Grephql.TypeMapper

  # Schema is only accessed for enum resolution; empty schema is safe for non-enum tests
  @no_schema %Grephql.Schema{}

  describe "built-in scalar mapping" do
    test "String! maps to :string, non-nullable" do
      type_ref = non_null(scalar("String"))

      assert %{ecto_type: :string, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "String (nullable) maps to :string, nullable" do
      type_ref = scalar("String")
      assert %{ecto_type: :string, nullable: true} = TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "Int! maps to :integer" do
      type_ref = non_null(scalar("Int"))

      assert %{ecto_type: :integer, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "Float! maps to :float" do
      type_ref = non_null(scalar("Float"))
      assert %{ecto_type: :float, nullable: false} = TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "Boolean! maps to :boolean" do
      type_ref = non_null(scalar("Boolean"))

      assert %{ecto_type: :boolean, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "ID! maps to :string" do
      type_ref = non_null(scalar("ID"))

      assert %{ecto_type: :string, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "Date maps to :date" do
      type_ref = scalar("Date")
      assert %{ecto_type: :date, nullable: true} = TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "JSON maps to :map" do
      type_ref = scalar("JSON")
      assert %{ecto_type: :map, nullable: true} = TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "JSONObject maps to :map" do
      type_ref = scalar("JSONObject")
      assert %{ecto_type: :map, nullable: true} = TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "URI maps to :string" do
      type_ref = scalar("URI")
      assert %{ecto_type: :string, nullable: true} = TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "URL maps to :string" do
      type_ref = scalar("URL")
      assert %{ecto_type: :string, nullable: true} = TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "BigInt maps to :integer" do
      type_ref = scalar("BigInt")

      assert %{ecto_type: :integer, nullable: true} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "HTML maps to :string" do
      type_ref = scalar("HTML")
      assert %{ecto_type: :string, nullable: true} = TypeMapper.resolve(type_ref, @no_schema, %{})
    end
  end

  describe "custom scalar mapping" do
    test "user-provided scalar type module" do
      type_ref = non_null(scalar("DateTime"))
      scalar_types = %{"DateTime" => MyApp.Types.DateTime}

      assert %{ecto_type: MyApp.Types.DateTime, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, scalar_types)
    end

    test "built-in custom scalar fallback (DateTime)" do
      type_ref = non_null(scalar("DateTime"))

      assert %{ecto_type: Grephql.Types.DateTime, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "user-provided scalar overrides built-in" do
      type_ref = non_null(scalar("DateTime"))
      scalar_types = %{"DateTime" => MyApp.CustomDateTime}

      assert %{ecto_type: MyApp.CustomDateTime, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, scalar_types)
    end

    test "unknown scalar raises CompileError" do
      type_ref = non_null(scalar("FooBarBaz"))

      assert_raise CompileError, ~r/unknown scalar type "FooBarBaz"/, fn ->
        TypeMapper.resolve(type_ref, @no_schema, %{})
      end
    end
  end

  describe "enum mapping" do
    test "auto-resolves enum to Grephql.Types.Enum with values" do
      schema = schema_with_enum("Role", ["ADMIN", "USER", "GUEST"])
      type_ref = non_null(enum_ref("Role"))

      assert %{
               ecto_type: Grephql.Types.Enum,
               nullable: false,
               enum_values: ["ADMIN", "USER", "GUEST"]
             } = TypeMapper.resolve(type_ref, schema, %{})
    end

    test "nullable enum" do
      schema = schema_with_enum("Status", ["ACTIVE", "INACTIVE"])
      type_ref = enum_ref("Status")

      assert %{
               ecto_type: Grephql.Types.Enum,
               nullable: true,
               enum_values: ["ACTIVE", "INACTIVE"]
             } = TypeMapper.resolve(type_ref, schema, %{})
    end

    test "user scalar_types override for enum (no enum_values)" do
      schema = schema_with_enum("Role", ["ADMIN", "USER"])
      type_ref = non_null(enum_ref("Role"))
      scalar_types = %{"Role" => Grephql.Test.RoleEnum}

      assert %{ecto_type: Grephql.Test.RoleEnum, nullable: false, enum_values: nil} =
               TypeMapper.resolve(type_ref, schema, scalar_types)
    end
  end

  describe "list combinations" do
    test "[User!]! — non-null list of non-null items" do
      type_ref = non_null(list(non_null(object("User"))))

      assert %{ecto_type: {:array, {:object, "User"}}, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "[User!] — nullable list of non-null items" do
      type_ref = list(non_null(object("User")))

      assert %{ecto_type: {:array, {:object, "User"}}, nullable: true} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "[User]! — non-null list of nullable items" do
      type_ref = non_null(list(object("User")))

      assert %{ecto_type: {:array, {:object, "User"}}, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "[User] — nullable list of nullable items" do
      type_ref = list(object("User"))

      assert %{ecto_type: {:array, {:object, "User"}}, nullable: true} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "[String!]! — list of non-null scalars" do
      type_ref = non_null(list(non_null(scalar("String"))))

      assert %{ecto_type: {:array, :string}, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end
  end

  describe "object types" do
    test "non-null object returns {:object, name}" do
      type_ref = non_null(object("User"))

      assert %{ecto_type: {:object, "User"}, nullable: false} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "nullable object" do
      type_ref = object("User")

      assert %{ecto_type: {:object, "User"}, nullable: true} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "interface type" do
      type_ref = %TypeRef{kind: :interface, name: "Node"}

      assert %{ecto_type: {:object, "Node"}, nullable: true} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "union type" do
      type_ref = %TypeRef{kind: :union, name: "SearchResult"}

      assert %{ecto_type: {:object, "SearchResult"}, nullable: true} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end

    test "input_object type" do
      type_ref = %TypeRef{kind: :input_object, name: "CreateUserInput"}

      assert %{ecto_type: {:object, "CreateUserInput"}, nullable: true} =
               TypeMapper.resolve(type_ref, @no_schema, %{})
    end
  end

  # Helper constructors

  defp scalar(name), do: %TypeRef{kind: :scalar, name: name}
  defp object(name), do: %TypeRef{kind: :object, name: name}
  defp enum_ref(name), do: %TypeRef{kind: :enum, name: name}
  defp non_null(inner), do: %TypeRef{kind: :non_null, of_type: inner}
  defp list(inner), do: %TypeRef{kind: :list, of_type: inner}

  defp schema_with_enum(enum_name, values) do
    enum_values = Enum.map(values, &%Grephql.Schema.EnumValue{name: &1, is_deprecated: false})

    type = %Grephql.Schema.Type{
      kind: :enum,
      name: enum_name,
      enum_values: enum_values
    }

    %Grephql.Schema{types: %{enum_name => type}}
  end
end
