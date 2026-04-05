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

        defgql :get_user, "query($login: String!) { user(login: $login) { name } }"
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
  alias Grephql.Schema.Loader

  @use_config_keys [:endpoint, :req_options]

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    source = Keyword.fetch!(opts, :source)
    scalars = Keyword.get(opts, :scalars, %{})
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

    quote do
      import Grephql.Macros

      unquote(external_resource_ast)

      @grephql_otp_app unquote(otp_app)
      @grephql_scalars unquote(Macro.escape(scalars))
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

  Takes a `%Grephql.Query{}` struct (produced by `defgql` or `~GQL`),
  a map of variables, and optional keyword options.

  Options override runtime config which overrides compile-time defaults.
  """
  @spec execute(Query.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(query, variables \\ %{}, opts \\ [])

  def execute(%Query{} = _query, _variables, _opts) do
    {:error, :not_implemented}
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
