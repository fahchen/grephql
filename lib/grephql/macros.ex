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

  @doc false
  @spec __build_doc__(Grephql.Query.t()) :: String.t()
  def __build_doc__(%Grephql.Query{} = query) do
    prefix = inspect(query.client_module) <> "."

    [doc_header(query), doc_variables(query.variable_docs), doc_modules(query, prefix)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp doc_header(query) do
    op_type = query.operation_type
    op_name = query.operation_name

    if op_name do
      "Executes the `#{op_name}` GraphQL #{op_type}."
    else
      "Executes a GraphQL #{op_type}."
    end
  end

  defp doc_variables([]), do: nil

  defp doc_variables(variable_docs) do
    rows =
      Enum.map_join(variable_docs, "\n", fn var ->
        req = if var.required, do: "required", else: "optional"
        "| `#{var.name}` | `#{var.type}` | #{req} |"
      end)

    """
    ## Variables

    | Name | Type | |
    |------|------|-|
    #{rows}\
    """
  end

  defp doc_modules(query, prefix) do
    short = &short_module(&1, prefix)

    result_lines = Enum.map(query.result_modules, &"- `#{short.(&1)}`")

    vars_lines =
      if query.variables_module,
        do: ["- `#{short.(query.variables_module)}`"],
        else: []

    input_lines = Enum.map(query.input_modules, &"- `#{short.(&1)}`")

    all_lines = result_lines ++ vars_lines ++ input_lines

    "## Generated Modules\n\n" <> Enum.join(all_lines, "\n")
  end

  defp short_module(module, prefix) do
    full = inspect(module)

    case String.split_at(full, String.length(prefix)) do
      {^prefix, rest} -> ~s|#{"\#{__MODULE__}."}#{rest}|
      _other -> full
    end
  end

  @doc false
  @spec __resolve_fragments__(String.t(), [Grephql.Compiler.fragment_entry()]) ::
          {String.t(), %{String.t() => Grephql.Compiler.fragment_entry()}}
  def __resolve_fragments__(query_str, fragment_entries) do
    fragment_map = build_fragment_map(fragment_entries)

    all_spread_names = fragment_spread_names(query_str)
    undefined = Enum.reject(all_spread_names, &Map.has_key?(fragment_map, &1))

    if undefined != [] do
      names = Enum.map_join(undefined, ", ", &"...#{&1}")
      raise CompileError, description: "undefined fragment spread: #{names}"
    end

    {_seen, used_names} = collect_spread_names(query_str, fragment_map, MapSet.new(), [])
    used_names = Enum.reverse(used_names)

    appended = Enum.map_join(used_names, "\n", fn name -> fragment_map[name].source end)

    full_query = if appended == "", do: query_str, else: query_str <> "\n" <> appended
    used_map = Map.take(fragment_map, used_names)

    {full_query, used_map}
  end

  defp build_fragment_map(fragment_entries) do
    fragment_entries
    |> Enum.reverse()
    |> Map.new(fn entry -> {entry.fragment.name, entry} end)
  end

  @fragment_spread_pattern ~r/\.\.\.\s*([_A-Za-z][_0-9A-Za-z]*)/

  # Dialyzer incorrectly flags MapSet as opaque in recursive calls
  @spec collect_spread_names(String.t(), map(), MapSet.t(String.t()), [String.t()]) ::
          {MapSet.t(String.t()), [String.t()]}
  @dialyzer {:no_opaque, collect_spread_names: 4}
  defp collect_spread_names(source, fragment_map, seen, acc) do
    Enum.reduce(fragment_spread_names(source), {seen, acc}, fn name, {seen_acc, acc_acc} ->
      if MapSet.member?(seen_acc, name) do
        {seen_acc, acc_acc}
      else
        next_spread_names(name, fragment_map, seen_acc, acc_acc)
      end
    end)
  end

  @spec next_spread_names(String.t(), map(), MapSet.t(String.t()), [String.t()]) ::
          {MapSet.t(String.t()), [String.t()]}
  @dialyzer {:no_opaque, next_spread_names: 4}
  defp next_spread_names(name, fragment_map, seen, acc) do
    seen = MapSet.put(seen, name)

    case Map.fetch(fragment_map, name) do
      {:ok, entry} ->
        collect_spread_names(entry.source, fragment_map, seen, [name | acc])

      :error ->
        {seen, acc}
    end
  end

  defp fragment_spread_names(source) do
    @fragment_spread_pattern
    |> Regex.scan(source)
    |> Enum.map(fn [_full, name] -> name end)
    |> Enum.reject(&(&1 == "on"))
  end

  @doc """
  Defines a reusable named GraphQL fragment.

  At compile time, parses and validates the fragment against the schema,
  then registers it in the module for use by `defgql`/`defgqlp`. When a
  query uses `...FragmentName`, the fragment definition is automatically
  appended to the query string sent to the server.

  The fragment name is inferred from the GraphQL definition itself
  (`fragment UserFields on User { ... }`), so no separate Elixir name is
  required.

  Fragments are resolved lexically: a `defgql` sees only the fragments
  defined before it in the module body. If the same fragment name is
  defined multiple times before a `defgql`, the latest definition wins.

  ## Examples

      deffragment ~GQL\"\"\"
      fragment UserFields on User {
        name
        email
      }
      \"\"\"

      defgql :get_user, ~GQL\"\"\"
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserFields
        }
      }
      \"\"\"
  """
  defmacro deffragment(fragment_string) do
    define_fragment(fragment_string)
  end

  # ~GQL sigil doesn't expand before deffragment receives it — extract the binary
  defp define_fragment({:sigil_GQL, _meta, [{:<<>>, _bin_meta, [frag_str]}, _modifiers]})
       when is_binary(frag_str) do
    define_fragment(frag_str)
  end

  defp define_fragment(frag_str_ast) do
    quote bind_quoted: [frag_str: frag_str_ast] do
      @grephql_fragments Grephql.Compiler.compile_fragment!(
                           frag_str,
                           @grephql_schema,
                           client_module: __MODULE__,
                           scalar_types: @grephql_scalars,
                           caller_env: __ENV__
                         )
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

  # Handle interpolated strings — bind_quoted evaluates at compile time.
  defp define_query_function(kind, func_name, {:<<>>, _meta, _parts} = query_str_ast)
       when is_atom(func_name) do
    build_query_ast(kind, func_name, query_str_ast)
  end

  defp define_query_function(kind, func_name, query_str)
       when is_atom(func_name) and is_binary(query_str) do
    build_query_ast(kind, func_name, query_str)
  end

  defp build_query_ast(kind, func_name, query_str_ast) do
    function_ast = build_function_ast(kind, func_name)

    quote bind_quoted: [func_name: func_name, query_str: query_str_ast],
          unquote: true do
      {grephql_full_query, grephql_fragments} =
        Grephql.Macros.__resolve_fragments__(query_str, @grephql_fragments)

      @grephql_query Grephql.Compiler.compile!(
                       grephql_full_query,
                       @grephql_schema,
                       client_module: __MODULE__,
                       function_name: func_name,
                       scalar_types: @grephql_scalars,
                       caller_env: __ENV__,
                       fragments: grephql_fragments
                     )

      unquote(function_ast)
    end
  end

  defp build_function_ast(kind, func_name) do
    doc_ast = if kind == :def, do: quote(do: @doc(Grephql.Macros.__build_doc__(@grephql_query)))

    quote do
      unquote(doc_ast)

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
              {:ok, Grephql.Result.t(unquote(result_module).t())}
              | {:error, Ecto.Changeset.t()}
              | {:error, Req.Response.t()}
    end
  end

  @doc false
  defmacro __define_spec_without_vars__(name, result_module) do
    quote bind_quoted: [name: name, result_module: result_module] do
      @spec unquote(name)(keyword()) ::
              {:ok, Grephql.Result.t(unquote(result_module).t())}
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
