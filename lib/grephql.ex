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
    * `:source` (required) — path to a schema JSON file, or an inline JSON string
    * `:scalars` — custom scalar type mappings (default: `%{}`)
    * `:endpoint` — default GraphQL endpoint URL
    * `:headers` — default HTTP headers (keyword list)
    * `:req_options` — default Req options, supports middleware/plugins (keyword list)
  """

  alias Grephql.Query
  alias Grephql.Schema.Loader

  @use_config_keys [:endpoint, :headers, :req_options]

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    source = Keyword.fetch!(opts, :source)
    scalars = Keyword.get(opts, :scalars, %{})
    use_config = Keyword.take(opts, @use_config_keys)

    file_source? = is_binary(source) and not Loader.json_content?(source)

    external_resource_ast =
      if file_source? do
        quote do
          @external_resource Path.expand(unquote(source))
        end
      end

    quote do
      import Grephql.Macros

      unquote(external_resource_ast)

      @grephql_otp_app unquote(otp_app)
      @grephql_scalars unquote(Macro.escape(scalars))
      @grephql_use_config unquote(use_config)
      @grephql_schema Grephql.__load_schema__(unquote(source))

      @doc false
      @spec __grephql_config__() :: {atom(), keyword()}
      def __grephql_config__, do: {@grephql_otp_app, @grephql_use_config}
    end
  end

  @doc false
  @spec __load_schema__(String.t()) :: Grephql.Schema.t()
  def __load_schema__(source) do
    cache_key = schema_cache_key(source)

    case :persistent_term.get(cache_key, :not_cached) do
      :not_cached ->
        schema = Loader.load!(source)
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
    [endpoint: nil, headers: [], req_options: []]
  end

  defp schema_cache_key(source) do
    if Loader.json_content?(source) do
      {__MODULE__, :schema, :erlang.phash2(source)}
    else
      {__MODULE__, :schema, Path.expand(source)}
    end
  end
end
