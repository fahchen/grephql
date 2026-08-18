defmodule TypedGql.GeneratorHelpers do
  @moduledoc false

  alias TypedGql.Generation.Plugin

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

  @spec embed_typed_opts(:embeds_one | :embeds_many, TypedGql.TypeMapper.resolve_result()) ::
          keyword()
  def embed_typed_opts(:embeds_one, %{nullable: true}), do: [null: true]
  def embed_typed_opts(_kind, _resolved), do: []

  @doc """
  Builds extra field opts for enum types (`:values` for `TypedGql.Types.Enum`).
  Returns `[]` for non-enum types.
  """
  @spec enum_opts(TypedGql.TypeMapper.resolve_result()) :: keyword()
  def enum_opts(%{enum_values: values}) when is_list(values), do: [values: values]
  def enum_opts(_resolved), do: []

  @doc """
  Builds extra field opts for typename types (`:values` for `TypedGql.Types.Typename`).
  Returns `[]` for non-typename types.
  """
  @spec typename_opts(map()) :: keyword()
  def typename_opts(%{typename_values: values}) when is_list(values), do: [values: values]
  def typename_opts(_resolved), do: []

  @doc """
  Splits an Ecto type into its innermost element and how many lists wrap it:
  `{:array, {:array, Foo}}` gives `{Foo, 2}`.
  """
  @spec unwrap_list(TypedGql.TypeMapper.ecto_type()) ::
          {TypedGql.TypeMapper.ecto_type(), integer()}
  def unwrap_list({:array, inner}) do
    {leaf, depth} = unwrap_list(inner)
    {leaf, depth + 1}
  end

  def unwrap_list(leaf), do: {leaf, 0}

  @doc """
  Builds `typed:` options for a scalar field, including enum type override.
  """
  @spec scalar_typed_opts(TypedGql.TypeMapper.resolve_result()) :: keyword()
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
      case Keyword.get(typed_opts(opts), :type) do
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
    Keyword.get(typed_opts(opts), :null, true)
  end

  # A plugin's after_lower may rewrite a field def; whatever non-keyword shape
  # its typed: option takes, the safe reading is no options — a nullable field
  # with a derived typespec, wider than the truth but never lying.
  defp typed_opts(opts) do
    case Keyword.get(opts, :typed, []) do
      typed when is_list(typed) -> typed
      _other -> []
    end
  end

  @spec ecto_type_to_type_ast(TypedGql.TypeMapper.ecto_type()) :: Macro.t()
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

  @created_key {__MODULE__, :created_modules}

  @doc """
  Whether this compilation has already created `module`.

  `Code.ensure_loaded?/1` answers a different question — whether the module is
  loadable *yet* — and the parallel compiler decides that on its own schedule,
  which changed in Elixir 1.19. A caller that skips work for a module it
  already generated needs an answer that does not move with the compiler.
  """
  @spec created?(module()) :: boolean()
  def created?(module) when is_atom(module) do
    MapSet.member?(Process.get(@created_key, MapSet.new()), module)
  end

  defp record_created(module) do
    Process.put(@created_key, MapSet.put(Process.get(@created_key, MapSet.new()), module))
  end

  @doc """
  Creates multiple modules from `{module_name, quoted_ast, create_opts}` tuples.

  `create_opts` says where the module comes from, so tooling like editor "go to
  definition" lands on the caller's `defgql` rather than wherever inside
  typed_gql the module happens to be compiled. Passing the caller's `Macro.Env`
  is enough — `Module.create/3` takes the file and line off it. It is specified
  per module because each generated module records its own source location.

  Uses `Kernel.ParallelCompiler.pmap/2` (Elixir 1.16+) so that spawned
  processes can resolve dependencies via `Code.ensure_compiled/1` and the
  Mix compiler tracks the generated `.beam` files. Falls back to sequential
  creation on older Elixir versions or outside a compiler session.
  """
  @spec create_modules([{module(), Macro.t(), Plugin.module_create_opts()}]) :: :ok
  # pmap/2 does not short-circuit an empty collection: it registers as waiting
  # on the compiler and blocks on a receive until released, whatever the
  # collection. The compiler runs deadlock resolution once every file it is
  # compiling sits in `waiting`, and pmap registers as `:raise`, which none of
  # the release passes handle — so a build where every remaining file is parked
  # in an empty pmap fails with `deadlocked waiting on pmap []`.
  #
  # It takes two or more such files and no other file making progress, which is
  # an incremental rebuild of a couple of client modules — a full build always
  # has other work in flight, which is why this survived CI.
  #
  # This is Elixir's to fix, not ours: `def pmap([], fun), do: []` upstream ends
  # it for everyone. We are not reporting it, so this clause stays. Reproduce it
  # with two files that each call `Kernel.ParallelCompiler.pmap([], & &1)`,
  # compiled by `Kernel.ParallelCompiler.compile/1` on a cold VM — warm, the
  # release message wins the race and it passes.
  def create_modules([]), do: :ok

  def create_modules(module_asts) do
    create_fn = fn {mod, ast, create_opts} -> Module.create(mod, ast, create_opts) end
    Enum.each(module_asts, fn {module, _ast, _create_opts} -> record_created(module) end)

    try do
      # apply/3 so Elixir 1.15 (no pmap/2) still compiles; the rescue covers both
      # UndefinedFunctionError there and pmap/2 raising when no compiler session
      # is active or the session is interrupted (e.g. inside capture_io in tests).
      #
      # TODO: once the minimum Elixir is 1.16, call pmap/2 directly and drop
      # UndefinedFunctionError from the rescue — the try/rescue itself stays,
      # since pmap/2 still raises outside a compiler session on every version.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Kernel.ParallelCompiler, :pmap, [module_asts, create_fn])
    rescue
      _error in [ArgumentError, MatchError, UndefinedFunctionError] ->
        Enum.each(module_asts, create_fn)
    end

    :ok
  end

  @doc """
  Builds the compile error for spreads naming a fragment that is not in scope.

  Names the second, likelier cause alongside the obvious one: `deffragment`
  resolves lexically, so a fragment defined further down the module is not
  visible yet.
  """
  @spec undefined_spread_message([String.t()]) :: String.t()
  def undefined_spread_message(names) do
    """
    undefined fragment spread: #{Enum.map_join(names, ", ", &"...#{&1}")}

    Either no fragment of that name is defined, or it is defined after this
    point: a deffragment compiles as it is expanded, so it sees only the
    fragments above it. GraphQL forbids fragment cycles, so the definitions
    form a DAG and can always be reordered to put each one before its uses.
    Fragments defined inside a single query string are exempt — there, order
    does not matter.\
    """
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
