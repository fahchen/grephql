defmodule Grephql.Types.UnionTest do
  use ExUnit.Case, async: true

  alias Grephql.Test.UnionTypes.Post
  alias Grephql.Test.UnionTypes.SearchUnion
  alias Grephql.Test.UnionTypes.User
  alias Grephql.Types.Union

  setup_all do
    Union.define(SearchUnion, %{
      "User" => User,
      "Post" => Post
    })

    :ok
  end

  describe "load/3" do
    test "loads User map by __typename" do
      map = %{"__typename" => "User", "name" => "Alice", "email" => "a@b.com"}

      assert {:ok, %User{__typename: :user}} =
               SearchUnion.load(map, nil, %{})
    end

    test "loads Post map by __typename" do
      map = %{"__typename" => "Post", "title" => "Hello"}

      assert {:ok, %Post{__typename: :post, title: "Hello"}} =
               SearchUnion.load(map, nil, %{})
    end

    test "returns nil for nil input" do
      assert {:ok, nil} = SearchUnion.load(nil, nil, %{})
    end

    test "returns error for missing __typename" do
      assert {:error, "missing __typename field"} =
               SearchUnion.load(%{"name" => "X"}, nil, %{})
    end

    test "returns error for unknown __typename" do
      assert {:error, "unknown __typename: \"Comment\""} =
               SearchUnion.load(%{"__typename" => "Comment"}, nil, %{})
    end
  end

  describe "cast/2" do
    test "casts map by __typename" do
      map = %{"__typename" => "User", "name" => "Bob"}

      assert {:ok, %User{__typename: :user, name: "Bob"}} =
               SearchUnion.cast(map, %{})
    end

    test "passes through existing struct" do
      struct = %User{name: "Alice"}
      assert {:ok, ^struct} = SearchUnion.cast(struct, %{})
    end

    test "casts nil" do
      assert {:ok, nil} = SearchUnion.cast(nil, %{})
    end
  end

  describe "dump/3" do
    test "dumps struct to map" do
      struct = %User{name: "Alice", email: "a@b.com"}
      assert {:ok, map} = SearchUnion.dump(struct, nil, %{})
      assert map.name == "Alice"
      assert map.email == "a@b.com"
    end

    test "dumps nil" do
      assert {:ok, nil} = SearchUnion.dump(nil, nil, %{})
    end
  end

  describe "embed_as/2" do
    test "returns :dump" do
      assert :dump == SearchUnion.embed_as(:json, %{})
    end
  end
end
