defmodule TypedGqlJasonErrorTest do
  # Not async: :json_library is global config that every other test reads through
  # TypedGql.JSON. Sync modules run alone, after all async ones have finished.
  use ExUnit.Case, async: false

  defmodule JasonErrorClient do
    use TypedGql,
      otp_app: :typed_gql,
      source: "support/schemas/minimal.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [plug: {Req.Test, TypedGqlJasonErrorTest.JasonErrorClient}]

    defgql(:get_user, "query { user(id: \"1\") { name } }")
  end

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

  test "an exception-shaped decode error is returned unwrapped" do
    Req.Test.stub(JasonErrorClient, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(200, "not json at all")
    end)

    assert {:error, %Jason.DecodeError{}} = JasonErrorClient.get_user()
  end
end
