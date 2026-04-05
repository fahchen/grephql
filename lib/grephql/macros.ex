defmodule Grephql.Macros do
  @moduledoc false

  @doc """
  Compiles a GraphQL query string into a `%Grephql.Query{}` struct.

  Unlike `defgql`, this does not generate a function — it returns
  the compiled query struct for manual use. The operation must be named,
  as the name is used to derive the type module namespace.

  Supports string interpolation (lowercase sigil).

  ## Examples

      @query ~g"query GetUser($id: ID!) { user(id: $id) { name } }"

      # With interpolation (module attributes only):
      @user_fields "name email"
      @query ~g"query GetUser($id: ID!) { user(id: $id) { \#{@user_fields} } }"
  """
  defmacro sigil_g(query_string, _modifiers) do
    quote bind_quoted: [query_str: query_string] do
      Grephql.Macros.__compile_sigil__(
        query_str,
        @grephql_schema,
        __MODULE__,
        @grephql_scalars,
        __ENV__
      )
    end
  end

  # Dialyzer cannot trace callers because this is only invoked inside
  # `quote` blocks at macro expansion time, not at runtime.
  @dialyzer [{:no_return, __compile_sigil__: 5}, {:no_contracts, __compile_sigil__: 5}]

  @doc false
  @spec __compile_sigil__(String.t(), Grephql.Schema.t(), module(), map(), Macro.Env.t()) ::
          Grephql.Query.t()
  def __compile_sigil__(query_str, schema, client_module, scalar_types, caller_env) do
    document = parse_sigil!(query_str)
    function_name = derive_function_name!(document)

    Grephql.Compiler.compile_document!(document, query_str, schema,
      client_module: client_module,
      function_name: function_name,
      scalar_types: scalar_types,
      caller_env: caller_env
    )
  end

  defp parse_sigil!(query_str) do
    case Grephql.Parser.parse(query_str) do
      {:ok, document} -> document
      {:error, reason} -> raise CompileError, description: "GraphQL parse error: #{reason}"
    end
  end

  defp derive_function_name!(document) do
    operation =
      Enum.find(document.definitions, &match?(%Grephql.Language.OperationDefinition{}, &1))

    unless operation && operation.name do
      raise CompileError,
        description: "~g sigil requires a named operation (e.g. query GetUser { ... })"
    end

    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    operation.name |> Macro.underscore() |> String.to_atom()
  end

  @doc false
  @spec __execute_with_variables__(Grephql.Query.t(), map(), keyword()) ::
          {:ok, Grephql.Result.t()} | {:error, Ecto.Changeset.t() | Req.Response.t()}
  def __execute_with_variables__(%Grephql.Query{} = query, variables, opts) do
    with {:ok, struct} <- query.variables_module.build(variables) do
      Grephql.execute(query, struct, opts)
    end
  end

  @doc """
  Defines a public GraphQL query function.

  At compile time, parses and validates the query, generates typed
  response schemas, and defines a function that calls `Grephql.execute/3`.

  ## Examples

      defgql :get_user, "query($id: ID!) { user(id: $id) { name } }"
      # Generates: def get_user(variables, opts \\\\ [])

      defgql :current_user, "query { currentUser { name email } }"
      # Generates: def current_user(opts \\\\ [])
  """
  defmacro defgql(name, query_string) do
    define_query_function(:def, name, query_string)
  end

  @doc """
  Defines a private GraphQL query function.

  Same as `defgql/2` but generates a `defp` instead of `def`.
  """
  defmacro defgqlp(name, query_string) do
    define_query_function(:defp, name, query_string)
  end

  defp define_query_function(kind, func_name, query_str)
       when is_atom(func_name) and is_binary(query_str) do
    function_ast = build_function_ast(kind, func_name)

    # @grephql_schema and @grephql_scalars are module attributes
    # available only in the caller's compile context (inside quote)
    quote bind_quoted: [func_name: func_name, query_str: query_str],
          unquote: true do
      @grephql_query Grephql.Compiler.compile!(
                       query_str,
                       @grephql_schema,
                       client_module: __MODULE__,
                       function_name: func_name,
                       scalar_types: @grephql_scalars,
                       caller_env: __ENV__
                     )

      unquote(function_ast)
    end
  end

  defp build_function_ast(kind, func_name) do
    quote do
      if @grephql_query.has_variables? do
        Grephql.Macros.__define_spec_with_vars__(
          unquote(func_name),
          @grephql_query.result_module,
          @grephql_query.variables_module
        )

        unquote(func_with_variables_ast(kind, func_name))
      else
        Grephql.Macros.__define_spec_without_vars__(
          unquote(func_name),
          @grephql_query.result_module
        )

        unquote(func_without_variables_ast(kind, func_name))
      end
    end
  end

  @doc false
  defmacro __define_spec_with_vars__(name, result_module, variables_module) do
    quote bind_quoted: [
            name: name,
            result_module: result_module,
            variables_module: variables_module
          ] do
      @spec unquote(name)(unquote(variables_module).params(), keyword()) ::
              {:ok, Grephql.Result.t(unquote(result_module))}
              | {:error, Ecto.Changeset.t()}
              | {:error, Req.Response.t()}
    end
  end

  @doc false
  defmacro __define_spec_without_vars__(name, result_module) do
    quote bind_quoted: [name: name, result_module: result_module] do
      @spec unquote(name)(keyword()) ::
              {:ok, Grephql.Result.t(unquote(result_module))}
              | {:error, Req.Response.t()}
    end
  end

  defp func_with_variables_ast(:def, name) do
    quote do
      def unquote(name)(variables, opts \\ []) do
        Grephql.Macros.__execute_with_variables__(@grephql_query, variables, opts)
      end
    end
  end

  defp func_with_variables_ast(:defp, name) do
    quote do
      defp unquote(name)(variables, opts \\ []) do
        Grephql.Macros.__execute_with_variables__(@grephql_query, variables, opts)
      end
    end
  end

  defp func_without_variables_ast(:def, name) do
    quote do
      def unquote(name)(opts \\ []) do
        Grephql.execute(@grephql_query, %{}, opts)
      end
    end
  end

  defp func_without_variables_ast(:defp, name) do
    quote do
      defp unquote(name)(opts \\ []) do
        Grephql.execute(@grephql_query, %{}, opts)
      end
    end
  end
end
