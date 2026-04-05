defmodule Grephql do
  @moduledoc """
  Compile-time GraphQL client for Elixir.

  Validates GraphQL operations at compile time and generates typed
  Ecto embedded schemas for responses.

  ## Usage

      defmodule MyApp.GitHub do
        use Grephql,
          otp_app: :my_app,
          source: "priv/schemas/github.json"

        defgql :get_user, ~GQL\"\"\"
          query($login: String!) {
            user(login: $login) {
              name
            }
          }
        \"\"\"
      end

  ## Options

    * `:otp_app` (required) — the OTP application for runtime config lookup
    * `:source` (required) — path to a schema JSON file (relative to the caller file), or an inline JSON string
    * `:scalars` — custom scalar type mappings (default: `%{}`)
    * `:endpoint` — default GraphQL endpoint URL
    * `:req_options` — default Req options passed directly to `Req.new/1` (keyword list).
      Supports all Req options including middleware/plugins. Common examples:

      - Headers: `req_options: [headers: [authorization: "Bearer token"]]`
      - Timeouts: `req_options: [receive_timeout: 30_000]`
      - Plug (for testing): `req_options: [plug: {Req.Test, MyApp.GitHub}]`

      You can also attach Req plugins via the `:req_options` key. Plugins are
      attached by passing the plugin's `attach/1` options:

          # In config/runtime.exs
          config :my_app, MyApp.GitHub,
            req_options: [auth: {:bearer, System.fetch_env!("GITHUB_TOKEN")}]

          # In test setup
          config :my_app, MyApp.GitHub,
            req_options: [plug: {Req.Test, MyApp.GitHub}]
  """

  alias Grephql.Query
  alias Grephql.ResponseDecoder
  alias Grephql.Result
  alias Grephql.Schema.Loader

  @use_config_keys [:endpoint, :req_options]

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    source = Keyword.fetch!(opts, :source)
    use_config = Keyword.take(opts, @use_config_keys)

    file_source? = is_binary(source) and not Loader.json_content?(source)

    if file_source? do
      absolute = Path.expand(source, Path.dirname(__CALLER__.file))

      unless File.exists?(absolute) do
        raise CompileError,
          description: "schema file not found: #{absolute} (resolved from #{source})"
      end
    end

    external_resource_ast =
      if file_source? do
        quote do
          @external_resource Path.expand(unquote(source), Path.dirname(__ENV__.file))
        end
      end

    # scalars from opts are already AST (may contain {:__aliases__, ...} nodes
    # for module references). Pass through without Macro.escape so they
    # evaluate correctly in the caller's compile context.
    scalars_ast = Keyword.get(opts, :scalars, Macro.escape(%{}))

    quote do
      import Grephql.Macros

      unquote(external_resource_ast)

      Module.register_attribute(__MODULE__, :grephql_fragments, accumulate: true)

      @grephql_otp_app unquote(otp_app)
      @grephql_scalars unquote(scalars_ast)
      @grephql_use_config unquote(use_config)
      @grephql_schema Grephql.__load_schema__(unquote(source), __ENV__.file)

      @doc false
      @spec __grephql_config__() :: {atom(), keyword()}
      def __grephql_config__, do: {@grephql_otp_app, @grephql_use_config}
    end
  end

  @doc false
  @spec __load_schema__(String.t(), String.t()) :: Grephql.Schema.t()
  def __load_schema__(source, caller_file) do
    resolved = resolve_source(source, caller_file)
    cache_key = schema_cache_key(resolved)

    case :persistent_term.get(cache_key, :not_cached) do
      :not_cached ->
        schema = Loader.load!(resolved)
        :persistent_term.put(cache_key, schema)
        schema

      schema ->
        schema
    end
  end

  @doc """
  Executes a compiled GraphQL query.

  Takes a `%Grephql.Query{}` struct (produced by `defgql`/`defgqlp`),
  a variables struct (built by `Variables.build/1`), and optional keyword options.

  Options override runtime config which overrides compile-time defaults.
  """
  @spec execute(Query.t(), struct() | map(), keyword()) ::
          {:ok, Result.t()} | {:error, Req.Response.t() | Exception.t()}
  def execute(query, variables \\ %{}, opts \\ [])

  def execute(%Query{} = query, variables, opts) do
    config = resolve_config(query.client_module, opts)

    endpoint =
      config[:endpoint] ||
        raise ArgumentError, "Grephql: :endpoint is required but was not configured"

    req_options = Keyword.get(config, :req_options, [])

    variables_json = dump_variables(variables)

    body = %{query: query.document, variables: variables_json}

    body =
      if query.operation_name, do: Map.put(body, :operationName, query.operation_name), else: body

    case [url: endpoint, json: body]
         |> Req.new()
         |> Req.merge(req_options)
         |> Req.post() do
      {:ok, %{status: status} = response} when status >= 200 and status <= 299 ->
        decode_response(response.body, query.result_module)

      {:ok, response} ->
        {:error, response}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp dump_variables(%{__struct__: _module} = variables) do
    Ecto.embedded_dump(variables, :json)
  end

  defp dump_variables(variables) when is_map(variables), do: variables

  defp decode_response(body, result_module) when is_map(body) do
    data =
      case Map.get(body, "data") do
        data when is_map(data) -> ResponseDecoder.decode!(result_module, data)
        _nil_or_absent -> nil
      end

    errors =
      body
      |> Map.get("errors", [])
      |> Enum.map(&Grephql.Error.from_json/1)

    {:ok, %Result{data: data, errors: errors}}
  end

  defp decode_response(body, result_module) when is_binary(body) do
    body |> Jason.decode!() |> decode_response(result_module)
  end

  @doc false
  @spec resolve_config(module(), keyword()) :: keyword()
  def resolve_config(client_module, execute_opts) do
    {otp_app, use_config} = client_module.__grephql_config__()
    runtime_config = Application.get_env(otp_app, client_module, [])

    defaults()
    |> Keyword.merge(use_config)
    |> Keyword.merge(runtime_config)
    |> Keyword.merge(execute_opts)
  end

  defp defaults do
    [endpoint: nil, req_options: []]
  end

  defp resolve_source(source, caller_file) do
    if Loader.json_content?(source) do
      source
    else
      Path.expand(source, Path.dirname(caller_file))
    end
  end

  defp schema_cache_key(resolved_source) do
    if Loader.json_content?(resolved_source) do
      {__MODULE__, :schema, :erlang.phash2(resolved_source)}
    else
      {__MODULE__, :schema, resolved_source}
    end
  end
end
