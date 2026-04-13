defmodule Grephql.Types.TypenameTest do
  use ExUnit.Case, async: true

  alias Grephql.Types.Typename

  describe "cast/1" do
    test "converts string to snake_cased atom" do
      assert {:ok, :user} = Typename.cast("User")
      assert {:ok, :search_result} = Typename.cast("SearchResult")
    end

    test "passes through atom" do
      assert {:ok, :user} = Typename.cast(:user)
    end

    test "casts nil" do
      assert {:ok, nil} = Typename.cast(nil)
    end

    test "rejects other types" do
      assert :error = Typename.cast(123)
    end
  end

  describe "load/1" do
    test "converts string to snake_cased atom" do
      assert {:ok, :user} = Typename.load("User")
      assert {:ok, :post} = Typename.load("Post")
      assert {:ok, :search_result} = Typename.load("SearchResult")
    end

    test "loads nil" do
      assert {:ok, nil} = Typename.load(nil)
    end

    test "rejects non-string" do
      assert :error = Typename.load(123)
    end
  end

  describe "dump/1" do
    test "converts atom to string" do
      assert {:ok, "user"} = Typename.dump(:user)
      assert {:ok, "search_result"} = Typename.dump(:search_result)
    end

    test "passes through string" do
      assert {:ok, "User"} = Typename.dump("User")
    end

    test "dumps nil" do
      assert {:ok, nil} = Typename.dump(nil)
    end

    test "rejects other types" do
      assert :error = Typename.dump(123)
    end
  end

  describe "type/0" do
    test "returns :string" do
      assert :string = Typename.type()
    end
  end
end
