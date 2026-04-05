defmodule Grephql.Macros do
  @moduledoc false

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
                       scalar_types: @grephql_scalars
                     )

      unquote(function_ast)
    end
  end

  defp build_function_ast(kind, func_name) do
    with_vars = build_with_variables(kind, func_name)
    without_vars = build_without_variables(kind, func_name)

    quote do
      if @grephql_query.has_variables? do
        unquote(with_vars)
      else
        unquote(without_vars)
      end
    end
  end

  defp build_with_variables(:def, name) do
    quote do
      def unquote(name)(variables, opts \\ []) do
        Grephql.execute(@grephql_query, variables, opts)
      end
    end
  end

  defp build_with_variables(:defp, name) do
    quote do
      defp unquote(name)(variables, opts \\ []) do
        Grephql.execute(@grephql_query, variables, opts)
      end
    end
  end

  defp build_without_variables(:def, name) do
    quote do
      def unquote(name)(opts \\ []) do
        Grephql.execute(@grephql_query, %{}, opts)
      end
    end
  end

  defp build_without_variables(:defp, name) do
    quote do
      defp unquote(name)(opts \\ []) do
        Grephql.execute(@grephql_query, %{}, opts)
      end
    end
  end
end
