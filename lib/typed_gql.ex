defmodule TypedGql do
  @moduledoc """
  Compile-time GraphQL client for Elixir.

  Validates GraphQL operations at compile time and generates typed
  Ecto embedded schemas for responses.

  ## Usage

      defmodule MyApp.GitHub do
        use TypedGql,
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
    * `:generation_plugins` — `TypedGql.Generation.Plugin` modules that hook into
      response-type generation. TypedGql's built-in plugins (e.g. `@include`/`@skip`
      handling) always run first; these are appended after them (default: `[]`)
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

  alias TypedGql.Query
  alias TypedGql.ResponseDecoder
  alias TypedGql.Result
  alias TypedGql.Schema.Loader

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

    # generation_plugins are module reference AST too; pass through unescaped so
    # the {:__aliases__, ...} nodes resolve in the caller's compile context.
    generation_plugins_ast = Keyword.get(opts, :generation_plugins, [])

    quote do
      import TypedGql.Macros

      unquote(external_resource_ast)

      Module.register_attribute(__MODULE__, :typed_gql_fragments, accumulate: true)

      @typed_gql_otp_app unquote(otp_app)
      @typed_gql_scalars unquote(scalars_ast)
      @typed_gql_generation_plugins unquote(generation_plugins_ast)
      @typed_gql_use_config unquote(use_config)
      @typed_gql_schema TypedGql.__load_schema__(unquote(source), __ENV__.file)

      @doc false
      @spec __typed_gql_config__() :: {atom(), keyword()}
      def __typed_gql_config__, do: {@typed_gql_otp_app, @typed_gql_use_config}

      @doc """
      Customizes the `Req.Request` before it is sent.

      Override this callback to attach Req response steps, add headers,
      or apply any other request-level configuration.

      ## Example

          def prepare_req(req) do
            Req.Request.append_response_steps(req,
              my_step: fn {req, resp} ->
                {req, TypedGql.Result.put_resp_assign(resp, :extensions, resp.body["extensions"])}
              end
            )
          end

      ## Accessing the operation in request steps

      The full `%TypedGql.Query{}` being executed is stashed under
      `request.private[:typed_gql_query]`. Request steps (including those you
      attach here) can read it to inspect operation metadata such as
      `function_name`, `operation_name`, or `client_module`:

          def prepare_req(req) do
            Req.Request.append_request_steps(req,
              log_operation: fn req ->
                %TypedGql.Query{function_name: name} = req.private[:typed_gql_query]
                Logger.metadata(gql_operation: name)
                req
              end
            )
          end

      `TypedGql.OperationInfo` is a built-in step that uses this.
      """
      @spec prepare_req(Req.Request.t()) :: Req.Request.t()
      def prepare_req(req), do: req

      defoverridable prepare_req: 1
    end
  end

  @doc false
  @spec __load_schema__(String.t(), String.t()) :: TypedGql.Schema.t()
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

  Takes a `%TypedGql.Query{}` struct (produced by `defgql`/`defgqlp`),
  a variables struct (built by `Variables.build/1`), and optional keyword options.

  Options override runtime config which overrides compile-time defaults.
  """
  @spec execute(Query.t(), struct() | map(), keyword()) ::
          {:ok, Result.t()} | {:error, Req.Response.t() | Exception.t()}
  def execute(query, variables \\ %{}, opts \\ [])

  def execute(%Query{} = query, variables, opts) do
    variables_json = dump_variables(variables)

    body = %{query: query.document, variables: variables_json}

    body =
      if query.operation_name, do: Map.put(body, :operationName, query.operation_name), else: body

    request =
      query.client_module
      |> build_request(opts, json: body)
      # stash the full query so request steps (e.g. TypedGql.OperationInfo)
      # can read operation metadata off request.private
      |> Req.Request.put_private(:typed_gql_query, query)

    case Req.post(request) do
      {:ok, %{status: status} = response} when status >= 200 and status <= 299 ->
        decode_response(response, query.result_module)

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

  defp decode_response(%Req.Response{body: body} = response, result_module)
       when is_map(body) do
    data =
      case Map.get(body, "data") do
        data when is_map(data) -> ResponseDecoder.decode!(result_module, data)
        _nil_or_absent -> nil
      end

    errors =
      body
      |> Map.get("errors", [])
      |> Enum.map(&TypedGql.Error.from_json/1)

    assigns = Result.assigns_from_response(response)

    {:ok, %Result{data: data, errors: errors, assigns: assigns}}
  end

  defp decode_response(%Req.Response{body: body} = response, result_module)
       when is_binary(body) do
    case TypedGql.JSON.decode(body) do
      {:ok, decoded} ->
        decode_response(%{response | body: decoded}, result_module)

      {:error, reason} when is_exception(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, RuntimeError.exception(inspect(reason))}
    end
  end

  @spec build_request(module(), keyword(), keyword()) :: Req.Request.t()
  defp build_request(client_module, execute_opts, base_opts) do
    {otp_app, use_config} = client_module.__typed_gql_config__()
    runtime_config = Application.get_env(otp_app, client_module, [])

    {use_req_opts, use_rest} = Keyword.pop(use_config, :req_options, [])
    {runtime_req_opts, runtime_rest} = Keyword.pop(runtime_config, :req_options, [])
    {exec_req_opts, exec_rest} = Keyword.pop(execute_opts, :req_options, [])

    config =
      [endpoint: nil]
      |> Keyword.merge(use_rest)
      |> Keyword.merge(runtime_rest)
      |> Keyword.merge(exec_rest)

    endpoint =
      config[:endpoint] ||
        raise ArgumentError, "TypedGql: :endpoint is required but was not configured"

    [use_req_opts, runtime_req_opts, exec_req_opts]
    |> Enum.reduce(Req.new([url: endpoint] ++ base_opts), &Req.merge(&2, &1))
    |> client_module.prepare_req()
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
