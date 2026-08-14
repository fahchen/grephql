defmodule TypedGql.Types.UnionTest do
  use ExUnit.Case, async: true

  alias TypedGql.Test.UnionTypes.Address
  alias TypedGql.Test.UnionTypes.Post
  alias TypedGql.Test.UnionTypes.SearchUnion
  alias TypedGql.Test.UnionTypes.User
  alias TypedGql.Types.Union

  setup_all do
    Union.define(SearchUnion, %{"User" => User, "Post" => Post})

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
      assert :error = SearchUnion.load(%{"name" => "X"}, nil, %{})
    end

    test "returns error for unknown __typename" do
      assert :error = SearchUnion.load(%{"__typename" => "Comment"}, nil, %{})
    end

    test "loads a map whose __typename key is an atom, as Ecto's dumper emits" do
      assert {:ok, %User{__typename: :user, name: "Alice"}} =
               SearchUnion.load(%{__typename: "User", name: "Alice"}, nil, %{})
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

    test "rejects a struct that is not a union member" do
      assert :error = SearchUnion.cast(%Address{zip: "12345"}, %{})
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

    test "dumps through the variant's own field dumpers" do
      {:ok, user} =
        SearchUnion.load(
          %{"__typename" => "User", "role" => "ADMIN", "address" => %{"zip" => "12345"}},
          nil,
          %{}
        )

      assert {:ok, map} = SearchUnion.dump(user, nil, %{})
      assert map.__typename == "User"
      assert map.role == "ADMIN"
      assert map.address == %{zip: "12345"}
      assert {:ok, _json} = Jason.encode(map)
    end

    test "round-trips back to the loaded struct" do
      {:ok, user} =
        SearchUnion.load(%{"__typename" => "User", "name" => "Alice"}, nil, %{})

      assert {:ok, dumped} = SearchUnion.dump(user, nil, %{})
      assert {:ok, ^user} = SearchUnion.load(dumped, nil, %{})
    end

    test "rejects a struct that is not a union member" do
      assert :error = SearchUnion.dump(%Address{zip: "12345"}, nil, %{})
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
