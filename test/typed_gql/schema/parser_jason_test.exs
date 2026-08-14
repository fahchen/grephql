defmodule TypedGql.Schema.ParserJasonTest do
  # Not async: :json_library is global config that every other test reads through
  # TypedGql.JSON. Sync modules run alone, after all async ones have finished.
  use ExUnit.Case, async: false

  alias TypedGql.Schema.Parser

  setup do
    previous = Application.get_env(:typed_gql, :json_library)
    Application.put_env(:typed_gql, :json_library, Jason)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:typed_gql, :json_library)
        library -> Application.put_env(:typed_gql, :json_library, library)
      end
    end)
  end

  test "an exception-shaped decode error is rendered via Exception.message/1" do
    assert {:error, decode_error} = Jason.decode("not json")

    assert Parser.parse("not json") ==
             {:error, "JSON decode error: " <> Exception.message(decode_error)}
  end
end
