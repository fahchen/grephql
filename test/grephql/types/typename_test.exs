defmodule Grephql.Types.TypenameTest do
  use ExUnit.Case, async: true

  alias Grephql.Types.Typename

  @params Typename.init(values: ["User", "Post", "SearchResult"])

  describe "init/1" do
    test "builds string-to-atom mapping" do
      assert @params == %{
               "User" => :user,
               "Post" => :post,
               "SearchResult" => :search_result
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

    test "passes through atom" do
      assert {:ok, :user} = Typename.cast(:user, @params)
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
    test "converts atom to string" do
      assert {:ok, "user"} = Typename.dump(:user, nil, @params)
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
