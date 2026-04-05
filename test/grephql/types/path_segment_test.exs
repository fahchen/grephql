defmodule Grephql.Types.PathSegmentTest do
  use ExUnit.Case, async: true

  alias Grephql.Types.PathSegment

  describe "type/0" do
    test "returns :any" do
      assert PathSegment.type() == :any
    end
  end

  describe "cast/1" do
    test "casts string" do
      assert {:ok, "user"} = PathSegment.cast("user")
    end

    test "casts integer" do
      assert {:ok, 0} = PathSegment.cast(0)
    end

    test "rejects other types" do
      assert :error = PathSegment.cast(1.5)
      assert :error = PathSegment.cast(:atom)
      assert :error = PathSegment.cast(nil)
    end
  end

  describe "dump/1" do
    test "dumps string" do
      assert {:ok, "user"} = PathSegment.dump("user")
    end

    test "dumps integer" do
      assert {:ok, 2} = PathSegment.dump(2)
    end

    test "rejects other types" do
      assert :error = PathSegment.dump(:atom)
    end
  end

  describe "load/1" do
    test "loads string" do
      assert {:ok, "user"} = PathSegment.load("user")
    end

    test "loads integer" do
      assert {:ok, 3} = PathSegment.load(3)
    end

    test "rejects other types" do
      assert :error = PathSegment.load(nil)
    end
  end

  describe "embed_as/1" do
    test "returns :self" do
      assert PathSegment.embed_as(:json) == :self
    end
  end
end
