defmodule TypedGql.Integration.QueryInterpolatingFragmentStringsViaModuleAttributesTest do
  @moduledoc """
  Documents built by interpolating module attributes into the query source:

  - an interpolated field list becomes exactly those fields on the Result struct
  - fields reached through an interpolated fragment definition land there too
  - the sent document carries every field of the interpolated list
  - the sent document carries the interpolated fragment definition exactly once
  - both operations decode with their custom types
  """
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug:
          {Req.Test,
           TypedGql.Integration.QueryInterpolatingFragmentStringsViaModuleAttributesTest.Client}
      ]

    @user_fields "id name role"
    @core_fragment """
    fragment Core on User {
      email
      createdAt
    }
    """

    defgql(
      :field_list_user,
      "query FieldListUser($id: ID!) { user(id: $id) { #{@user_fields} } }"
    )

    defgql(:fragment_user, """
    query FragmentUser($id: ID!) {
      user(id: $id) {
        id
        ...Core
      }
    }
    #{@core_fragment}
    """)
  end

  describe "generated shape" do
    test "the interpolated field list becomes exactly those fields on the Result struct" do
      assert Client.FieldListUser.Result.User.__schema__(:fields) == [:id, :name, :role]
    end

    test "fields reached through the interpolated fragment land on the Result struct" do
      assert Enum.sort(Client.FragmentUser.Result.User.__schema__(:fields)) ==
               [:created_at, :email, :id]
    end
  end

  describe "dumped request" do
    test "the sent document carries every field of the interpolated list" do
      request = capture_request(&call_field_list_user/0)

      assert request["operationName"] == "FieldListUser"
      assert request["query"] =~ "id\n    name\n    role"
    end

    test "the sent document carries the interpolated fragment definition exactly once" do
      request = capture_request(&call_fragment_user/0)

      assert request["operationName"] == "FragmentUser"
      assert [_only_definition] = :binary.matches(request["query"], "fragment Core on User")
      assert request["query"] =~ "...Core"
    end
  end

  describe "loaded response" do
    test "the field-list operation decodes into a typed struct with an enum atom" do
      result = fetch_field_list_user()

      assert %Client.FieldListUser.Result.User{id: "u1", name: "Alice", role: :admin} =
               result.data.user
    end

    test "fields reached through the fragment decode with their custom types" do
      result = fetch_fragment_user()

      assert %Client.FragmentUser.Result.User{
               id: "u1",
               email: "alice@example.com",
               created_at: ~U[2025-01-15 10:30:00Z]
             } = result.data.user
    end
  end

  defp capture_request(call) do
    parent = self()

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = call.()
    assert_received {:request, request}
    request
  end

  defp fetch_field_list_user do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{"user" => %{"id" => "u1", "name" => "Alice", "role" => "ADMIN"}}
      })
    end)

    assert {:ok, %Result{} = result} = call_field_list_user()
    result
  end

  defp fetch_fragment_user do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "user" => %{
            "id" => "u1",
            "email" => "alice@example.com",
            "createdAt" => "2025-01-15T10:30:00Z"
          }
        }
      })
    end)

    assert {:ok, %Result{} = result} = call_fragment_user()
    result
  end

  defp call_field_list_user do
    Client.field_list_user(%{id: "u1"})
  end

  defp call_fragment_user do
    Client.fragment_user(%{id: "u1"})
  end
end
