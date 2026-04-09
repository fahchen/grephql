defmodule TypedStructor.Plugins.AccessTest do
  use ExUnit.Case, async: true

  alias Grephql.Test.Response.ScalarUser
  alias Grephql.Test.Response.UserWithProfile

  describe "fetch/2" do
    test "returns {:ok, value} for existing keys" do
      user = %ScalarUser{name: "Alice", email: "alice@example.com"}

      assert {:ok, "Alice"} = Access.fetch(user, :name)
      assert {:ok, "alice@example.com"} = Access.fetch(user, :email)
    end

    test "returns {:ok, nil} for existing keys with nil value" do
      user = %ScalarUser{name: "Alice", email: nil}

      assert {:ok, nil} = Access.fetch(user, :email)
    end

    test "returns :error for non-existing keys" do
      user = %ScalarUser{name: "Alice", email: nil}

      assert :error = Access.fetch(user, :nonexistent)
    end

    test "works with bracket syntax" do
      user = %ScalarUser{name: "Alice", email: "alice@example.com"}

      assert user[:name] == "Alice"
      assert user[:email] == "alice@example.com"
    end

    test "returns nil for non-existing keys with bracket syntax" do
      user = %ScalarUser{name: "Alice", email: nil}

      assert user[:nonexistent] == nil
    end
  end

  describe "get_and_update/3" do
    test "gets and updates an existing key" do
      user = %ScalarUser{name: "Alice", email: nil}

      assert {"Alice", %ScalarUser{name: "ALICE", email: nil}} =
               Access.get_and_update(user, :name, fn current ->
                 {current, String.upcase(current)}
               end)
    end

    test "works with get_and_update_in/3" do
      user = %ScalarUser{name: "Alice", email: nil}

      assert {"Alice", %ScalarUser{name: "Bob", email: nil}} =
               get_and_update_in(user, [:name], fn current ->
                 {current, "Bob"}
               end)
    end
  end

  describe "pop/2" do
    test "raises on pop" do
      user = %ScalarUser{name: "Alice", email: nil}

      assert_raise UndefinedFunctionError, ~r/structs do not allow removing keys/, fn ->
        Access.pop(user, :name)
      end
    end
  end

  describe "nested access" do
    test "works with get_in/2 for nested schemas" do
      user = %UserWithProfile{
        name: "Alice",
        profile: %Grephql.Test.Response.Profile{bio: "hello"}
      }

      assert get_in(user, [:profile, :bio]) == "hello"
    end
  end
end
