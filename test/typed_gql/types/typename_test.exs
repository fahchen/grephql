defmodule TypedGql.Types.TypenameTest do
  use ExUnit.Case, async: true

  alias TypedGql.Types.Typename

  @params Typename.init(values: ["User", "Post", "SearchResult"])

  describe "init/1" do
    test "builds both directions of the mapping" do
      assert @params == %{
               string_to_atom: %{
                 "User" => :user,
                 "Post" => :post,
                 "SearchResult" => :search_result
               },
               atom_to_string: %{
                 user: "User",
                 post: "Post",
                 search_result: "SearchResult"
               }
             }
    end
  end

  describe "cast/2" do
    test "converts known string to snake_cased atom" do
      assert {:ok, :user} = Typename.cast("User", @params)
      assert {:ok, :search_result} = Typename.cast("SearchResult", @params)
    end

    test "rejects unknown string" do
      assert :error = Typename.cast("Comment", @params)
    end

    test "passes through a declared atom" do
      assert {:ok, :user} = Typename.cast(:user, @params)
    end

    test "rejects an undeclared atom" do
      assert :error = Typename.cast(:comment, @params)
    end

    test "casts nil" do
      assert {:ok, nil} = Typename.cast(nil, @params)
    end

    test "rejects other types" do
      assert :error = Typename.cast(123, @params)
    end
  end

  describe "load/3" do
    test "converts known string to snake_cased atom" do
      assert {:ok, :user} = Typename.load("User", nil, @params)
      assert {:ok, :post} = Typename.load("Post", nil, @params)
    end

    test "rejects unknown string" do
      assert :error = Typename.load("Comment", nil, @params)
    end

    test "loads nil" do
      assert {:ok, nil} = Typename.load(nil, nil, @params)
    end

    test "rejects non-string" do
      assert :error = Typename.load(123, nil, @params)
    end
  end

  describe "dump/3" do
    test "converts atom back to its GraphQL type name" do
      assert {:ok, "User"} = Typename.dump(:user, nil, @params)
      assert {:ok, "SearchResult"} = Typename.dump(:search_result, nil, @params)
    end

    test "rejects an undeclared atom" do
      assert :error = Typename.dump(:comment, nil, @params)
    end

    test "round-trips through load/3" do
      assert {:ok, name} = Typename.dump(:search_result, nil, @params)
      assert {:ok, :search_result} = Typename.load(name, nil, @params)
    end

    test "passes through string" do
      assert {:ok, "User"} = Typename.dump("User", nil, @params)
    end

    test "dumps nil" do
      assert {:ok, nil} = Typename.dump(nil, nil, @params)
    end

    test "rejects other types" do
      assert :error = Typename.dump(123, nil, @params)
    end
  end

  describe "type/1" do
    test "returns :string" do
      assert :string = Typename.type(@params)
    end
  end

  describe "embed_as/2" do
    test "returns :dump" do
      assert :dump = Typename.embed_as(:json, @params)
    end
  end
end
