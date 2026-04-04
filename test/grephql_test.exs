defmodule GrephqlTest do
  use ExUnit.Case
  doctest Grephql

  test "greets the world" do
    assert Grephql.hello() == :world
  end
end
