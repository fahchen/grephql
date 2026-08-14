defmodule TypedGql.Integration.EnumVariableInputFormsAndWireDumpContractTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: which input forms an enum variable accepts (wire
  # string, atom, lowercase string) and the exact string that reaches the
  # wire, plus the rejection of values outside the enum.
  use ExUnit.Case, async: true

  import TypedGql.Test.Helpers, only: [errors_on: 2]

  alias TypedGql.Result

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql"

    defgql(:update_user, """
    mutation UpdateRole($id: ID!, $input: UpdateUserInput!) {
      updateUser(id: $id, input: $input) { id role }
    }
    """)
  end

  setup {Req.Test, :verify_on_exit!}

  describe "dumped request" do
    test ~s(the wire string "ADMIN" dumps unchanged as "ADMIN") do
      request = capture_request("ADMIN")

      assert request["variables"]["input"]["role"] == "ADMIN"
    end

    test "the atom :admin is accepted and dumps as \"ADMIN\"" do
      request = capture_request(:admin)

      assert request["variables"]["input"]["role"] == "ADMIN"
    end

    test ~s(the lowercase string "admin" is accepted and normalizes to "ADMIN" on the wire) do
      request = capture_request("admin")

      assert request["variables"]["input"]["role"] == "ADMIN"
    end
  end

  # No Req.Test.expect is registered for these tests: verify_on_exit! with
  # zero expectations proves the invalid values never issued an HTTP request.
  describe "changeset validation" do
    test "a string outside the enum fails as a changeset error before any request" do
      assert {:error, %Ecto.Changeset{} = changeset} = call("SUPERADMIN")

      assert "is invalid" in errors_on(changeset.changes.input, :role)
    end

    test "an atom outside the enum fails as a changeset error before any request" do
      assert {:error, %Ecto.Changeset{} = changeset} = call(:superadmin)

      assert "is invalid" in errors_on(changeset.changes.input, :role)
    end
  end

  describe "loaded response" do
    test "the enum string \"GUEST\" in the response decodes to :guest" do
      result = fetch()

      assert result.data.update_user.role == :guest
    end
  end

  defp capture_request(role) do
    parent = self()

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = call(role)
    assert_received {:request, request}
    request
  end

  defp fetch do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{"updateUser" => %{"id" => "u1", "role" => "GUEST"}}
      })
    end)

    assert {:ok, %Result{} = result} = call("GUEST")
    result
  end

  defp call(role) do
    Client.update_user(
      %{id: "u1", input: %{role: role}},
      req_options: [plug: {Req.Test, Client}]
    )
  end
end
