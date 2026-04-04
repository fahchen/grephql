defmodule Grephql.Types.DateTimeTest do
  use ExUnit.Case, async: true

  alias Grephql.Types.DateTime, as: DateTimeType

  describe "type/0" do
    test "returns :utc_datetime_usec" do
      assert DateTimeType.type() == :utc_datetime_usec
    end
  end

  describe "cast/1" do
    test "casts ISO 8601 string to DateTime" do
      assert {:ok, %DateTime{year: 2024, month: 1, day: 15}} =
               DateTimeType.cast("2024-01-15T10:30:00Z")
    end

    test "passes through DateTime struct" do
      dt = ~U[2024-01-15 10:30:00Z]
      assert {:ok, ^dt} = DateTimeType.cast(dt)
    end

    test "casts ISO 8601 string with offset" do
      assert {:ok, %DateTime{}} = DateTimeType.cast("2024-01-15T10:30:00+05:00")
    end

    test "rejects invalid string" do
      assert :error = DateTimeType.cast("not-a-date")
    end

    test "rejects non-string non-datetime" do
      assert :error = DateTimeType.cast(123)
    end
  end

  describe "dump/1" do
    test "dumps DateTime to ISO 8601 string" do
      dt = ~U[2024-01-15 10:30:00Z]
      assert {:ok, "2024-01-15T10:30:00Z"} = DateTimeType.dump(dt)
    end

    test "rejects non-datetime" do
      assert :error = DateTimeType.dump("2024-01-15T10:30:00Z")
    end
  end

  describe "load/1" do
    test "loads ISO 8601 string to DateTime" do
      assert {:ok, %DateTime{year: 2024, month: 1, day: 15}} =
               DateTimeType.load("2024-01-15T10:30:00Z")
    end

    test "passes through DateTime struct" do
      dt = ~U[2024-01-15 10:30:00Z]
      assert {:ok, ^dt} = DateTimeType.load(dt)
    end

    test "rejects invalid string" do
      assert :error = DateTimeType.load("not-a-date")
    end
  end
end
