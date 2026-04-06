defmodule Grephql.Types.EnumTest do
  use ExUnit.Case, async: true

  alias Grephql.Types.Enum, as: EnumType

  @params EnumType.init(values: ["ADMIN", "USER", "GUEST"])

  describe "type/1" do
    test "returns :string" do
      assert EnumType.type(@params) == :string
    end
  end

  describe "cast/2" do
    test "casts exact uppercase string to atom" do
      assert {:ok, :admin} = EnumType.cast("ADMIN", @params)
      assert {:ok, :user} = EnumType.cast("USER", @params)
      assert {:ok, :guest} = EnumType.cast("GUEST", @params)
    end

    test "casts case-insensitively" do
      assert {:ok, :admin} = EnumType.cast("admin", @params)
      assert {:ok, :admin} = EnumType.cast("Admin", @params)
      assert {:ok, :admin} = EnumType.cast("aDmIn", @params)
    end

    test "casts atom to itself" do
      assert {:ok, :admin} = EnumType.cast(:admin, @params)
    end

    test "casts nil to nil" do
      assert {:ok, nil} = EnumType.cast(nil, @params)
    end

    test "rejects invalid string" do
      assert :error = EnumType.cast("SUPERADMIN", @params)
    end

    test "rejects invalid atom" do
      assert :error = EnumType.cast(:superadmin, @params)
    end

    test "rejects non-string non-atom" do
      assert :error = EnumType.cast(123, @params)
    end
  end

  describe "dump/3" do
    test "dumps atom to original GraphQL string" do
      assert {:ok, "ADMIN"} = EnumType.dump(:admin, &Ecto.Type.dump/2, @params)
      assert {:ok, "USER"} = EnumType.dump(:user, &Ecto.Type.dump/2, @params)
    end

    test "dumps nil to nil" do
      assert {:ok, nil} = EnumType.dump(nil, &Ecto.Type.dump/2, @params)
    end

    test "rejects invalid atom" do
      assert :error = EnumType.dump(:superadmin, &Ecto.Type.dump/2, @params)
    end

    test "rejects non-atom" do
      assert :error = EnumType.dump("ADMIN", &Ecto.Type.dump/2, @params)
    end
  end

  describe "load/3" do
    test "loads string case-insensitively to atom" do
      assert {:ok, :admin} = EnumType.load("ADMIN", &Ecto.Type.load/2, @params)
      assert {:ok, :admin} = EnumType.load("admin", &Ecto.Type.load/2, @params)
      assert {:ok, :guest} = EnumType.load("Guest", &Ecto.Type.load/2, @params)
    end

    test "loads nil to nil" do
      assert {:ok, nil} = EnumType.load(nil, &Ecto.Type.load/2, @params)
    end

    test "rejects invalid string" do
      assert :error = EnumType.load("BOGUS", &Ecto.Type.load/2, @params)
    end

    test "rejects non-string" do
      assert :error = EnumType.load(:admin, &Ecto.Type.load/2, @params)
    end
  end

  describe "underscore conversion" do
    test "converts camelCase enum values to snake_case atoms" do
      params = EnumType.init(values: ["FooBar", "bazQux"])
      assert {:ok, :foo_bar} = EnumType.cast("FooBar", params)
      assert {:ok, :baz_qux} = EnumType.cast("bazQux", params)
      assert {:ok, "FooBar"} = EnumType.dump(:foo_bar, &Ecto.Type.dump/2, params)
    end
  end

  describe "define/2" do
    test "creates a standalone module wrapping the parameterized type" do
      EnumType.define(Grephql.Test.StatusEnum, ["ACTIVE", "INACTIVE"])

      assert {:ok, :active} = Grephql.Test.StatusEnum.cast("ACTIVE")
      assert {:ok, :active} = Grephql.Test.StatusEnum.cast("active")
      assert {:ok, "INACTIVE"} = Grephql.Test.StatusEnum.dump(:inactive)
      assert {:ok, :active} = Grephql.Test.StatusEnum.load("ACTIVE")
      assert {:ok, :active} = Grephql.Test.StatusEnum.load("active")
    end
  end
end
