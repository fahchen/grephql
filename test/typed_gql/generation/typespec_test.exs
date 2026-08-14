defmodule TypedGql.Generation.TypespecTest do
  use ExUnit.Case, async: true

  # Asserts the *generated* @type, not just the generation IR. This is only
  # possible because TypedGql.Test.TypespecFixture is a compiled .ex client
  # (test/support/typespec_fixture.ex): Code.Typespec.fetch_types/1 reads from
  # the .beam, which exists for compile-time-generated modules but not for the
  # in-memory modules the other generation tests build at runtime.
  test "@include makes a non-null field nullable in the generated @type" do
    rendered = generated_t(TypedGql.Test.TypespecFixture.GetUser.Result.User)

    # id is ID! but carries @include(if: $show) -> nullable in the generated type.
    assert rendered =~ "id: String.t() | nil"
    # name is non-null and undirected -> stays non-null.
    assert rendered =~ "name: String.t()"
    refute rendered =~ "name: String.t() | nil"
  end

  test "a [T!]! object list keeps the embeds_many type" do
    rendered = generated_t(TypedGql.Test.TypespecFixture.GetUser.Result.User)

    # Ecto.Schema.embeds_many(t) expands to [t], so [Post!]! keeps its embed.
    assert rendered =~
             "posts: Ecto.Schema.embeds_many(TypedGql.Test.TypespecFixture.GetUser.Result.User.Posts.t())"
  end

  test "a nullable object list is nullable in both the list and its elements" do
    rendered = generated_t(TypedGql.Test.TypespecFixture.ListDrafts.Result)

    # drafts is [Post] — the whole list and every element may be null.
    assert rendered =~
             "drafts: [TypedGql.Test.TypespecFixture.ListDrafts.Result.Drafts.t() | nil] | nil"
  end

  test "a list of an abstract type carries element nullability too" do
    rendered = generated_t(TypedGql.Test.TypespecFixture.ListNodes.Result)

    # nodes is [Node]! — the list itself cannot be null, its elements can.
    assert rendered =~
             "nodes: [TypedGql.Test.TypespecFixture.ListNodes.Result.Nodes.Union.t() | nil]"
  end

  defp generated_t(module) do
    {:ok, types} = Code.Typespec.fetch_types(module)

    types
    |> Enum.map(fn {_kind, type} -> Macro.to_string(Code.Typespec.type_to_quoted(type)) end)
    |> Enum.find(&String.starts_with?(&1, "t() ::"))
  end
end
