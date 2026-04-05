defmodule Mix.Tasks.Grephql.DownloadSchemaTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Grephql.DownloadSchema

  @moduletag :tmp_dir

  @valid_response %{
    "data" => %{
      "__schema" => %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "types" => [],
        "directives" => []
      }
    }
  }

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)
    on_exit(fn -> Mix.shell(previous_shell) end)
    :ok
  end

  setup {Req.Test, :verify_on_exit!}

  describe "run/2" do
    test "downloads and saves schema", %{tmp_dir: tmp_dir} do
      output = Path.join(tmp_dir, "schema.json")

      Req.Test.expect(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert is_binary(request["query"])
        assert request["query"] =~ "IntrospectionQuery"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(@valid_response))
      end)

      DownloadSchema.run(
        ["--endpoint", "https://api.example.com/graphql", "--output", output],
        req_options()
      )

      assert File.exists?(output)
      saved = output |> File.read!() |> Jason.decode!()
      assert get_in(saved, ["data", "__schema", "queryType", "name"]) == "Query"
    end

    test "passes headers to request", %{tmp_dir: tmp_dir} do
      output = Path.join(tmp_dir, "schema.json")

      Req.Test.expect(__MODULE__, fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        assert auth == ["Bearer token123"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(@valid_response))
      end)

      DownloadSchema.run(
        [
          "--endpoint",
          "https://api.example.com/graphql",
          "--output",
          output,
          "--header",
          "Authorization: Bearer token123"
        ],
        req_options()
      )

      assert File.exists?(output)
    end

    test "creates output directory if it does not exist", %{tmp_dir: tmp_dir} do
      output = Path.join([tmp_dir, "nested", "dir", "schema.json"])
      expect_success()

      DownloadSchema.run(
        ["--endpoint", "https://api.example.com/graphql", "--output", output],
        req_options()
      )

      assert File.exists?(output)
    end

    test "raises on missing --endpoint" do
      assert_raise Mix.Error, ~r/--endpoint is required/, fn ->
        DownloadSchema.run(["--output", "schema.json"], req_options())
      end
    end

    test "raises on missing --output" do
      assert_raise Mix.Error, ~r/--output is required/, fn ->
        DownloadSchema.run(
          ["--endpoint", "https://example.com"],
          req_options()
        )
      end
    end

    test "raises on non-2xx response", %{tmp_dir: tmp_dir} do
      output = Path.join(tmp_dir, "schema.json")

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"error" => "Unauthorized"}))
      end)

      assert_raise Mix.Error, ~r/HTTP 401/, fn ->
        DownloadSchema.run(
          ["--endpoint", "https://api.example.com/graphql", "--output", output],
          req_options()
        )
      end
    end

    test "raises on invalid introspection response", %{tmp_dir: tmp_dir} do
      output = Path.join(tmp_dir, "schema.json")

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => %{"something" => "else"}}))
      end)

      assert_raise Mix.Error, ~r/missing __schema/, fn ->
        DownloadSchema.run(
          ["--endpoint", "https://api.example.com/graphql", "--output", output],
          req_options()
        )
      end
    end

    test "raises on transport error", %{tmp_dir: tmp_dir} do
      output = Path.join(tmp_dir, "schema.json")

      assert_raise Mix.Error, ~r/Request failed: connection refused/, fn ->
        DownloadSchema.run(
          ["--endpoint", "https://api.example.com/graphql", "--output", output],
          retry: false,
          adapter: fn req ->
            {req, %Req.TransportError{reason: :econnrefused}}
          end
        )
      end
    end

    test "raises on invalid header format" do
      assert_raise Mix.Error, ~r/Invalid header format/, fn ->
        DownloadSchema.run(
          [
            "--endpoint",
            "https://example.com",
            "--output",
            "s.json",
            "--header",
            "no-colon-here"
          ],
          req_options()
        )
      end
    end
  end

  defp req_options, do: [plug: {Req.Test, __MODULE__}]

  defp expect_success do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(@valid_response))
    end)
  end
end
