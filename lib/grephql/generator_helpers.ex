defmodule Grephql.GeneratorHelpers do
  @moduledoc false

  @doc """
  Builds `source:` option for Ecto field/embed when the snake_case atom name
  differs from the original GraphQL field name (camelCase).
  """
  @spec source_opt(atom(), String.t()) :: keyword()
  def source_opt(atom_name, original_name) when is_atom(atom_name) and is_binary(original_name) do
    if Atom.to_string(atom_name) != original_name do
      # GraphQL field names from schema, bounded set
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      [source: String.to_atom(original_name)]
    else
      []
    end
  end

  @spec field_def_to_ast({atom(), atom(), term(), keyword()}) :: Macro.t()
  def field_def_to_ast({kind, name, type_or_schema, opts}) do
    quote do: unquote(kind)(unquote(name), unquote(type_or_schema), unquote(opts))
  end

  @spec camelize(atom()) :: String.t()
  def camelize(name) when is_atom(name), do: name |> Atom.to_string() |> Macro.camelize()

  @spec camelize(String.t()) :: String.t()
  def camelize(name) when is_binary(name), do: Macro.camelize(name)

  @spec embed_typed_opts(:embeds_one | :embeds_many, Grephql.TypeMapper.resolve_result()) ::
          keyword()
  def embed_typed_opts(:embeds_one, %{nullable: true}), do: [null: true]
  def embed_typed_opts(_kind, _resolved), do: []

  @doc """
  Builds extra field opts for enum types (`:values` for `Grephql.Types.Enum`).
  Returns `[]` for non-enum types.
  """
  @spec enum_opts(Grephql.TypeMapper.resolve_result()) :: keyword()
  def enum_opts(%{enum_values: values}) when is_list(values), do: [values: values]
  def enum_opts(_resolved), do: []

  @doc """
  Builds extra field opts for typename types (`:values` for `Grephql.Types.Typename`).
  Returns `[]` for non-typename types.
  """
  @spec typename_opts(map()) :: keyword()
  def typename_opts(%{typename_values: values}) when is_list(values), do: [values: values]
  def typename_opts(_resolved), do: []

  @doc """
  Builds `typed:` options for a scalar field, including enum type override.
  """
  @spec scalar_typed_opts(Grephql.TypeMapper.resolve_result()) :: keyword()
  def scalar_typed_opts(resolved) do
    typed_opts = if resolved.nullable, do: [null: true], else: [null: false]

    case resolved.enum_values do
      values when is_list(values) ->
        type_ast = enum_type_ast(values, inner_nullable: resolved.inner_nullable)
        Keyword.put(typed_opts, :type, type_ast)

      _no_enum ->
        typed_opts
    end
  end

  @doc """
  Builds a quoted union type AST from enum values for use in `typed: [type: ...]`.

  Given `["OPEN", "CLOSED"]`, returns AST for `:open | :closed`.
  When `inner_nullable: true`, appends `| nil` (for list elements like `[Role]`).
  """
  @spec enum_type_ast([String.t()], keyword()) :: Macro.t()
  def enum_type_ast(values, opts \\ []) when is_list(values) do
    # Enum values from the schema are compile-time constants, not runtime user input
    atoms =
      Enum.map(values, fn val ->
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        val |> Macro.underscore() |> String.to_atom()
      end)

    base =
      List.foldr(atoms, nil, fn
        atom_val, nil -> atom_val
        atom_val, acc -> {:|, [], [atom_val, acc]}
      end)

    if opts[:inner_nullable], do: {:|, [], [base, nil]}, else: base
  end

  @doc """
  Builds a quoted `@type params()` map literal from field definitions.

  Generates `%{required(:name) => String.t(), optional(:email) => String.t() | nil}`.
  Embeds reference the nested module's `params()` type.
  """
  @spec build_params_type_ast(list(), [atom()]) :: Macro.t()
  def build_params_type_ast(field_defs, required_names) do
    map_fields =
      Enum.map(field_defs, fn field_def ->
        {name, type_ast} = field_def_to_type_ast(field_def)
        req_or_opt = if name in required_names, do: :required, else: :optional
        {{req_or_opt, [], [name]}, type_ast}
      end)

    {:%{}, [], map_fields}
  end

  defp field_def_to_type_ast({:field, field_name, ecto_type, opts}) do
    base_type =
      case get_in(opts, [:typed, :type]) do
        nil -> ecto_type_to_type_ast(ecto_type)
        custom_type -> custom_type
      end

    {field_name, maybe_nullable(base_type, opts)}
  end

  defp field_def_to_type_ast({:embeds_one, name, schema_module, opts}) do
    type_ast = maybe_nullable(quote(do: unquote(schema_module).params()), opts)
    {name, type_ast}
  end

  defp field_def_to_type_ast({:embeds_many, name, schema_module, opts}) do
    inner = quote(do: unquote(schema_module).params())
    type_ast = maybe_nullable(quote(do: [unquote(inner)]), opts)
    {name, type_ast}
  end

  defp maybe_nullable(type_ast, opts) do
    if nullable_from_opts(opts) do
      quote(do: unquote(type_ast) | nil)
    else
      type_ast
    end
  end

  defp nullable_from_opts(opts) do
    case Keyword.get(opts, :typed, []) do
      typed when is_list(typed) -> Keyword.get(typed, :null, true)
      _other -> true
    end
  end

  @spec ecto_type_to_type_ast(Grephql.TypeMapper.ecto_type()) :: Macro.t()
  def ecto_type_to_type_ast(:string), do: quote(do: String.t())
  def ecto_type_to_type_ast(:integer), do: quote(do: integer())
  def ecto_type_to_type_ast(:float), do: quote(do: float())
  def ecto_type_to_type_ast(:boolean), do: quote(do: boolean())

  def ecto_type_to_type_ast({:array, inner}) do
    inner_ast = ecto_type_to_type_ast(inner)
    quote(do: [unquote(inner_ast)])
  end

  def ecto_type_to_type_ast(module) when is_atom(module) do
    quote(do: unquote(module).t())
  end

  @doc """
  Creates multiple modules from `{module_name, quoted_ast}` tuples.

  Uses `Kernel.ParallelCompiler.pmap/2` (Elixir 1.16+) so that spawned
  processes can resolve dependencies via `Code.ensure_compiled/1` and the
  Mix compiler tracks the generated `.beam` files. Falls back to sequential
  creation on older Elixir versions or outside a compiler session.
  """
  @spec create_modules([{module(), Macro.t()}]) :: :ok
  def create_modules(module_asts) do
    location = Macro.Env.location(__ENV__)
    create_fn = fn {mod, ast} -> Module.create(mod, ast, location) end

    # Remove function_exported? guard when dropping Elixir 1.15 support
    if function_exported?(Kernel.ParallelCompiler, :pmap, 2) do
      try do
        Kernel.ParallelCompiler.pmap(module_asts, create_fn)
      rescue
        # pmap/2 raises when no compiler session is active or when the
        # session is interrupted (e.g. inside capture_io in tests).
        _error in [ArgumentError, MatchError] ->
          Enum.each(module_asts, create_fn)
      end
    else
      Enum.each(module_asts, create_fn)
    end

    :ok
  end

  @doc """
  Reverses accumulated field definitions and extracts cast field names.

  Takes the reversed accumulators from a reduce pass and returns
  `{field_defs, cast_fields, embed_names, required_names}` ready
  for `create_input_schema/5`.
  """
  @spec prepare_schema_fields(list(), list(), list()) ::
          {list(), [atom()], list(), list()}
  def prepare_schema_fields(field_defs, embed_names, required_names) do
    field_defs = :lists.reverse(field_defs)
    embed_names = :lists.reverse(embed_names)
    required_names = :lists.reverse(required_names)
    cast_fields = for {:field, name, _type, _opts} <- field_defs, do: name

    {field_defs, cast_fields, embed_names, required_names}
  end
end
