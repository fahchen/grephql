defmodule Grephql.Macros do
  @moduledoc false

  @doc """
  A sigil for writing GraphQL query strings that can be formatted by `mix format`.

  Returns the query as a plain string — use it with `defgql`/`defgqlp`.
  Does not support interpolation (uppercase sigil convention).

  To enable formatting, add `Grephql.Formatter` to your `.formatter.exs` plugins.

  ## Examples

      defgql :get_user, ~GQL\"\"\"
        query GetUser($id: ID!) {
          user(id: $id) {
            name
            email
          }
        }
      \"\"\"
  """
  defmacro sigil_GQL(query_string, _modifiers) do
    # Uppercase sigils receive an already-interpolated binary in Elixir,
    # so we simply return it as-is. The value is the formatter hook.
    query_string
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

  # Handle ~GQL sigil AST — the sigil doesn't expand before defgql receives it,
  # so we pattern-match the AST node and extract the binary string.
  defp define_query_function(
         kind,
         func_name,
         {:sigil_GQL, _meta, [{:<<>>, _bin_meta, [query_str]}, _modifiers]}
       )
       when is_atom(func_name) and is_binary(query_str) do
    define_query_function(kind, func_name, query_str)
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
