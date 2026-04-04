defmodule Grephql.ResponseDecoderTest do
  use ExUnit.Case, async: true

  alias Grephql.ResponseDecoder
  alias Grephql.Test.Response

  describe "decode!/2 with scalar fields" do
    test "decodes string fields" do
      json = %{"name" => "Alice", "email" => "a@b.com"}
      result = ResponseDecoder.decode!(Response.ScalarUser, json)

      assert %Response.ScalarUser{} = result
      assert result.name == "Alice"
      assert result.email == "a@b.com"
    end

    test "decodes integer and float fields" do
      json = %{"age" => 30, "score" => 4.5}
      result = ResponseDecoder.decode!(Response.NumericFields, json)

      assert result.age == 30
      assert result.score == 4.5
    end

    test "decodes boolean fields" do
      json = %{"active" => true}
      result = ResponseDecoder.decode!(Response.BooleanField, json)

      assert result.active == true
    end

    test "nullable field defaults to nil when absent" do
      json = %{"name" => "Alice"}
      result = ResponseDecoder.decode!(Response.ScalarUser, json)

      assert result.name == "Alice"
      assert result.email == nil
    end

    test "nullable field accepts null value" do
      json = %{"name" => "Alice", "email" => nil}
      result = ResponseDecoder.decode!(Response.ScalarUser, json)

      assert result.email == nil
    end
  end

  describe "decode!/2 with nested objects" do
    test "decodes embeds_one" do
      json = %{"name" => "Alice", "profile" => %{"bio" => "Hello"}}
      result = ResponseDecoder.decode!(Response.UserWithProfile, json)

      assert %Response.Profile{} = result.profile
      assert result.profile.bio == "Hello"
    end

    test "decodes embeds_many" do
      json = %{"name" => "Alice", "posts" => [%{"title" => "Post 1"}, %{"title" => "Post 2"}]}
      result = ResponseDecoder.decode!(Response.UserWithPosts, json)

      assert length(result.posts) == 2
      assert [%Response.Post{title: "Post 1"}, %Response.Post{title: "Post 2"}] = result.posts
    end

    test "decodes deeply nested objects" do
      json = %{
        "name" => "Alice",
        "posts" => [
          %{"title" => "Post 1", "author" => %{"name" => "Bob"}}
        ]
      }

      result = ResponseDecoder.decode!(Response.UserWithDeepPosts, json)

      assert hd(result.posts).author.name == "Bob"
    end

    test "absent embed defaults to nil for embeds_one" do
      json = %{"name" => "Alice"}
      result = ResponseDecoder.decode!(Response.UserWithProfile, json)

      assert result.profile == nil
    end

    test "absent embed defaults to empty list for embeds_many" do
      json = %{"name" => "Alice"}
      result = ResponseDecoder.decode!(Response.UserWithPosts, json)

      assert result.posts == []
    end
  end

  describe "decode!/2 with custom Ecto types" do
    test "decodes enum field via cast/1" do
      json = %{"name" => "Alice", "role" => "ADMIN"}
      result = ResponseDecoder.decode!(Response.UserWithRole, json)

      assert result.role == :admin
    end

    test "decodes DateTime field via cast/1" do
      json = %{"name" => "Event", "created_at" => "2024-01-15T10:30:00Z"}
      result = ResponseDecoder.decode!(Response.WithDateTime, json)

      assert %DateTime{} = result.created_at
      assert result.created_at.year == 2024
      assert result.created_at.month == 1
      assert result.created_at.day == 15
    end
  end

  describe "decode/2" do
    test "returns {:ok, struct} on success" do
      json = %{"name" => "Alice", "email" => "a@b.com"}

      assert {:ok, %Response.ScalarUser{name: "Alice"}} =
               ResponseDecoder.decode(Response.ScalarUser, json)
    end

    test "returns {:error, reason} on failure" do
      assert {:error, _reason} = ResponseDecoder.decode(NonExistentModule, %{})
    end
  end

  describe "decode!/2 with unknown keys" do
    test "ignores extra keys in JSON" do
      json = %{"name" => "Alice", "email" => "a@b.com", "unknown_field" => "ignored"}
      result = ResponseDecoder.decode!(Response.ScalarUser, json)

      assert result.name == "Alice"
      assert result.email == "a@b.com"
    end
  end
end
