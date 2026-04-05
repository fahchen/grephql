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

  @doc false
  @spec field_def_to_ast({atom(), atom(), term(), keyword()}) :: Macro.t()
  def field_def_to_ast({kind, name, type_or_schema, opts}) do
    quote do: unquote(kind)(unquote(name), unquote(type_or_schema), unquote(opts))
  end

  @doc false
  @spec camelize(atom()) :: String.t()
  def camelize(name) when is_atom(name), do: name |> Atom.to_string() |> Macro.camelize()

  @doc false
  @spec camelize(String.t()) :: String.t()
  def camelize(name) when is_binary(name), do: Macro.camelize(name)

  @doc false
  @spec embed_typed_opts(:embeds_one | :embeds_many, Grephql.TypeMapper.resolve_result()) ::
          keyword()
  def embed_typed_opts(:embeds_one, %{nullable: true}), do: [null: true]
  def embed_typed_opts(_kind, _resolved), do: []

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
    type_ast = ecto_type |> ecto_type_to_type_ast() |> maybe_nullable(opts)
    {field_name, type_ast}
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

  @doc false
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
