defmodule Mix.Tasks.Grephql.DownloadSchema do
  @moduledoc """
  Downloads a GraphQL schema via introspection and saves it as JSON.

  ## Usage

      mix grephql.download_schema --endpoint URL --output PATH [--header "Key: Value"]

  ## Options

    * `--endpoint` (required) — the GraphQL endpoint URL
    * `--output` (required) — file path to save the schema JSON
    * `--header` — HTTP header in `"Key: Value"` format (may be repeated)

  ## Examples

      mix grephql.download_schema \\
        --endpoint https://api.example.com/graphql \\
        --output priv/schemas/schema.json

      mix grephql.download_schema \\
        --endpoint https://api.example.com/graphql \\
        --output priv/schemas/schema.json \\
        --header "Authorization: Bearer token123"
  """

  use Mix.Task

  @shortdoc "Downloads a GraphQL schema via introspection"

  @introspection_query_path Path.expand(
                              Path.join([
                                __DIR__,
                                "..",
                                "..",
                                "..",
                                "priv",
                                "graphql",
                                "introspection.graphql"
                              ])
                            )
  @external_resource @introspection_query_path
  @introspection_query File.read!(@introspection_query_path)

  @switches [endpoint: :string, output: :string, header: :keep]
  @aliases [e: :endpoint, o: :output, h: :header]

  @impl Mix.Task
  def run(args), do: run(args, [])

  @doc false
  @spec run([String.t()], keyword()) :: :ok
  def run(args, req_options) do
    {opts, _unparsed} = OptionParser.parse!(args, switches: @switches, aliases: @aliases)

    endpoint = opts[:endpoint] || Mix.raise("--endpoint is required")
    output = opts[:output] || Mix.raise("--output is required")
    headers = parse_headers(opts)

    Mix.shell().info("Downloading schema from #{endpoint}...")

    Application.ensure_all_started(:req)

    body = %{query: @introspection_query}

    response =
      [url: endpoint, json: body, headers: headers]
      |> Req.new()
      |> Req.merge(req_options)
      |> Req.post!()

    case response.status do
      status when status >= 200 and status <= 299 ->
        validate_and_save!(response.body, output)

      _other ->
        Mix.raise("HTTP #{response.status}: #{inspect(response.body)}")
    end
  end

  defp parse_headers(opts) do
    opts
    |> Keyword.get_values(:header)
    |> Enum.map(fn header ->
      case String.split(header, ":", parts: 2) do
        [key, value] ->
          {String.trim(key), String.trim(value)}

        _invalid ->
          Mix.raise("Invalid header format: #{inspect(header)}. Expected \"Key: Value\"")
      end
    end)
  end

  defp validate_and_save!(body, output) when is_map(body) do
    json = Jason.encode!(body, pretty: true)

    case Grephql.Schema.Parser.parse(json) do
      {:ok, _schema} -> save!(output, json)
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp validate_and_save!(body, _output) do
    Mix.raise("Unexpected response body: #{inspect(body)}")
  end

  defp save!(output, json) do
    output |> Path.dirname() |> File.mkdir_p!()
    File.write!(output, json)
    Mix.shell().info("Schema saved to #{output}")
  end
end
