defmodule Grephql.TypeMapperTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema.TypeRef
  alias Grephql.TypeMapper

  describe "built-in scalar mapping" do
    test "String! maps to :string, non-nullable" do
      type_ref = non_null(scalar("String"))
      assert %{ecto_type: :string, nullable: false} = TypeMapper.resolve(type_ref, %{})
    end

    test "String (nullable) maps to :string, nullable" do
      type_ref = scalar("String")
      assert %{ecto_type: :string, nullable: true} = TypeMapper.resolve(type_ref, %{})
    end

    test "Int! maps to :integer" do
      type_ref = non_null(scalar("Int"))
      assert %{ecto_type: :integer, nullable: false} = TypeMapper.resolve(type_ref, %{})
    end

    test "Float! maps to :float" do
      type_ref = non_null(scalar("Float"))
      assert %{ecto_type: :float, nullable: false} = TypeMapper.resolve(type_ref, %{})
    end

    test "Boolean! maps to :boolean" do
      type_ref = non_null(scalar("Boolean"))
      assert %{ecto_type: :boolean, nullable: false} = TypeMapper.resolve(type_ref, %{})
    end

    test "ID! maps to :string" do
      type_ref = non_null(scalar("ID"))
      assert %{ecto_type: :string, nullable: false} = TypeMapper.resolve(type_ref, %{})
    end
  end

  describe "custom scalar mapping" do
    test "user-provided scalar type module" do
      type_ref = non_null(scalar("DateTime"))
      scalar_types = %{"DateTime" => MyApp.Types.DateTime}

      assert %{ecto_type: MyApp.Types.DateTime, nullable: false} =
               TypeMapper.resolve(type_ref, scalar_types)
    end

    test "built-in custom scalar fallback (DateTime)" do
      type_ref = non_null(scalar("DateTime"))

      assert %{ecto_type: Grephql.Types.DateTime, nullable: false} =
               TypeMapper.resolve(type_ref, %{})
    end

    test "user-provided scalar overrides built-in" do
      type_ref = non_null(scalar("DateTime"))
      scalar_types = %{"DateTime" => MyApp.CustomDateTime}

      assert %{ecto_type: MyApp.CustomDateTime, nullable: false} =
               TypeMapper.resolve(type_ref, scalar_types)
    end

    test "unknown scalar raises CompileError" do
      type_ref = non_null(scalar("JSON"))

      assert_raise CompileError, ~r/unknown scalar type "JSON"/, fn ->
        TypeMapper.resolve(type_ref, %{})
      end
    end
  end

  describe "enum mapping" do
    test "enum type resolves via scalar_types" do
      type_ref = non_null(enum_ref("Role"))
      scalar_types = %{"Role" => Grephql.Test.RoleEnum}

      assert %{ecto_type: Grephql.Test.RoleEnum, nullable: false} =
               TypeMapper.resolve(type_ref, scalar_types)
    end

    test "nullable enum" do
      type_ref = enum_ref("Role")
      scalar_types = %{"Role" => Grephql.Test.RoleEnum}

      assert %{ecto_type: Grephql.Test.RoleEnum, nullable: true} =
               TypeMapper.resolve(type_ref, scalar_types)
    end
  end

  describe "list combinations" do
    test "[User!]! — non-null list of non-null items" do
      type_ref = non_null(list(non_null(object("User"))))

      assert %{ecto_type: {:array, {:object, "User"}}, nullable: false} =
               TypeMapper.resolve(type_ref, %{})
    end

    test "[User!] — nullable list of non-null items" do
      type_ref = list(non_null(object("User")))

      assert %{ecto_type: {:array, {:object, "User"}}, nullable: true} =
               TypeMapper.resolve(type_ref, %{})
    end

    test "[User]! — non-null list of nullable items" do
      type_ref = non_null(list(object("User")))

      assert %{ecto_type: {:array, {:object, "User"}}, nullable: false} =
               TypeMapper.resolve(type_ref, %{})
    end

    test "[User] — nullable list of nullable items" do
      type_ref = list(object("User"))

      assert %{ecto_type: {:array, {:object, "User"}}, nullable: true} =
               TypeMapper.resolve(type_ref, %{})
    end

    test "[String!]! — list of non-null scalars" do
      type_ref = non_null(list(non_null(scalar("String"))))

      assert %{ecto_type: {:array, :string}, nullable: false} =
               TypeMapper.resolve(type_ref, %{})
    end
  end

  describe "object types" do
    test "non-null object returns {:object, name}" do
      type_ref = non_null(object("User"))

      assert %{ecto_type: {:object, "User"}, nullable: false} =
               TypeMapper.resolve(type_ref, %{})
    end

    test "nullable object" do
      type_ref = object("User")

      assert %{ecto_type: {:object, "User"}, nullable: true} =
               TypeMapper.resolve(type_ref, %{})
    end

    test "interface type" do
      type_ref = %TypeRef{kind: :interface, name: "Node"}

      assert %{ecto_type: {:object, "Node"}, nullable: true} =
               TypeMapper.resolve(type_ref, %{})
    end

    test "union type" do
      type_ref = %TypeRef{kind: :union, name: "SearchResult"}

      assert %{ecto_type: {:object, "SearchResult"}, nullable: true} =
               TypeMapper.resolve(type_ref, %{})
    end

    test "input_object type" do
      type_ref = %TypeRef{kind: :input_object, name: "CreateUserInput"}

      assert %{ecto_type: {:object, "CreateUserInput"}, nullable: true} =
               TypeMapper.resolve(type_ref, %{})
    end
  end

  # Helper constructors

  defp scalar(name), do: %TypeRef{kind: :scalar, name: name}
  defp object(name), do: %TypeRef{kind: :object, name: name}
  defp enum_ref(name), do: %TypeRef{kind: :enum, name: name}
  defp non_null(inner), do: %TypeRef{kind: :non_null, of_type: inner}
  defp list(inner), do: %TypeRef{kind: :list, of_type: inner}
end
