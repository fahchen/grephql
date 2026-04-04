defmodule Grephql.Types.EnumTest do
  use ExUnit.Case, async: true

  alias Grephql.Types.Enum, as: EnumType

  setup_all do
    EnumType.define(Grephql.Test.RoleEnum, ["ADMIN", "USER", "GUEST"])
    :ok
  end

  describe "type/0" do
    test "returns :string" do
      assert Grephql.Test.RoleEnum.type() == :string
    end
  end

  describe "cast/1" do
    test "casts uppercase string to atom" do
      assert {:ok, :admin} = Grephql.Test.RoleEnum.cast("ADMIN")
      assert {:ok, :user} = Grephql.Test.RoleEnum.cast("USER")
      assert {:ok, :guest} = Grephql.Test.RoleEnum.cast("GUEST")
    end

    test "casts atom to itself" do
      assert {:ok, :admin} = Grephql.Test.RoleEnum.cast(:admin)
    end

    test "rejects invalid string" do
      assert :error = Grephql.Test.RoleEnum.cast("SUPERADMIN")
    end

    test "rejects invalid atom" do
      assert :error = Grephql.Test.RoleEnum.cast(:superadmin)
    end

    test "rejects non-string non-atom" do
      assert :error = Grephql.Test.RoleEnum.cast(123)
    end
  end

  describe "dump/1" do
    test "dumps atom to uppercase string" do
      assert {:ok, "ADMIN"} = Grephql.Test.RoleEnum.dump(:admin)
      assert {:ok, "USER"} = Grephql.Test.RoleEnum.dump(:user)
    end

    test "rejects invalid atom" do
      assert :error = Grephql.Test.RoleEnum.dump(:superadmin)
    end

    test "rejects non-atom" do
      assert :error = Grephql.Test.RoleEnum.dump("ADMIN")
    end
  end

  describe "load/1" do
    test "loads uppercase string to atom" do
      assert {:ok, :admin} = Grephql.Test.RoleEnum.load("ADMIN")
      assert {:ok, :guest} = Grephql.Test.RoleEnum.load("GUEST")
    end

    test "rejects invalid string" do
      assert :error = Grephql.Test.RoleEnum.load("BOGUS")
    end

    test "rejects non-string" do
      assert :error = Grephql.Test.RoleEnum.load(:admin)
    end
  end

  describe "define/2" do
    test "creates a module with Ecto.Type behaviour" do
      EnumType.define(Grephql.Test.StatusEnum, ["ACTIVE", "INACTIVE"])

      assert {:ok, :active} = Grephql.Test.StatusEnum.cast("ACTIVE")
      assert {:ok, "INACTIVE"} = Grephql.Test.StatusEnum.dump(:inactive)
      assert {:ok, :active} = Grephql.Test.StatusEnum.load("ACTIVE")
    end
  end
end
